drop trigger if exists salary_slips_non_negative_net on public.salary_slips;
drop function if exists public.salary_slip_non_negative_net();
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

  insert into public.loans (employee_id, label, principal, installments, first_period, request_id)
  values (p_employee_id, trim(p_label), p_principal, p_installments, v_first, p_request_id)
  returning id into v_id;

  -- échéances entières ; la dernière absorbe le reste : somme des échéances = capital exactement
  v_each := floor(p_principal / p_installments);
  for i in 1..p_installments loop
    insert into public.loan_installments (loan_id, due_period, amount)
    values (v_id, (v_first + make_interval(months => i - 1))::date,
            case when i = p_installments then p_principal - v_each * (p_installments - 1) else v_each end);
  end loop;
  return v_id;
end;
$$;
drop function if exists public.set_loan_max_rate(numeric);
drop function if exists public.get_loan_max_rate();
drop table if exists public.app_parameters;
notify pgrst, 'reload schema';
