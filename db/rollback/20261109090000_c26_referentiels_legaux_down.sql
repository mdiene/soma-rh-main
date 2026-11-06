-- Retour C26 (1/3) : supprime les référentiels légaux et le plafond global des retenues.
drop function if exists public.quotite_cessible(numeric, text);
drop function if exists public.plafond_retenues(numeric, numeric);
drop table if exists public.severance_scales;
drop table if exists public.overtime_rates;
drop table if exists public.notice_scales;
drop table if exists public.garnishment_scale;
alter table public.payroll_settings drop column if exists deduction_global_cap;
drop table if exists public.legal_sources;
notify pgrst, 'reload schema';
