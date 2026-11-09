-- Retour de 20261206100000_l1b_baremes_edition.sql. Les versions de barèmes créées restent en place (ce sont des données).
drop function if exists public.set_scale_reference(text, text, text);
drop function if exists public.scale_reset(text, date);
drop function if exists public.scale_save(text, date, jsonb);
drop function if exists public.scale_get(text, date);
drop function if exists public.scale_versions(text);
drop function if exists public.scale_overview(date);
drop function if exists public.scale_validate(text, jsonb);
drop function if exists public.scale_check_ranges(jsonb, text, text, text);
drop function if exists public.scale_version_dates(text);
drop function if exists public.scale_lines(text, date);
drop table if exists public.scale_defaults;
drop table if exists public.scale_catalog;
notify pgrst, 'reload schema';
