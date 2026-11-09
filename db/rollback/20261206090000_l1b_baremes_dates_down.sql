-- Retour de 20261206090000_l1b_baremes_dates.sql.
-- ATTENTION : à appliquer APRÈS le retour de 20261206100000. Si des versions datées de barèmes ont été créées, supprimez-les avant
-- (le retour de la clé unique/primaire échouerait sinon). compute_salary_slip doit être rétabli depuis 20261204... / la migration
-- précédente qui l'a définie (appels hs_majoration à deux arguments).
drop trigger if exists overtime_rates_guard on public.overtime_rates;
drop trigger if exists notice_scales_guard on public.notice_scales;
drop trigger if exists garnishment_scale_guard on public.garnishment_scale;
drop trigger if exists severance_scales_guard on public.severance_scales;
drop trigger if exists tax_slabs_guard on public.tax_slabs;
drop trigger if exists tax_slab_brackets_guard on public.tax_slab_brackets;
drop trigger if exists ir_family_reductions_guard on public.ir_family_reductions;
drop trigger if exists trimf_brackets_guard on public.trimf_brackets;
drop trigger if exists overtime_rates_audit on public.overtime_rates;
drop trigger if exists notice_scales_audit on public.notice_scales;
drop trigger if exists garnishment_scale_audit on public.garnishment_scale;
drop trigger if exists severance_scales_audit on public.severance_scales;
drop function if exists public.scale_row_guard();
drop function if exists public.slab_child_guard();
drop function if exists public.scale_version_locked(date, date);

alter table public.overtime_rates drop constraint if exists overtime_rates_pkey;
alter table public.overtime_rates add constraint overtime_rates_pkey primary key (code);
alter table public.garnishment_scale drop constraint if exists garnishment_scale_version_key;
alter table public.garnishment_scale add constraint garnishment_scale_kind_lower_bound_key unique (kind, lower_bound);
alter table public.severance_scales drop constraint if exists severance_scales_version_key;
alter table public.severance_scales add constraint severance_scales_kind_year_from_key unique (kind, year_from);
alter table public.overtime_rates drop column if exists effective_from;
alter table public.garnishment_scale drop column if exists effective_from;
alter table public.severance_scales drop column if exists effective_from;

drop function if exists public.hs_majoration(text, numeric, date);
drop function if exists public.quotite_cessible_at(numeric, text, date);
-- hs_majoration(text, numeric) et quotite_cessible(numeric, text) deviennent invalides sans les colonnes : les recréer depuis
-- 20261115090000_lotg_hs_preavis.sql et 20261109090000_c26_referentiels_legaux.sql ; severance_coefficient depuis la version codée en dur
-- (avant-dernière définition : migration d'origine du moteur de paie, 20261028170300_payroll_engine.sql).
notify pgrst, 'reload schema';
