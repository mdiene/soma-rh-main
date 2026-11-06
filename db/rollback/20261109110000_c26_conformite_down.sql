-- Retour C26 (3/3) : supprime la conformité sociale (les colonnes d'embauche perdent leurs valeurs saisies).
drop view if exists public.v_conformite_embauche;
drop function if exists public.echeance_cotisations(date, integer);
drop function if exists public.majoration_retard_cotisations(numeric, date, date);
drop table if exists public.compliance_findings;
drop table if exists public.employee_representatives;
drop table if exists public.delegate_seats;
alter table public.employees
  drop column if exists hire_declaration_ref,
  drop column if exists hire_declared_on,
  drop column if exists affiliation_date;
notify pgrst, 'reload schema';
