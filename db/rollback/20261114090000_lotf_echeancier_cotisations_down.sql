create or replace function public.detecter_conformite()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_new integer;
begin
  if not public.has_role(array['rh','paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis';
  end if;

  drop table if exists pg_temp._found;
  create temp table _found on commit drop as
  select 'EMB-DECL'::text as rule_id, 'A'::text as severity, 'employee'::text as entity, v.employee_id as entity_id,
         'Salarié ' || v.employee_number || ' : déclaration d''embauche non référencée' as message
    from public.v_conformite_embauche v where v.declaration_manquante
  union all
  select 'EMB-AFFIL', 'A', 'employee', v.employee_id,
         'Salarié ' || v.employee_number || ' : affiliation absente ou au-delà de 2 mois après l''embauche'
    from public.v_conformite_embauche v where v.affiliation_hors_delai
  union all
  select 'RET-04', 'B', 'salary_slip', r.slip_id,
         'Salarié ' || r.employee_number || ' ' || to_char(r.period_start, 'MM/YYYY') || ' : retenues sur net supérieures à la quotité cessible'
    from public.v_conformite_retenues r where r.depasse_quotite_cessible
  union all
  select 'RET-PLAFOND', 'B', 'salary_slip', r.slip_id,
         'Salarié ' || r.employee_number || ' ' || to_char(r.period_start, 'MM/YYYY') || ' : retenues sur net supérieures au plafond des 2/3'
    from public.v_conformite_retenues r where r.depasse_plafond_global;

  insert into public.compliance_findings(rule_id, severity, entity, entity_id, message)
  select f.rule_id, f.severity, f.entity, f.entity_id, f.message from _found f
  on conflict (rule_id, entity_id) where resolved_on is null do nothing;
  get diagnostics v_new = row_count;

  update public.compliance_findings c set resolved_on = current_date
   where c.resolved_on is null and c.rule_id in ('EMB-DECL','EMB-AFFIL','RET-04','RET-PLAFOND')
     and not exists (select 1 from _found f where f.rule_id = c.rule_id and f.entity_id = c.entity_id);
  return v_new;
end $$;

drop view if exists public.v_echeancier_cotisations;
drop table if exists public.contribution_payments;
