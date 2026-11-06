-- =============================================================================
-- C26 (2/3) : maternité (art. 277), motifs de sortie étendus, indemnités de rupture
-- Tickets : C26-01 (maternité 126 j + extension 21 j), C26-03 (liste des 16 motifs), C26-04 (indemnité spéciale 1 mois),
--           C26-05 (éligibilité à l'indemnité de licenciement après 12 mois)
-- Cette migration ne modifie ni compute_salary_slip ni sortie_salarie : le branchement sur le moteur est un ticket à part
-- (voir le cadrage). Les anciens motifs (dont « FIN DE CONTRAT ») restent acceptés pour ne rien casser.
-- Application : docker exec -i soma-rh-local-postgres-1 psql -U soma -d soma_rh -v ON_ERROR_STOP=1 < ce fichier
-- Retour : db/rollback/20261109100000_c26_maternite_sorties_down.sql
-- =============================================================================

-- ------------------------------------------------------------ maternité
alter table public.leave_types
  add column if not exists extension_days numeric not null default 0 check (extension_days >= 0);
comment on column public.leave_types.extension_days is 'Jours supplémentaires possibles au-delà du maximum (maternité : 21 jours, soit 147 au total ; art. 277, sur justificatif).';

update public.leave_types
   set max_days_per_year = 126, extension_days = 21
 where code = 'MATERNITE';

-- ------------------------------------------------------------ paramètres de rupture
alter table public.payroll_settings
  add column if not exists severance_min_months smallint not null default 12 check (severance_min_months >= 0);
comment on column public.payroll_settings.severance_min_months is 'Ancienneté minimale (mois) pour l''indemnité de licenciement (C26-05).';

-- ------------------------------------------------------------ motifs de sortie
create table public.exit_reasons (
  code                    text primary key,
  label                   text not null,
  severance_eligible      boolean not null default false,
  retirement_indemnity    boolean not null default false,
  special_indemnity_months numeric not null default 0 check (special_indemnity_months >= 0),
  is_legacy               boolean not null default false,
  source_code             text references public.legal_sources(code),
  notes                   text,
  sort_order              smallint not null default 0
);
create index exit_reasons_source_idx on public.exit_reasons(source_code);
comment on table public.exit_reasons is 'Motifs de sortie. severance_eligible et special_indemnity_months ne sont renseignés que là où le Code 2026 le dit ; les autres lignes sont à confirmer (notes).';

insert into public.exit_reasons (code, label, severance_eligible, retirement_indemnity, special_indemnity_months, is_legacy, notes, sort_order) values
  ('DEMISSION',                'Démission',                                 false, false, 0, false, null, 10),
  ('DEMISSION_SANS_PREAVIS',   'Démission sans préavis',                    false, false, 0, false, 'Conséquences sur le préavis à confirmer.', 20),
  ('LICENCIEMENT_PERSONNEL',   'Licenciement pour motif personnel',         true,  false, 0, false, 'Indemnité sous condition de 12 mois d''ancienneté.', 30),
  ('LICENCIEMENT_FAUTE_LOURDE','Licenciement pour faute lourde',            false, false, 0, false, 'Pas d''indemnité de licenciement.', 40),
  ('LICENCIEMENT_ECONOMIQUE',  'Licenciement économique',                   true,  false, 1, false, 'Indemnité spéciale d''un mois (C26-04).', 50),
  ('CESSATION_ACTIVITE',       'Cessation d''activité de l''entreprise',     true,  false, 1, false, 'Indemnité spéciale d''un mois (C26-04).', 60),
  ('PLAN_SOCIAL',              'Plan social',                               true,  false, 1, false, 'Indemnité spéciale d''un mois (C26-04).', 70),
  ('RUPTURE_AMIABLE',          'Rupture d''un commun accord',               false, false, 0, false, 'Droits à confirmer par le juriste.', 80),
  ('RETRAITE',                 'Départ ou mise à la retraite',              false, true,  0, false, null, 90),
  ('DECES',                    'Décès',                                     false, false, 0, false, 'Indemnité assimilée au licenciement, plus un mois pour les obsèques : ticket C26-28.', 100),
  ('INAPTITUDE_PRO',           'Inaptitude professionnelle',                false, false, 0, false, 'Droits à confirmer.', 110),
  ('INAPTITUDE_NON_PRO',       'Inaptitude non professionnelle',            false, false, 0, false, 'Droits à confirmer.', 120),
  ('FIN_CDD',                  'Fin de CDD',                                false, false, 0, false, 'Indemnité de précarité gérée par contract_types.', 130),
  ('RUPTURE_ANTICIPEE_CDD',    'Rupture anticipée de CDD',                  false, false, 0, false, 'Droits à confirmer.', 140),
  ('FIN_ESSAI',                'Fin de période d''essai',                    false, false, 0, false, null, 150),
  ('FORCE_MAJEURE',            'Force majeure',                             false, false, 0, false, 'Droits à confirmer.', 160),
  -- anciens codes de SOMA-RH, conservés tels quels
  ('LICENCIEMENT',             'Licenciement (ancien code)',                true,  false, 0, true,  'Équivaut à LICENCIEMENT_PERSONNEL.', 900),
  ('FIN DE CONTRAT',           'Fin de contrat (ancien code)',              false, false, 0, true,  'Équivaut à FIN_CDD.', 910)
on conflict do nothing;

-- la liste fermée du contrôle devient une clé étrangère : on peut ajouter un motif sans migration
alter table public.employees drop constraint if exists employees_exit_reason_check;
alter table public.employees
  add constraint employees_exit_reason_fk foreign key (exit_reason) references public.exit_reasons(code) on update cascade;
create index if not exists employees_exit_reason_idx on public.employees(exit_reason);

alter table public.exit_reasons enable row level security;
create policy exit_reasons_read on public.exit_reasons for select to authenticated using (true);
create policy exit_reasons_ins  on public.exit_reasons for insert to authenticated with check ((select public.has_role(array['rh'])));
create policy exit_reasons_upd  on public.exit_reasons for update to authenticated using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));
create policy exit_reasons_del  on public.exit_reasons for delete to authenticated using ((select public.has_role(array['rh'])));

notify pgrst, 'reload schema';
