-- Retour de 20261207090000_l2_scan_derogations.sql.
-- detecter_conformite, reset_parameter et scale_reset doivent être rétablis à leur définition précédente :
--   detecter_conformite : 20261114090000_lotf_echeancier_cotisations.sql ; reset_parameter : 20261204090000_l1a_catalogue_constantes.sql ;
--   scale_reset : 20261206100000_l1b_baremes_edition.sql (rejouer leur « create or replace function » après ce fichier).
drop function if exists public.compliance_status();
drop function if exists public.run_compliance_scan();
drop function if exists public.compliance_open_findings();
drop function if exists public.revoke_waiver(uuid, text);
drop function if exists public.grant_waiver(text, uuid, text, text);
drop function if exists public.lift_waivers(text);
drop table if exists public.compliance_scans;
drop table if exists public.compliance_waivers;
drop table if exists public.compliance_rules;
delete from public.parameter_catalog where code = 'cdd_max_months';
delete from public.app_parameters where code = 'cdd_max_months';
delete from public.legal_sources where code = 'CT26_100';
drop index if exists public.compliance_findings_employee_idx;
drop index if exists public.compliance_findings_waived_by_idx;
alter table public.compliance_findings drop column if exists employee_id;
notify pgrst, 'reload schema';
