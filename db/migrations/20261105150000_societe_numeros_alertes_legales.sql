-- Audit SaaS (2026-11-05) :
--  1. Identité légale de l'employeur : numéros IPRES et CSS, convention collective appliquée (la société n'avait que NINEA et RCCM).
--  2. legal_alerts() : alertes réglementaires datées pour les RH et la paie (fin de CDD, salaire de base sous le SMIG
--     paramétré, pièce d'identité expirée). Les seuils viennent de payroll_settings à la date demandée, rien n'est codé en dur.
-- Les tables « taux légaux versionnés » et « grilles salariales » existent déjà : payroll_settings (effective_from) et
-- employee_grades (agreement_code, effective_from). Aucune table en double n'est créée.
-- Retour : db/rollback/20261105150000_societe_numeros_alertes_legales_down.sql

alter table public.companies
  add column if not exists ipres_number text,
  add column if not exists css_number text,
  add column if not exists collective_agreement_code text references public.collective_agreements(code);

create index if not exists companies_collective_agreement_idx on public.companies (collective_agreement_code);

create or replace function public.legal_alerts(p_as_of date default current_date, p_horizon_days integer default 30)
returns table (
  code text, severity text, employee_id uuid, employee_number text, employee_name text,
  due_date date, message text
)
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  s public.payroll_settings;
  v_smic_month numeric;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis';
  end if;
  s := public.payroll_settings_at(p_as_of);
  v_smic_month := coalesce(s.smig_hourly, 0) * coalesce(s.monthly_hours, 0);

  -- Fin de CDD : échu (erreur) ou dans l'horizon (alerte)
  return query
  select case when e.contract_end < p_as_of then 'cdd_echu' else 'cdd_echeance' end,
         case when e.contract_end < p_as_of then 'erreur' else 'alerte' end,
         e.id, e.employee_number, e.last_name || ' ' || e.first_name, e.contract_end,
         case when e.contract_end < p_as_of
              then 'CDD échu depuis le ' || to_char(e.contract_end, 'DD/MM/YYYY') || ' : renouveler, requalifier ou clôturer la sortie'
              else 'CDD arrivant à échéance le ' || to_char(e.contract_end, 'DD/MM/YYYY') || ' : décider du renouvellement ou de la sortie' end
  from public.employees e
  where e.status = 'Active' and e.employment_type = 'CDD' and e.contract_end is not null
    and e.contract_end <= p_as_of + p_horizon_days;

  -- Salaire de base inférieur au SMIG mensuel paramétré (dernière affectation en vigueur)
  if v_smic_month > 0 then
    return query
    select 'sous_smig'::text, 'erreur'::text, e.id, e.employee_number, e.last_name || ' ' || e.first_name, a.from_date,
           'Salaire de base ' || round(a.base_salary) || ' F inférieur au SMIG mensuel paramétré (' || round(v_smic_month) || ' F)'
    from public.employees e
    join lateral (
      select x.base_salary, x.from_date from public.salary_structure_assignments x
      where x.employee_id = e.id and x.from_date <= p_as_of
      order by x.from_date desc limit 1
    ) a on true
    where e.status = 'Active' and e.employment_type in ('CDI', 'CDD')
      and a.base_salary is not null and a.base_salary > 0 and a.base_salary < v_smic_month;
  end if;

  -- Pièce d'identité expirée ou expirant dans l'horizon
  return query
  select case when e.id_expiry_date < p_as_of then 'piece_expiree' else 'piece_echeance' end,
         case when e.id_expiry_date < p_as_of then 'alerte' else 'info' end,
         e.id, e.employee_number, e.last_name || ' ' || e.first_name, e.id_expiry_date,
         'Pièce d''identité ' || case when e.id_expiry_date < p_as_of then 'expirée le ' else 'expirant le ' end || to_char(e.id_expiry_date, 'DD/MM/YYYY')
  from public.employees e
  where e.status = 'Active' and e.id_expiry_date is not null and e.id_expiry_date <= p_as_of + p_horizon_days;
end;
$function$;

revoke execute on function public.legal_alerts(date, integer) from public, anon;
grant execute on function public.legal_alerts(date, integer) to authenticated, service_role;

notify pgrst, 'reload schema';
