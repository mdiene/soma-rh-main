-- RPR-08 (décision du 09/11/2026) : plafond de retenue sur prêt.
--   * plafond global par défaut 1/3 du brut, modifiable par l'administrateur, le rôle rh ou le rôle paie (la base n'acceptait que l'admin) ;
--   * surcharge par salarié (table employee_loan_caps) modifiable par les mêmes rôles, avec motif ;
--   * journal (audit_events) : ancienne et nouvelle valeur, auteur ;
--   * create_loan lit la surcharge du salarié, sinon le plafond global. Règle D-30 inchangée (net jamais négatif).
-- Retour : db/rollback/20261214130000_rpr08_plafond_pret_down.sql

create table if not exists public.employee_loan_caps (
  employee_id uuid primary key references public.employees(id) on delete cascade,
  rate numeric not null check (rate > 0 and rate <= 1),
  reason text not null,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
comment on table public.employee_loan_caps is 'Plafond de retenue mensuelle de prêt propre à un salarié (part du brut) ; à défaut, plafond global app_parameters.loan_max_rate.';
alter table public.employee_loan_caps enable row level security;
drop policy if exists employee_loan_caps_select on public.employee_loan_caps;
create policy employee_loan_caps_select on public.employee_loan_caps for select to authenticated
  using ((select public.has_role(array['rh', 'paie'])));
-- aucune écriture directe : set_employee_loan_cap (security definer) journalise chaque changement

-- valeur par défaut 1/3 (décision) tant que personne n'a modifié le plafond
update public.app_parameters set value = round(1.0 / 3, 6) where code = 'loan_max_rate' and updated_by is null and value = 0.33;
-- valeur de référence du catalogue des constantes (utilisée par la réinitialisation)
update public.parameter_catalog set default_value = round(1.0 / 3, 6) where code = 'loan_max_rate' and default_value = 0.33;

CREATE OR REPLACE FUNCTION public.get_loan_max_rate()
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select value from public.app_parameters where code = 'loan_max_rate'), round(1.0 / 3, 6));
$function$;

create or replace function public.set_loan_max_rate(p_rate numeric)
 returns numeric
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old numeric := public.get_loan_max_rate();
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : administrateur, RH ou paie requis pour modifier le plafond de retenue';
  end if;
  if p_rate is null or p_rate <= 0 or p_rate > 1 then
    raise exception 'Le plafond doit être compris entre 0 et 1 (0,33 = 33 %% du brut)';
  end if;
  insert into public.app_parameters (code, label, value, updated_by)
  values ('loan_max_rate', 'Plafond de la retenue mensuelle de prêt (part du brut)', p_rate, auth.uid())
  on conflict (code) do update set value = excluded.value, updated_by = auth.uid(), updated_at = now();
  insert into public.audit_events (actor_id, action, resource_type, before_data, after_data)
  values (auth.uid(), 'plafond_pret_global', 'app_parameters', jsonb_build_object('rate', v_old), jsonb_build_object('rate', p_rate));
  return p_rate;
end;
$function$;

create or replace function public.get_employee_loan_cap(p_employee_id uuid)
 returns numeric
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select coalesce((select c.rate from public.employee_loan_caps c where c.employee_id = p_employee_id), public.get_loan_max_rate())
$function$;

-- p_rate null : supprime la surcharge (le salarié retombe sur le plafond global)
create or replace function public.set_employee_loan_cap(p_employee_id uuid, p_rate numeric, p_reason text)
 returns numeric
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old numeric;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : administrateur, RH ou paie requis pour modifier le plafond d''un salarié';
  end if;
  if not exists (select 1 from public.employees where id = p_employee_id) then raise exception 'Salarié introuvable'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'Un motif d''au moins 5 caractères est obligatoire'; end if;
  if p_rate is not null and (p_rate <= 0 or p_rate > 1) then
    raise exception 'Le plafond doit être compris entre 0 et 1 (0,33 = 33 %% du brut)';
  end if;
  select c.rate into v_old from public.employee_loan_caps c where c.employee_id = p_employee_id;
  if p_rate is null then
    delete from public.employee_loan_caps where employee_id = p_employee_id;
  else
    insert into public.employee_loan_caps (employee_id, rate, reason, updated_by) values (p_employee_id, p_rate, trim(p_reason), auth.uid())
    on conflict (employee_id) do update set rate = excluded.rate, reason = excluded.reason, updated_by = auth.uid(), updated_at = now();
  end if;
  insert into public.audit_events (actor_id, action, resource_type, resource_id, before_data, after_data, reason)
  values (auth.uid(), 'plafond_pret_salarie', 'employee', p_employee_id, jsonb_build_object('rate', v_old), jsonb_build_object('rate', p_rate), trim(p_reason));
  return public.get_employee_loan_cap(p_employee_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_loan(p_employee_id uuid, p_label text, p_principal numeric, p_installments integer, p_first_period date, p_request_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_first date := date_trunc('month', p_first_period)::date;
  v_each numeric;
  v_first_amount numeric;
  -- RPR-08 : surcharge du plafond propre au salarié, sinon plafond global
  v_rate numeric := coalesce((select c.rate from public.employee_loan_caps c where c.employee_id = p_employee_id), public.get_loan_max_rate());
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
$function$;

revoke execute on function public.get_loan_max_rate() from public, anon;
revoke execute on function public.set_loan_max_rate(numeric) from public, anon;
revoke execute on function public.get_employee_loan_cap(uuid) from public, anon;
revoke execute on function public.set_employee_loan_cap(uuid, numeric, text) from public, anon;
revoke execute on function public.create_loan(uuid, text, numeric, integer, date, uuid) from public, anon;
grant execute on function public.get_loan_max_rate() to authenticated, service_role;
grant execute on function public.set_loan_max_rate(numeric) to authenticated, service_role;
grant execute on function public.get_employee_loan_cap(uuid) to authenticated, service_role;
grant execute on function public.set_employee_loan_cap(uuid, numeric, text) to authenticated, service_role;
grant execute on function public.create_loan(uuid, text, numeric, integer, date, uuid) to authenticated, service_role;
notify pgrst, 'reload schema';
