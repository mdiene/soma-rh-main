-- D-30 / D-53 : un bulletin ne peut pas avoir un net à payer négatif ; la retenue mensuelle d'un prêt est plafonnée
-- à une part du brut, paramétrable par l'administrateur, la paie ou les RH (table app_parameters).
-- Rollback : db/rollback/20261107130000_d30_d53_net_negatif_plafond_pret_down.sql

-- ---------------------------------------------------------------- paramètres applicatifs
create table if not exists public.app_parameters (
  code        text primary key,
  label       text not null,
  value       numeric not null,
  updated_by  uuid references auth.users(id) on delete set null,
  updated_at  timestamptz not null default now()
);
create index if not exists app_parameters_updated_by_idx on public.app_parameters (updated_by);
alter table public.app_parameters enable row level security;
drop policy if exists app_parameters_read on public.app_parameters;
create policy app_parameters_read on public.app_parameters for select to authenticated
  using ((select public.has_role(array['admin', 'rh', 'paie'])));
revoke insert, update, delete on public.app_parameters from anon, authenticated;
grant select on public.app_parameters to authenticated;

insert into public.app_parameters (code, label, value)
values ('loan_max_rate', 'Plafond de la retenue mensuelle de prêt (part du brut)', 0.33)
on conflict (code) do nothing;

drop trigger if exists app_parameters_audit on public.app_parameters;
create trigger app_parameters_audit after insert or update or delete on public.app_parameters
  for each row execute function public.business_audit();

create or replace function public.get_loan_max_rate()
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select value from public.app_parameters where code = 'loan_max_rate'), 0.33);
$$;

create or replace function public.set_loan_max_rate(p_rate numeric)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['admin', 'rh', 'paie']) then
    raise exception 'Droits insuffisants : administrateur, RH ou paie requis pour modifier le plafond de retenue';
  end if;
  if p_rate is null or p_rate <= 0 or p_rate > 1 then
    raise exception 'Le plafond doit être compris entre 0 et 1 (0,33 = 33 %% du brut)';
  end if;
  insert into public.app_parameters (code, label, value, updated_by)
  values ('loan_max_rate', 'Plafond de la retenue mensuelle de prêt (part du brut)', p_rate, auth.uid())
  on conflict (code) do update set value = excluded.value, updated_by = auth.uid(), updated_at = now();
  return p_rate;
end;
$$;
revoke all on function public.get_loan_max_rate() from public, anon;
revoke all on function public.set_loan_max_rate(numeric) from public, anon;
grant execute on function public.get_loan_max_rate() to authenticated;
grant execute on function public.set_loan_max_rate(numeric) to authenticated;

-- ---------------------------------------------------------------- création de prêt plafonnée
create or replace function public.create_loan(
  p_employee_id uuid, p_label text, p_principal numeric, p_installments integer,
  p_first_period date, p_request_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_first date := date_trunc('month', p_first_period)::date;
  v_each numeric;
  v_first_amount numeric;
  v_rate numeric := public.get_loan_max_rate();
  v_brut numeric;
  v_existing numeric;
  i integer;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis pour accorder un prêt';
  end if;
  if p_principal is null or p_principal <= 0 then raise exception 'Le montant du prêt doit être strictement positif'; end if;
  if p_installments is null or p_installments < 1 or p_installments > 60 then
    raise exception 'Le nombre d''échéances doit être compris entre 1 et 60';
  end if;
  if p_principal <> round(p_principal) then raise exception 'Le montant du prêt doit être en francs entiers (FCFA)'; end if;
  if p_principal < p_installments then
    raise exception 'Le montant du prêt (%) doit être au moins égal au nombre d''échéances (%)', p_principal, p_installments;
  end if;
  if exists (select 1 from public.payroll_entries
              where date_trunc('month', period_start)::date >= v_first and status in ('Validée', 'Payée', 'Clôturée')) then
    raise exception 'La première échéance (%) tombe dans un mois dont la paie est déjà validée : choisissez le premier mois non validé', to_char(v_first, 'MM/YYYY');
  end if;
  if not exists (select 1 from public.employees where id = p_employee_id and status = 'Active') then
    raise exception 'Salarié introuvable ou inactif';
  end if;
  if coalesce(trim(p_label), '') = '' then raise exception 'Un libellé est obligatoire'; end if;

  -- D-30 : plafond de retenue = taux paramétré x brut mensuel (dernier bulletin, sinon structure salariale)
  select s.gross_pay into v_brut from public.salary_slips s
   where s.employee_id = p_employee_id and s.status <> 'Annulé' and s.gross_pay > 0
   order by s.period_start desc limit 1;
  if v_brut is null then
    select coalesce(a.base_salary, 0) + a.sursalaire + a.fees + a.other_fixed into v_brut
      from public.salary_structure_assignments a
     where a.employee_id = p_employee_id and a.from_date <= current_date
     order by a.from_date desc limit 1;
  end if;
  v_each := floor(p_principal / p_installments);
  v_first_amount := greatest(v_each, p_principal - v_each * (p_installments - 1));
  select coalesce(sum(i2.amount), 0) into v_existing
    from public.loan_installments i2 join public.loans l2 on l2.id = i2.loan_id
   where l2.employee_id = p_employee_id and l2.status = 'Actif' and i2.status = 'Prévue' and i2.due_period = v_first;
  if coalesce(v_brut, 0) <= 0 then
    raise exception 'Prêt impossible : aucun salaire de référence pour ce salarié (structure salariale absente ou nulle)';
  end if;
  if v_first_amount + v_existing > floor(v_brut * v_rate) then
    raise exception 'Retenue mensuelle trop élevée : % F (dont % F de prêts en cours) pour un plafond de % F (% %% du brut de % F). Augmentez le nombre d''échéances ou réduisez le montant.',
      round(v_first_amount + v_existing), round(v_existing), floor(v_brut * v_rate), round(v_rate * 100, 1), round(v_brut);
  end if;

  insert into public.loans (employee_id, label, principal, installments, first_period, request_id)
  values (p_employee_id, trim(p_label), p_principal, p_installments, v_first, p_request_id)
  returning id into v_id;

  -- échéances entières ; la dernière absorbe le reste : somme des échéances = capital exactement
  for i in 1..p_installments loop
    insert into public.loan_installments (loan_id, due_period, amount)
    values (v_id, (v_first + make_interval(months => i - 1))::date,
            case when i = p_installments then p_principal - v_each * (p_installments - 1) else v_each end);
  end loop;
  return v_id;
end;
$$;
revoke all on function public.create_loan(uuid, text, numeric, integer, date, uuid) from public, anon;
grant execute on function public.create_loan(uuid, text, numeric, integer, date, uuid) to authenticated;

-- ---------------------------------------------------------------- D-30 / D-53 : jamais de net négatif
create or replace function public.salary_slip_non_negative_net()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_who text;
begin
  if new.status <> 'Annulé' and new.net_pay < 0 then
    select e.employee_number || ' ' || e.last_name || ' ' || e.first_name into v_who from public.employees e where e.id = new.employee_id;
    raise exception 'Bulletin refusé : le net à payer de % serait négatif (% F). Vérifiez ses retenues (prêts, régularisations) et sa structure salariale.',
      coalesce(v_who, new.employee_id::text), round(new.net_pay);
  end if;
  return new;
end;
$$;
drop trigger if exists salary_slips_non_negative_net on public.salary_slips;
create trigger salary_slips_non_negative_net
before insert or update of net_pay, status on public.salary_slips
for each row execute function public.salary_slip_non_negative_net();

notify pgrst, 'reload schema';
