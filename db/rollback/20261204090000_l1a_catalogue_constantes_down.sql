-- Retour de 20261204090000_l1a_catalogue_constantes.sql.
-- Les versions de payroll_settings créées par set_parameter restent en place (ce sont des données) ; supprimez-les à la main si besoin.
drop trigger if exists payroll_settings_guard on public.payroll_settings;
drop function if exists public.payroll_settings_guard();
drop function if exists public.set_parameter_reference(text, text, text);
drop function if exists public.reset_parameter(text, date);
drop function if exists public.set_parameter(text, numeric, date);
drop function if exists public.parameter_overview(date);
drop table if exists public.parameter_catalog;
drop function if exists public.parameters_min_effective_date();
drop function if exists public.payroll_locked_until();
notify pgrst, 'reload schema';
