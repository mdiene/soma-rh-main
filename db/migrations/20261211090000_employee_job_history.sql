-- =============================================================================
-- Historique des emplois : emplois successifs d'un salarié, avec leurs dates (art. 140 du Code du travail 2026 : le certificat de
-- travail indique « la nature et les dates des emplois successifs »). Un salarié n'occupe qu'un emploi à la fois : pas de chevauchement.
-- Alimenté automatiquement quand employees.designation_id ou grade_id change ; la RH corrige ou complète à la main.
-- Retour : db/rollback/20261211090000_employee_job_history_down.sql
-- =============================================================================
create table public.employee_job_history (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid not null references public.employees(id) on delete cascade,
  designation_id uuid references public.designations(id) on delete set null,
  title          text not null check (length(btrim(title)) > 0),   -- libellé figé au moment de la saisie
  grade_id       uuid references public.employee_grades(id) on delete set null,
  valid_from     date not null,
  valid_to       date,                                              -- inclus ; vide = emploi en cours
  note           text,
  created_by     uuid default auth.uid() references auth.users(id) on delete set null,
  created_at     timestamptz not null default now(),
  check (valid_to is null or valid_to >= valid_from),
  exclude using gist (employee_id with =, daterange(valid_from, valid_to, '[]') with &&)
);
create index employee_job_history_employee_idx on public.employee_job_history(employee_id, valid_from);
create index employee_job_history_designation_idx on public.employee_job_history(designation_id);
create index employee_job_history_grade_idx on public.employee_job_history(grade_id);
create index employee_job_history_created_by_idx on public.employee_job_history(created_by);

alter table public.employee_job_history enable row level security;
create policy employee_job_history_read on public.employee_job_history for select to authenticated
  using ((select public.has_role(array['rh', 'paie'])));
create policy employee_job_history_write on public.employee_job_history for all to authenticated
  using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));
create trigger employee_job_history_audit after insert or update or delete on public.employee_job_history
  for each row execute function public.business_audit();

-- Suit l'emploi et la catégorie portés par la fiche salarié.
create or replace function public.employee_job_history_sync() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_open public.employee_job_history; v_title text;
begin
  if new.designation_id is null then return null; end if;
  select name into v_title from public.designations where id = new.designation_id;
  if tg_op = 'INSERT' then
    insert into public.employee_job_history(employee_id, designation_id, title, grade_id, valid_from)
    values (new.id, new.designation_id, coalesce(v_title, 'Emploi'), new.grade_id, new.date_of_joining);
    return null;
  end if;
  if new.designation_id is not distinct from old.designation_id and new.grade_id is not distinct from old.grade_id then return null; end if;
  select * into v_open from public.employee_job_history where employee_id = new.id and valid_to is null order by valid_from desc limit 1;
  if v_open.id is null then
    insert into public.employee_job_history(employee_id, designation_id, title, grade_id, valid_from)
    values (new.id, new.designation_id, coalesce(v_title, 'Emploi'), new.grade_id, greatest(new.date_of_joining, current_date));
  elsif v_open.valid_from >= current_date then
    -- changement le jour même ou daté du futur : correction de l'emploi en cours, pas de période vide
    update public.employee_job_history set designation_id = new.designation_id, title = coalesce(v_title, 'Emploi'), grade_id = new.grade_id where id = v_open.id;
  else
    update public.employee_job_history set valid_to = current_date - 1 where id = v_open.id;
    insert into public.employee_job_history(employee_id, designation_id, title, grade_id, valid_from)
    values (new.id, new.designation_id, coalesce(v_title, 'Emploi'), new.grade_id, current_date);
  end if;
  return null;
end $$;
revoke execute on function public.employee_job_history_sync() from public, anon, authenticated;
create trigger employees_job_history_ins after insert on public.employees
  for each row execute function public.employee_job_history_sync();
create trigger employees_job_history_upd after update of designation_id, grade_id on public.employees
  for each row execute function public.employee_job_history_sync();

-- reprise de l'existant : l'emploi actuel depuis l'entrée (jusqu'à la sortie pour un salarié sorti)
insert into public.employee_job_history(employee_id, designation_id, title, grade_id, valid_from, valid_to, note)
select e.id, e.designation_id, d.name, e.grade_id, e.date_of_joining,
       case when e.status = 'Left' and e.relieving_date >= e.date_of_joining then e.relieving_date end, 'reprise'
  from public.employees e join public.designations d on d.id = e.designation_id
 where e.designation_id is not null;

notify pgrst, 'reload schema';
