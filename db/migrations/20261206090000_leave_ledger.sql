-- =============================================================================
-- L7-01 / L7-02 : registre des congés par écritures (leave_ledger), solde lu depuis le registre.
-- Une écriture = un mouvement signé en jours (+ attribution, - pris). Le registre est en ajout seul : toute correction
-- passe par une écriture inverse, jamais par une modification. Les écritures sont posées par des déclencheurs sur
-- leave_allocations et leave_applications (un congé « Approuvée » pèse -total_days ; s'il quitte cet état, une
-- écriture inverse le compense). Aucun taux d'indemnité ici : c'est L7-03 / L7-05, après confirmation du juriste.
-- Retour : db/rollback/20261206090000_leave_ledger_down.sql
-- =============================================================================
create table public.leave_ledger (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid not null references public.employees(id) on delete cascade,
  leave_type     text not null references public.leave_types(code) on update cascade,
  effective_date date not null,
  days           numeric not null check (days <> 0),
  kind           text not null check (kind in ('allocation', 'taken', 'reversal', 'adjustment')),
  source_table   text not null check (source_table in ('leave_allocations', 'leave_applications', 'manual')),
  source_id      uuid,
  note           text,
  created_by     uuid default auth.uid() references auth.users(id) on delete set null,
  created_at     timestamptz not null default now()
);
create index leave_ledger_emp_type_idx on public.leave_ledger(employee_id, leave_type, effective_date);
create index leave_ledger_source_idx on public.leave_ledger(source_table, source_id);
create index leave_ledger_type_idx on public.leave_ledger(leave_type);
create index leave_ledger_created_by_idx on public.leave_ledger(created_by);

alter table public.leave_ledger enable row level security;
-- mêmes visibilités que les congés : RH / paie, le salarié lui-même, le manager (et son délégué) de l'équipe
create policy leave_ledger_select on public.leave_ledger for select to authenticated
  using ((select public.has_role(array['rh', 'paie'])) or employee_id = (select public.my_employee_id()));
create policy leave_ledger_select_team on public.leave_ledger for select to authenticated
  using ((select public.can_see_leave(leave_ledger.employee_id, leave_ledger.effective_date)));
-- aucune politique d'écriture : seules les fonctions ci-dessous (security definer) écrivent
revoke insert, update, delete, truncate on public.leave_ledger from authenticated, anon;

-- ajout seul, même pour le propriétaire de la table
create or replace function public.leave_ledger_append_only() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'Le registre des congés est en ajout seul : posez une écriture inverse au lieu de modifier ou supprimer';
end $$;
create trigger leave_ledger_no_change before update or delete on public.leave_ledger
  for each row execute function public.leave_ledger_append_only();
create trigger leave_ledger_audit after insert on public.leave_ledger
  for each row execute function public.business_audit();

-- Pose les écritures qui ramènent une source (attribution ou demande) à l'état voulu ; idempotent.
create or replace function public.leave_ledger_sync() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid; v_emp uuid; v_type text; v_date date; v_want numeric := 0; v_have numeric; v_delta numeric; g record;
  v_alloc boolean := tg_table_name = 'leave_allocations';
begin
  if tg_op = 'DELETE' then
    v_id := old.id;
  else
    v_id := new.id; v_emp := new.employee_id; v_type := new.leave_type;
    if v_alloc then v_date := new.to_date; v_want := new.days;
    else v_date := new.from_date; v_want := case when new.status = 'Approuvée' then -new.total_days else 0 end; end if;
  end if;
  -- ancien jeu (salarié, type, date) abandonné par une modification ou une suppression : on le ramène à zéro
  for g in
    select employee_id, leave_type, effective_date, sum(days) as s from public.leave_ledger
     where source_table = tg_table_name and source_id = v_id
       and (tg_op = 'DELETE' or (employee_id, leave_type, effective_date) is distinct from (v_emp, v_type, v_date))
     group by 1, 2, 3 having sum(days) <> 0
  loop
    insert into public.leave_ledger(employee_id, leave_type, effective_date, days, kind, source_table, source_id, note)
    values (g.employee_id, g.leave_type, g.effective_date, -g.s, case when v_alloc then 'adjustment' else 'reversal' end, tg_table_name,
            v_id, case when tg_op = 'DELETE' then 'source supprimée' else 'source modifiée' end);
  end loop;
  if tg_op <> 'DELETE' then
    select coalesce(sum(days), 0) into v_have from public.leave_ledger
     where source_table = tg_table_name and source_id = v_id and employee_id = v_emp and leave_type = v_type and effective_date = v_date;
    v_delta := v_want - v_have;
    if v_delta <> 0 then
      insert into public.leave_ledger(employee_id, leave_type, effective_date, days, kind, source_table, source_id)
      values (v_emp, v_type, v_date, v_delta,
              case when v_alloc then (case when v_delta > 0 then 'allocation' else 'adjustment' end)
                   else (case when v_delta < 0 then 'taken' else 'reversal' end) end,
              tg_table_name, v_id);
    end if;
  end if;
  return null;
end $$;
revoke execute on function public.leave_ledger_sync(), public.leave_ledger_append_only() from public, anon, authenticated;

-- reprise de l'existant avant d'armer les déclencheurs
insert into public.leave_ledger(employee_id, leave_type, effective_date, days, kind, source_table, source_id, note)
select employee_id, leave_type, to_date, days, 'allocation', 'leave_allocations', id, 'reprise' from public.leave_allocations where days <> 0;
insert into public.leave_ledger(employee_id, leave_type, effective_date, days, kind, source_table, source_id, note)
select employee_id, leave_type, from_date, -total_days, 'taken', 'leave_applications', id, 'reprise' from public.leave_applications where status = 'Approuvée';

create trigger leave_allocations_ledger after insert or update or delete on public.leave_allocations
  for each row execute function public.leave_ledger_sync();
create trigger leave_applications_ledger after insert or update or delete on public.leave_applications
  for each row execute function public.leave_ledger_sync();

-- L7-02 : le solde est lu depuis le registre (mêmes colonnes, même fenêtre : année en cours)
create or replace view public.v_leave_balances with (security_invoker = true) as
 with alloc as (
   select l.employee_id, l.leave_type, sum(l.days) as allocated
     from public.leave_ledger l
    where l.source_table <> 'leave_applications' and l.effective_date >= date_trunc('year', current_date)
    group by l.employee_id, l.leave_type having sum(l.days) <> 0
 ), used as (
   select l.employee_id, l.leave_type, -sum(l.days) as taken
     from public.leave_ledger l
    where l.source_table = 'leave_applications' and l.effective_date >= date_trunc('year', current_date)
    group by l.employee_id, l.leave_type having sum(l.days) <> 0
 )
 select e.id as employee_id, e.employee_number, e.first_name, e.last_name, lt.code as leave_type, lt.name as leave_type_name,
        coalesce(a.allocated, 0::numeric) as allocated, coalesce(u.taken, 0::numeric) as taken,
        coalesce(a.allocated, 0::numeric) - coalesce(u.taken, 0::numeric) as balance
   from public.employees e
   cross join public.leave_types lt
   left join alloc a on a.employee_id = e.id and a.leave_type = lt.code
   left join used u on u.employee_id = e.id and u.leave_type = lt.code
  where e.status = 'Active' and (a.allocated is not null or u.taken is not null);
grant select on public.v_leave_balances to authenticated;

notify pgrst, 'reload schema';
