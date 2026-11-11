-- Retour de RPR-08 : anciennes définitions, suppression de la surcharge par salarié.
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
$function$;

CREATE OR REPLACE FUNCTION public.get_loan_max_rate()
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select value from public.app_parameters where code = 'loan_max_rate'), 0.33);
$function$;

CREATE OR REPLACE FUNCTION public.set_loan_max_rate(p_rate numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not public.has_role(array['admin']) then
    raise exception 'Droits insuffisants : rôle « admin » requis pour modifier le plafond de retenue (les autres rôles passent par une demande de modification de constante)';
  end if;
  if p_rate is null or p_rate <= 0 or p_rate > 1 then
    raise exception 'Le plafond doit être compris entre 0 et 1 (0,33 = 33 %% du brut)';
  end if;
  insert into public.app_parameters (code, label, value, updated_by)
  values ('loan_max_rate', 'Plafond de la retenue mensuelle de prêt (part du brut)', p_rate, auth.uid())
  on conflict (code) do update set value = excluded.value, updated_by = auth.uid(), updated_at = now();
  return p_rate;
end;
$function$;

drop function if exists public.set_employee_loan_cap(uuid, numeric, text);
drop function if exists public.get_employee_loan_cap(uuid);
drop table if exists public.employee_loan_caps;
update public.app_parameters set value = 0.33 where code = 'loan_max_rate' and updated_by is null and value = round(1.0 / 3, 6);
update public.parameter_catalog set default_value = 0.33 where code = 'loan_max_rate' and default_value = round(1.0 / 3, 6);

revoke execute on function public.get_loan_max_rate() from public, anon;
revoke execute on function public.set_loan_max_rate(numeric) from public, anon;
revoke execute on function public.create_loan(uuid, text, numeric, integer, date, uuid) from public, anon;
grant execute on function public.get_loan_max_rate() to authenticated, service_role;
grant execute on function public.set_loan_max_rate(numeric) to authenticated, service_role;
grant execute on function public.create_loan(uuid, text, numeric, integer, date, uuid) to authenticated, service_role;
notify pgrst, 'reload schema';
