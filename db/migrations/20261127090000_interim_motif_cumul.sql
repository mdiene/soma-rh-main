-- M4 : (1) motif de mission obligatoire et dans la liste de l'art. 293 (INT_MISSION_REASON, bloquant, test INT-T01) ;
--      (2) alerte de cumul : missions enchaînées chez un même client au-delà de la durée maximale (INT_DURABLE_POST / INT_MAX_DURATION).
-- Le journal des missions (INT_MISSION_LOG, art. 294) est assuré par le trigger business_audit sur employee_module_data.
-- Retour : db/rollback/20261127090000_interim_motif_cumul_down.sql

create or replace function public.interim_mission_reason_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.module_id = 'soma-mod-services-interim-sn' and new.data->>'is_interim' = 'true'
     and coalesce(new.data->>'mission_reason', '') not in
         ('REMPLACEMENT_SUSPENSION', 'ACCROISSEMENT_TEMPORAIRE', 'TACHE_PONCTUELLE', 'TRAVAUX_URGENTS') then
    raise exception 'INT_MISSION_REASON : motif de mission absent ou hors liste (Code du travail 2026, art. 293)' using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke execute on function public.interim_mission_reason_guard() from public, anon, authenticated;
create trigger interim_mission_reason_guard before insert or update on public.employee_module_data
  for each row execute function public.interim_mission_reason_guard();

CREATE OR REPLACE FUNCTION public.legal_alerts(p_as_of date DEFAULT CURRENT_DATE, p_horizon_days integer DEFAULT 30)
 RETURNS TABLE(code text, severity text, employee_id uuid, employee_number text, employee_name text, due_date date, message text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- Agrément de l'entreprise de travail temporaire (Code du travail 2026, art. 292) : module Intérim actif, société ETT, numéro absent
  return query
  select 'agrement_ett_manquant'::text, 'alerte'::text, null::uuid, null::text, c.name, null::date,
         'Attention : l''ouverture d''une entreprise de travail temporaire est soumise à un agrément du Directeur général du Travail et de la Sécurité sociale (Code du travail 2026, art. 292). N° d''agrément non renseigné dans la fiche société.'::text
  from public.companies c
  where c.is_ett and nullif(btrim(c.ett_agreement_number), '') is null
    and exists (select 1 from public.module_activation a where a.module_id = 'soma-mod-services-interim-sn' and a.enabled);

  -- Durée maximale de mission d'intérim : dépassée (erreur) ou atteinte dans l'horizon pour une mission en cours (alerte)
  return query
  with d as (
    select coalesce((select (v.value #>> '{}')::numeric from public.module_parameter_value v
                      where v.module_id = 'soma-mod-services-interim-sn' and v.param_key = 'interim_max_mission_duration_years'
                        and (v.valid_to is null or v.valid_to > p_as_of)
                      order by v.valid_from desc nulls last limit 1), 2) as years
  )
  select case when coalesce(m.valid_to, p_as_of) > (m.valid_from + (d.years * 12)::int * interval '1 month')::date
              then 'mission_interim_duree_max' else 'mission_interim_echeance' end,
         case when coalesce(m.valid_to, p_as_of) > (m.valid_from + (d.years * 12)::int * interval '1 month')::date
              then 'erreur' else 'alerte' end,
         e.id, e.employee_number, e.last_name || ' ' || e.first_name,
         (m.valid_from + (d.years * 12)::int * interval '1 month')::date,
         'Mission d''intérim commencée le ' || to_char(m.valid_from, 'DD/MM/YYYY') || ' : durée maximale de ' || d.years
           || ' an(s) (décret 2009-1412, art. 4 et 8) ' || case when coalesce(m.valid_to, p_as_of) > (m.valid_from + (d.years * 12)::int * interval '1 month')::date
           then 'dépassée depuis le ' else 'atteinte le ' end
           || to_char((m.valid_from + (d.years * 12)::int * interval '1 month')::date, 'DD/MM/YYYY')
           || ' (sauf ouvrage déterminé)'
  from public.employee_module_data m
  join public.employees e on e.id = m.employee_id
  cross join d
  where m.module_id = 'soma-mod-services-interim-sn' and m.data->>'is_interim' = 'true' and m.valid_from is not null
    and (m.valid_to is null or m.valid_to > p_as_of - interval '0 day')
    and (m.valid_from + (d.years * 12)::int * interval '1 month')::date <= p_as_of + p_horizon_days
    and exists (select 1 from public.module_activation a where a.module_id = 'soma-mod-services-interim-sn' and a.enabled);

  -- Cumul des missions enchaînées chez un même client : au-delà de la durée maximale => alerte (risque de poste durable)
  return query
  with d as (
    select coalesce((select (v.value #>> '{}')::numeric from public.module_parameter_value v
                      where v.module_id = 'soma-mod-services-interim-sn' and v.param_key = 'interim_max_mission_duration_years'
                        and (v.valid_to is null or v.valid_to > p_as_of)
                      order by v.valid_from desc nulls last limit 1), 2) as years
  ), c as (
    select m.employee_id, m.data->>'client_company_id' as client, count(*) as n,
           sum(least(coalesce(m.valid_to, p_as_of), p_as_of) - m.valid_from) as days
    from public.employee_module_data m
    where m.module_id = 'soma-mod-services-interim-sn' and m.data->>'is_interim' = 'true'
      and m.valid_from is not null and m.valid_from < p_as_of and nullif(m.data->>'client_company_id', '') is not null
    group by 1, 2
  )
  select 'mission_interim_cumul'::text, 'alerte'::text, e.id, e.employee_number, e.last_name || ' ' || e.first_name, null::date,
         c.n || ' missions chez l''entreprise utilisatrice « ' || c.client || ' » cumulent ' || c.days
           || ' jours, au-delà de ' || d.years || ' an(s) : risque de poste durable (Code du travail 2026, art. 293 ; décret 2009-1412)'
  from c cross join d join public.employees e on e.id = c.employee_id
  where c.n >= 2 and c.days > (d.years * 365)::int
    and exists (select 1 from public.module_activation a where a.module_id = 'soma-mod-services-interim-sn' and a.enabled);
end;
$function$;
