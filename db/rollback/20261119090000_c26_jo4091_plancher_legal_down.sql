-- Retour C26 (4) : retire le plancher légal des heures supplémentaires, le préavis supplétif et l'IFC intérim.
alter table public.payroll_settings drop column if exists interim_ifc_rate;
drop table if exists public.statutory_notice;
alter table public.overtime_rates drop constraint if exists overtime_rates_not_below_legal_min;
drop index if exists public.overtime_rates_legal_min_source_idx;
alter table public.overtime_rates drop column if exists legal_min_source;
alter table public.overtime_rates drop column if exists legal_min_uplift;
delete from public.legal_sources
 where code in ('DEC_70_180','DEC_70_182','DEC_70_183','DEC_70_184','DEC_70_185','CT26_167','IFC_INTERIM','CSS_PLAFOND_AT');
notify pgrst, 'reload schema';
