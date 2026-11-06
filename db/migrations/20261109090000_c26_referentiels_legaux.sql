-- =============================================================================
-- C26 (1/3) : référentiels légaux du Code du Travail 2026 (loi 2026-18) et des textes hérités
-- Tables : legal_sources, garnishment_scale, notice_scales, overtime_rates, severance_scales
-- Fonctions : quotite_cessible(assiette, kind), plafond_retenues(assiette)
-- Tickets : C26-26 (quotité cessible, plafond 2/3), C26-27 (préavis, heures sup.), C26-10, C26-39
-- Statut des valeurs : CODE = fixé par la loi ; HERITEE = texte antérieur maintenu (art. 459-461) ; A_FOURNIR = vide.
-- Aucune modification du moteur compute_salary_slip : ces tables sont lues par les contrôles et les tickets suivants.
-- Application : docker exec -i soma-rh-local-postgres-1 psql -U soma -d soma_rh -v ON_ERROR_STOP=1 < ce fichier
-- Retour : db/rollback/20261109090000_c26_referentiels_legaux_down.sql
-- =============================================================================

-- ------------------------------------------------------------ traçabilité des sources
create table public.legal_sources (
  code         text primary key,
  label        text not null,
  source_type  text not null check (source_type in ('CODE','HERITEE','A_FOURNIR')),
  document     text,
  article      text,
  valid_from   date,
  status       text not null default 'a_confirmer' check (status in ('a_confirmer','confirme')),
  notes        text,
  created_at   timestamptz not null default now()
);
comment on table public.legal_sources is 'Origine de chaque valeur légale : Code 2026, texte hérité ou à fournir. « confirme » seulement après revue juridique.';

insert into public.legal_sources (code, label, source_type, document, article, status, notes) values
  ('CPC_381',     'Quotité cessible et saisissable des salaires', 'HERITEE', 'Code de procédure civile', '381', 'a_confirmer', 'Lecture progressive des tranches à confirmer par le juriste.'),
  ('CT26_216',    'Retenues sur salaire : renvoi au CPC',         'CODE',    'Loi 2026-18 (Code du Travail)', '216', 'a_confirmer', null),
  ('CCNI_74_77',  'Préavis : 1 mois ouvriers/employés, 2 maîtrise, 3 cadres', 'HERITEE', 'CCNI', '74-77', 'a_confirmer', 'À confirmer : convention applicable à SOMA.'),
  ('CCNI_49',     'Heures supplémentaires : +15 %, +40 %, +60 %, +100 %', 'HERITEE', 'CCNI', '49', 'a_confirmer', 'Taux renvoyés par le Code 2026 (art. 244).'),
  ('CCNI_80',     'Indemnité de licenciement 25/30/40 %',         'HERITEE', 'CCNI', '80', 'a_confirmer', null),
  ('CCNI_84',     'Indemnité de retraite 25/30/45/50 %',          'HERITEE', 'CCNI', '84', 'a_confirmer', null),
  ('CSS_91_93',   'Échéances de versement des cotisations',       'CODE',    'Loi 2026-19 (Code de la Sécurité sociale)', '91-93', 'a_confirmer', null),
  ('CSS_320',     'Majoration de retard : 10 %/mois, plafond 50 %/an', 'CODE', 'Loi 2026-19 (Code de la Sécurité sociale)', '320', 'a_confirmer', null),
  ('CT26_277',    'Congé de maternité : 18 semaines (126 jours)', 'CODE',    'Loi 2026-18 (Code du Travail)', '277', 'a_confirmer', 'Date d''entrée en vigueur à confirmer (art. 459).'),
  ('DEC_67_1360', 'Délégués du personnel : nombre de sièges',     'HERITEE', 'Décret 67-1360', '2', 'a_confirmer', null),
  ('AMENDES_ADM', 'Barème des amendes administratives',           'A_FOURNIR','Décret annoncé (CT art. 373, CSS art. 309)', '373', 'a_confirmer', 'Décret non publié dans les pièces fournies.')
on conflict do nothing;

-- ------------------------------------------------------------ quotité cessible (CPC art. 381)
create table public.garnishment_scale (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null check (kind in ('PRINCIPAL','SUPPLEMENTAIRE')),
  lower_bound  numeric not null check (lower_bound >= 0),
  upper_bound  numeric check (upper_bound is null or upper_bound > lower_bound),
  rate         numeric not null check (rate > 0 and rate <= 1),
  source_code  text references public.legal_sources(code),
  unique (kind, lower_bound)
);
create index garnishment_scale_source_idx on public.garnishment_scale(source_code);
comment on table public.garnishment_scale is 'Tranches mensuelles de la part saisissable ; le taux s''applique à la part d''assiette comprise dans chaque tranche.';

insert into public.garnishment_scale (kind, lower_bound, upper_bound, rate, source_code) values
  ('PRINCIPAL',           0,  20000, 0.10, 'CPC_381'),
  ('PRINCIPAL',       20000,  30000, 0.20, 'CPC_381'),
  ('PRINCIPAL',       30000, 100000, 0.30, 'CPC_381'),
  ('PRINCIPAL',      100000, 200000, 0.40, 'CPC_381'),
  ('PRINCIPAL',      200000,   null, 1.00, 'CPC_381'),
  ('SUPPLEMENTAIRE',      0,  20000, 0.10, 'CPC_381'),
  ('SUPPLEMENTAIRE',  20000,  30000, 0.20, 'CPC_381'),
  ('SUPPLEMENTAIRE',  30000, 100000, 0.30, 'CPC_381'),
  ('SUPPLEMENTAIRE', 100000, 200000, 0.40, 'CPC_381');

-- plafond global des retenues, cessions volontaires comprises
alter table public.payroll_settings
  add column if not exists deduction_global_cap numeric not null default 0.6666666666666667
  check (deduction_global_cap > 0 and deduction_global_cap <= 1);
comment on column public.payroll_settings.deduction_global_cap is 'Part maximale de l''assiette retenable, cessions volontaires comprises (CPC art. 381 : deux tiers).';

create or replace function public.quotite_cessible(p_assiette numeric, p_kind text default 'PRINCIPAL')
returns numeric
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(
    greatest(0, least(p_assiette, coalesce(g.upper_bound, p_assiette)) - g.lower_bound) * g.rate
  ), 0)
  from public.garnishment_scale g
  where g.kind = p_kind and p_assiette > 0;
$$;
comment on function public.quotite_cessible(numeric, text) is 'Part saisissable de l''assiette mensuelle selon les tranches progressives (PRINCIPAL ou SUPPLEMENTAIRE).';

create or replace function public.plafond_retenues(p_assiette numeric, p_cap numeric default 2.0/3.0)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select greatest(0, p_assiette) * p_cap;
$$;
comment on function public.plafond_retenues(numeric, numeric) is 'Plafond global des retenues (deux tiers de l''assiette par défaut).';

-- ------------------------------------------------------------ préavis (CCNI art. 74-77)
create table public.notice_scales (
  id              uuid primary key default gen_random_uuid(),
  agreement_code  text references public.collective_agreements(code) on update cascade,  -- null = CCNI interprofessionnelle
  category        text not null check (category in ('OUVRIER_EMPLOYE','MAITRISE','CADRE')),
  notice_months   numeric not null check (notice_months >= 0),
  free_days_week  smallint not null default 2 check (free_days_week >= 0),
  source_code     text references public.legal_sources(code),
  valid_from      date not null default date '2026-10-01',
  unique nulls not distinct (agreement_code, category, valid_from)
);
create index notice_scales_agreement_idx on public.notice_scales(agreement_code);
create index notice_scales_source_idx    on public.notice_scales(source_code);
insert into public.notice_scales (category, notice_months, source_code) values
  ('OUVRIER_EMPLOYE', 1, 'CCNI_74_77'),
  ('MAITRISE',        2, 'CCNI_74_77'),
  ('CADRE',           3, 'CCNI_74_77');

-- ------------------------------------------------------------ heures supplémentaires (CCNI art. 49)
create table public.overtime_rates (
  code         text primary key,
  label        text not null,
  rate_uplift  numeric not null check (rate_uplift >= 0),
  hours_from   numeric,
  hours_to     numeric,
  source_code  text references public.legal_sources(code)
);
create index overtime_rates_source_idx on public.overtime_rates(source_code);
insert into public.overtime_rates (code, label, rate_uplift, hours_from, hours_to, source_code) values
  ('HS_JOUR_8_PREMIERES', 'Heures supplémentaires : 8 premières heures',  0.15, 0,    8,    'CCNI_49'),
  ('HS_JOUR_AU_DELA',     'Heures supplémentaires : au-delà de 8 heures', 0.40, 8,    null, 'CCNI_49'),
  ('HS_NUIT',             'Heures supplémentaires de nuit',               0.60, null, null, 'CCNI_49'),
  ('HS_REPOS_FERIE_JOUR', 'Repos hebdomadaire ou jour férié, de jour',    0.60, null, null, 'CCNI_49'),
  ('HS_REPOS_FERIE_NUIT', 'Repos hebdomadaire ou jour férié, de nuit',    1.00, null, null, 'CCNI_49');

-- ------------------------------------------------------------ indemnités de licenciement et de retraite
create table public.severance_scales (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null check (kind in ('LICENCIEMENT','RETRAITE')),
  year_from    smallint not null check (year_from >= 0),
  year_to      smallint check (year_to is null or year_to > year_from),
  rate         numeric not null check (rate > 0 and rate <= 1),
  source_code  text references public.legal_sources(code),
  unique (kind, year_from)
);
create index severance_scales_source_idx on public.severance_scales(source_code);
comment on table public.severance_scales is 'Taux par année d''ancienneté, miroir de severance_coefficient() ; la fonction n''est pas encore branchée sur cette table (ticket C26-25).';
insert into public.severance_scales (kind, year_from, year_to, rate, source_code) values
  ('LICENCIEMENT', 0, 5, 0.25, 'CCNI_80'), ('LICENCIEMENT', 5, 10, 0.30, 'CCNI_80'), ('LICENCIEMENT', 10, null, 0.40, 'CCNI_80'),
  ('RETRAITE', 0, 5, 0.25, 'CCNI_84'), ('RETRAITE', 5, 10, 0.30, 'CCNI_84'), ('RETRAITE', 10, 20, 0.45, 'CCNI_84'), ('RETRAITE', 20, null, 0.50, 'CCNI_84');

-- ------------------------------------------------------------ RLS : lecture authentifiée, écriture RH
do $$
declare t text;
begin
  foreach t in array array['legal_sources','garnishment_scale','notice_scales','overtime_rates','severance_scales'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %1$s_read on public.%1$s for select to authenticated using (true)', t);
    execute format('create policy %1$s_ins on public.%1$s for insert to authenticated with check ((select public.has_role(array[''rh''])))', t);
    execute format('create policy %1$s_upd on public.%1$s for update to authenticated using ((select public.has_role(array[''rh'']))) with check ((select public.has_role(array[''rh''])))', t);
    execute format('create policy %1$s_del on public.%1$s for delete to authenticated using ((select public.has_role(array[''rh''])))', t);
  end loop;
end $$;

revoke execute on function public.quotite_cessible(numeric, text) from public, anon;
revoke execute on function public.plafond_retenues(numeric, numeric) from public, anon;
grant execute on function public.quotite_cessible(numeric, text) to authenticated;
grant execute on function public.plafond_retenues(numeric, numeric) to authenticated;

notify pgrst, 'reload schema';
