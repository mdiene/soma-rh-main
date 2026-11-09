-- Retour : planning métier retiré (les postes planifiés sont perdus ; les présences et saisies déjà reportées restent).
drop function if exists public.planning_compliance(date, date);
drop function if exists public.apply_planning(date);
drop function if exists public.plan_shifts(jsonb);
drop function if exists public.shift_templates();
drop function if exists public.shift_night_hours(time, time);
drop table if exists public.module_shift;
