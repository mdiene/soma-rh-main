-- =============================================================================
-- C26 (4) : JO n° 4091 du 9 mars 1970 — plancher légal des heures supplémentaires, préavis supplétif, sources
-- Sources lues : décrets 70-180, 70-182, 70-183, 70-184, 70-185 (docs/sources-legales/EXTRAITS_JO_4091_DU_09_MARS_1970.md)
-- Contenu :
--   legal_sources                    : décrets du JO 4091 ; IFC du CDD (Code 2026 art. 167) ; IFC intérim et plafond AT (à confirmer)
--   overtime_rates.legal_min_uplift  : plancher du décret 70-184 ; contrainte : le taux appliqué n'est jamais inférieur
--   statutory_notice                 : préavis des entreprises sans convention (décret 70-185)
--   payroll_settings.interim_ifc_rate: IFC intérim, 7 % provisoire (source secondaire)
-- Le moteur compute_salary_slip n'est pas modifié : les taux CCNI du lot G restent appliqués (plus favorables).
-- Application : docker exec -i soma-rh-local-postgres-1 psql -U soma -d soma_rh -v ON_ERROR_STOP=1 < ce fichier
-- Retour : db/rollback/20261119090000_c26_jo4091_plancher_legal_down.sql
-- =============================================================================

-- ------------------------------------------------------------ sources
insert into public.legal_sources (code, label, source_type, document, article, valid_from, status, notes) values
  ('DEC_70_180',  'Journaliers et saisonniers',                                'HERITEE', 'Décret 70-180 du 20/02/1970 (JO 4091)', '1-8',   date '1970-03-09', 'a_confirmer', 'Maintien sous le Code 2026 : art. 461.'),
  ('DEC_70_182',  'Travail de nuit : 22 h à 5 h',                              'HERITEE', 'Décret 70-182 du 20/02/1970 (JO 4091)', '1',     date '1970-03-09', 'a_confirmer', 'Concorde avec le Code 2026 art. 245.'),
  ('DEC_70_183',  'Dérogations à la durée légale ; équivalences sans chiffre', 'HERITEE', 'Décret 70-183 du 20/02/1970 (JO 4091)', '1-13',  date '1970-03-09', 'a_confirmer', 'Seuils d''équivalence : arrêtés de branche non fournis.'),
  ('DEC_70_184',  'Heures supplémentaires : majorations minimales',            'HERITEE', 'Décret 70-184 du 20/02/1970 (JO 4091)', '2-7',   date '1970-03-09', 'a_confirmer', '10 / 35 / 50 / 50 / 100 %.'),
  ('DEC_70_185',  'Préavis des professions sans convention collective',        'HERITEE', 'Décret 70-185 du 20/02/1970 (JO 4091)', '1-3',   date '1970-03-09', 'a_confirmer', '1 mois / 8 jours / 1 heure par journée.'),
  ('CT26_167',    'Indemnité de fin de contrat du CDD : 7 %',                  'CODE',    'Loi 2026-18 (Code du Travail)',          '167',     null,              'a_confirmer', 'Texte officiel lu.'),
  ('IFC_INTERIM', 'Indemnité de fin de mission d''intérim : 7 % provisoire',    'A_FOURNIR','Décret 2009-1412 (non lu) ; Code 2026 art. 292-293', '292-293', null,       'a_confirmer', 'Valeur issue de sources secondaires qui alignent l''intérim sur le CDD.'),
  ('CSS_PLAFOND_AT', 'Plafond mensuel de la branche AT : 63 000 F',            'A_FOURNIR','Arrêté non fourni ; CLEISS / OCDE (secondaire)', '73-74', null,          'a_confirmer', 'Une source dit « sans plafond » : contradiction non levée.')
on conflict do nothing;

-- ------------------------------------------------------------ plancher légal des heures supplémentaires
alter table public.overtime_rates
  add column if not exists legal_min_uplift numeric not null default 0 check (legal_min_uplift >= 0),
  add column if not exists legal_min_source text references public.legal_sources(code);
create index if not exists overtime_rates_legal_min_source_idx on public.overtime_rates(legal_min_source);

update public.overtime_rates set legal_min_uplift = 0.10, legal_min_source = 'DEC_70_184' where code = 'HS_JOUR_8_PREMIERES';
update public.overtime_rates set legal_min_uplift = 0.35, legal_min_source = 'DEC_70_184' where code = 'HS_JOUR_AU_DELA';
update public.overtime_rates set legal_min_uplift = 0.50, legal_min_source = 'DEC_70_184' where code = 'HS_NUIT';
update public.overtime_rates set legal_min_uplift = 0.50, legal_min_source = 'DEC_70_184' where code = 'HS_REPOS_FERIE_JOUR';
update public.overtime_rates set legal_min_uplift = 1.00, legal_min_source = 'DEC_70_184' where code = 'HS_REPOS_FERIE_NUIT';

-- un taux inférieur au minimum légal est refusé (la CCNI et les accords peuvent seulement faire mieux)
alter table public.overtime_rates
  add constraint overtime_rates_not_below_legal_min check (rate_uplift >= legal_min_uplift);
comment on column public.overtime_rates.legal_min_uplift is 'Majoration minimale du décret 70-184 ; rate_uplift (CCNI ou accord) ne peut pas être inférieur.';

-- ------------------------------------------------------------ préavis supplétif (décret 70-185)
create table public.statutory_notice (
  code         text primary key,
  label        text not null,
  amount       numeric not null check (amount > 0),
  unit         text not null check (unit in ('MOIS','JOURS','HEURES_PAR_JOURNEE')),
  source_code  text references public.legal_sources(code)
);
create index statutory_notice_source_idx on public.statutory_notice(source_code);
comment on table public.statutory_notice is 'Préavis applicable aux entreprises sans convention collective (décret 70-185) ; le contrat peut prévoir plus long (art. 2).';
insert into public.statutory_notice (code, label, amount, unit, source_code) values
  ('MENSUEL',    'Payés au mois, rémunération fixée au mois',                                                1, 'MOIS',               'DEC_70_185'),
  ('PERIODIQUE', 'Payés à la semaine, à la quinzaine ou au mois, rémunération à l''heure, au jour ou à la période', 8, 'JOURS',         'DEC_70_185'),
  ('JOURNALIER', 'Payés au jour, rémunération à l''heure ou à la journée',                                   1, 'HEURES_PAR_JOURNEE', 'DEC_70_185');

alter table public.statutory_notice enable row level security;
create policy statutory_notice_read on public.statutory_notice for select to authenticated using (true);
create policy statutory_notice_ins  on public.statutory_notice for insert to authenticated with check ((select public.has_role(array['rh'])));
create policy statutory_notice_upd  on public.statutory_notice for update to authenticated using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));
create policy statutory_notice_del  on public.statutory_notice for delete to authenticated using ((select public.has_role(array['rh'])));

-- ------------------------------------------------------------ IFC intérim (provisoire)
alter table public.payroll_settings
  add column if not exists interim_ifc_rate numeric not null default 0.07 check (interim_ifc_rate >= 0 and interim_ifc_rate <= 1);
comment on column public.payroll_settings.interim_ifc_rate is 'Indemnité de fin de mission d''intérim : 7 % PROVISOIRE (source secondaire, décret 2009-1412 non lu). Source : legal_sources.IFC_INTERIM.';

notify pgrst, 'reload schema';
