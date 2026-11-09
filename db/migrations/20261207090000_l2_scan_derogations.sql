-- =============================================================================
-- Centre de conformité, lot L2 : scan de cohérence, état vert / orange / rouge, registre durable des dérogations.
-- Cadrage : docs/CADRAGE_CENTRE_CONFORMITE.md (§4.3, §4.4, §8-2).
--   compliance_findings   + employee_id (salarié concerné)
--   compliance_rules      libellé, domaine, référence juridique, action recommandée, cible de correction de chaque règle
--   compliance_waivers    dérogations : sans expiration ; remplacée par une nouvelle, levée si la constante liée est réinitialisée, ou révoquée
--   compliance_scans      journal des scans (état, compteurs)
--   detecter_conformite() étendue : legal_alerts (SMIG, CDD, agrément ETT, attestations, intérim, gardiennage, habilitations, permis, logement),
--                         planning_compliance (28 derniers jours), durée maximale du CDD, constantes modifiées sans source confirmée
--   run_compliance_scan / compliance_open_findings / compliance_status / grant_waiver / revoke_waiver
-- Non couvert faute de donnée : nombre de renouvellements et cumul des CDD (pas de compteur en base), contingent d'heures supplémentaires
-- (aucun paramètre). Ils seront ajoutés avec leurs données.
-- Dérogation et scan : rôle admin (grant/revoke) ; le circuit RH -> admin arrive en L2b.
-- Retour : db/rollback/20261207090000_l2_scan_derogations_down.sql
-- =============================================================================

alter table public.compliance_findings add column if not exists employee_id uuid references public.employees(id) on delete set null;
create index if not exists compliance_findings_employee_idx on public.compliance_findings (employee_id);
create index if not exists compliance_findings_waived_by_idx on public.compliance_findings (waived_by);

-- rattache les constats déjà ouverts à leur salarié quand l'entité est un salarié ou un bulletin
update public.compliance_findings f set employee_id = f.entity_id
 where f.employee_id is null and f.entity = 'employee' and exists (select 1 from public.employees e where e.id = f.entity_id);
update public.compliance_findings f set employee_id = s.employee_id
  from public.salary_slips s where f.employee_id is null and f.entity = 'salary_slip' and s.id = f.entity_id;

-- ------------------------------------------------------------ référence juridique du CDD (durée maximale)
insert into public.legal_sources (code, label, source_type, document, article, status, notes) values
  ('CT26_100', 'CDD : 24 mois au plus, un seul renouvellement, 4 ans cumulés', 'CODE', 'Loi 2026-18 (Code du Travail)', '99-103', 'a_confirmer',
   'Reprise de docs/CODE_TRAVAIL_2026_SPECIFICATION_SOMA_RH.md (CTR-04) ; à confirmer par le juriste.')
on conflict (code) do nothing;
insert into public.app_parameters (code, label, value) values ('cdd_max_months', 'Durée maximale d''un CDD (mois)', 24)
on conflict (code) do nothing;
insert into public.parameter_catalog (code, domain, label, unit, sort, store, column_name, default_value, min_value, max_value, source_code, legal_text) values
  ('cdd_max_months', 'Contrats', 'Durée maximale d''un contrat à durée déterminée', 'mois', 10, 'app_parameters', 'cdd_max_months', 24, 1, 120, 'CT26_100',
   'Un CDD ne peut dépasser 24 mois, avec un seul renouvellement ou une seule prolongation, et 4 ans cumulés chez le même employeur (hors ouvrage déterminé). Valeur reprise de la spécification du dépôt, à confirmer.')
on conflict (code) do nothing;

-- ------------------------------------------------------------ règles
create table if not exists public.compliance_rules (
  rule_id           text primary key,
  label             text not null,
  domain            text not null,
  legal_ref         text,
  suggested_action  text not null,
  fix_target        text not null default 'employee' check (fix_target in ('employee', 'company', 'parameter', 'planning', 'payroll'))
);
alter table public.compliance_rules enable row level security;
drop policy if exists compliance_rules_read on public.compliance_rules;
create policy compliance_rules_read on public.compliance_rules for select to authenticated
  using ((select public.has_role(array['admin', 'rh', 'paie'])));
revoke insert, update, delete on public.compliance_rules from anon, authenticated;
grant select on public.compliance_rules to authenticated;

insert into public.compliance_rules (rule_id, label, domain, legal_ref, suggested_action, fix_target) values
  ('EMB-DECL',   'Déclaration d''embauche non référencée', 'Embauche', null, 'Renseigner la référence de déclaration d''embauche sur la fiche du salarié.', 'employee'),
  ('EMB-AFFIL',  'Affiliation absente ou tardive', 'Embauche', 'Affiliation dans les 2 mois suivant l''embauche', 'Saisir ou régulariser l''affiliation sociale du salarié.', 'employee'),
  ('RET-04',     'Retenues supérieures à la quotité cessible', 'Retenues', 'Code de procédure civile, art. 381', 'Réduire les retenues du bulletin ou accorder une dérogation motivée.', 'payroll'),
  ('RET-PLAFOND','Retenues supérieures au plafond des deux tiers', 'Retenues', 'Code du Travail 2026, art. 216', 'Réduire les retenues du bulletin ou accorder une dérogation motivée.', 'payroll'),
  ('COT-ECHEANCE','Échéance de versement des cotisations', 'Cotisations', 'Code de la Sécurité sociale, art. 91-93 et 320', 'Verser les cotisations et enregistrer le paiement dans l''échéancier.', 'payroll'),
  ('CDD-DUREE',  'CDD au-delà de la durée maximale', 'Contrats', 'Code du Travail 2026, art. 99-103', 'Requalifier, raccourcir le contrat ou déroger (ouvrage déterminé).', 'employee'),
  ('PARAM-DEFAUT','Constante modifiée sans source légale confirmée', 'Constantes', null, 'Confirmer la source légale de la constante ou la réinitialiser.', 'parameter'),
  ('LEGAL-CDD_ECHU','CDD échu', 'Contrats', 'Code du Travail 2026, art. 99-103', 'Renouveler, requalifier ou clôturer la sortie.', 'employee'),
  ('LEGAL-CDD_ECHEANCE','CDD arrivant à échéance', 'Contrats', 'Code du Travail 2026, art. 99-103', 'Décider du renouvellement ou de la sortie.', 'employee'),
  ('LEGAL-SOUS_SMIG','Salaire de base inférieur au SMIG', 'Rémunération', 'SMIG paramétré', 'Corriger le salaire de base du salarié ou la valeur du SMIG.', 'employee'),
  ('LEGAL-PIECE_EXPIREE','Pièce d''identité expirée', 'Dossier salarié', null, 'Obtenir et enregistrer une pièce d''identité valide.', 'employee'),
  ('LEGAL-PIECE_ECHEANCE','Pièce d''identité bientôt expirée', 'Dossier salarié', null, 'Demander le renouvellement de la pièce.', 'employee'),
  ('LEGAL-AGREMENT_ETT_MANQUANT','Agrément de l''entreprise de travail temporaire absent', 'Intérim', 'Code du Travail 2026, art. 292', 'Saisir le numéro d''agrément dans la fiche société.', 'company'),
  ('LEGAL-MISSION_INTERIM_DUREE_MAX','Mission d''intérim au-delà de la durée maximale', 'Intérim', 'Décret 2009-1412, art. 4 et 8', 'Clôturer la mission, la requalifier ou déroger (ouvrage déterminé).', 'employee'),
  ('LEGAL-MISSION_INTERIM_ECHEANCE','Mission d''intérim proche de la durée maximale', 'Intérim', 'Décret 2009-1412, art. 4 et 8', 'Prévoir la fin ou la requalification de la mission.', 'employee'),
  ('LEGAL-MISSION_INTERIM_CUMUL','Missions enchaînées au-delà de la durée maximale', 'Intérim', 'Code du Travail 2026, art. 293 ; décret 2009-1412', 'Examiner le risque de poste durable chez l''entreprise utilisatrice.', 'employee'),
  ('LEGAL-ATTESTATION_REGULARITE_MANQUANTE','Attestation de régularité sociale absente', 'Gardiennage et nettoyage', 'Code du Travail 2026, art. 291', 'Saisir la date de l''attestation dans la fiche société.', 'company'),
  ('LEGAL-ATTESTATION_REGULARITE_ECHUE','Attestation de régularité sociale échue', 'Gardiennage et nettoyage', 'Code du Travail 2026, art. 291', 'Obtenir une nouvelle attestation et la saisir dans la fiche société.', 'company'),
  ('LEGAL-ATTESTATION_REGULARITE_ECHEANCE','Attestation de régularité sociale bientôt échue', 'Gardiennage et nettoyage', 'Code du Travail 2026, art. 291', 'Demander le renouvellement de l''attestation.', 'company'),
  ('LEGAL-EQUIVALENCE_MANQUANTE','Seuil d''équivalence non saisi', 'Gardiennage et nettoyage', 'Décret 70-183, art. 4', 'Saisir le seuil d''équivalence de la catégorie dans les paramètres du module Gardiennage.', 'parameter'),
  ('LEGAL-HABILITATION_ECHUE','Habilitation échue', 'Habilitations', null, 'Renouveler l''habilitation avant toute affectation.', 'employee'),
  ('LEGAL-HABILITATION_ECHEANCE','Habilitation bientôt échue', 'Habilitations', null, 'Programmer le renouvellement de l''habilitation.', 'employee'),
  ('LEGAL-PERMIS_ECHU','Permis de conduire échu', 'Habilitations', null, 'Retirer le conducteur des affectations jusqu''au renouvellement du permis.', 'employee'),
  ('LEGAL-PERMIS_ECHEANCE','Permis de conduire bientôt échu', 'Habilitations', null, 'Programmer le renouvellement du permis.', 'employee'),
  ('LEGAL-RETENUE_LOGEMENT_PLAFOND','Retenue pour logement au-delà du plafond', 'Retenues', 'Arrêté 5040/ITLS/SM de 1956 (texte non lu, à confirmer)', 'Ramener la retenue au plafond ou déroger.', 'payroll'),
  ('PLANNING-DUREE_HEBDO_DEPASSEE','Durée hebdomadaire dépassée', 'Temps de travail', null, 'Revoir le planning de la semaine ou déroger.', 'planning'),
  ('PLANNING-REPOS_HEBDO_MANQUANT','Repos hebdomadaire manquant', 'Temps de travail', null, 'Planifier un jour de repos ou déroger.', 'planning')
on conflict (rule_id) do nothing;

-- ------------------------------------------------------------ dérogations
create table if not exists public.compliance_waivers (
  id               uuid primary key default gen_random_uuid(),
  rule_id          text not null,
  entity_id        uuid not null,
  employee_id      uuid references public.employees(id) on delete set null,
  reason           text not null check (length(btrim(reason)) > 0),
  parameter_code   text,
  parameter_value  numeric,
  status           text not null default 'active' check (status in ('active', 'remplacée', 'levée', 'révoquée')),
  granted_by       uuid references auth.users(id) on delete set null default auth.uid(),
  granted_at       timestamptz not null default now(),
  ended_at         timestamptz,
  ended_by         uuid references auth.users(id) on delete set null,
  ended_reason     text,
  check ((status = 'active') = (ended_at is null))
);
create unique index if not exists compliance_waivers_active_uniq on public.compliance_waivers (rule_id, entity_id) where status = 'active';
create index if not exists compliance_waivers_employee_idx on public.compliance_waivers (employee_id);
create index if not exists compliance_waivers_granted_by_idx on public.compliance_waivers (granted_by);
create index if not exists compliance_waivers_ended_by_idx on public.compliance_waivers (ended_by);
create index if not exists compliance_waivers_parameter_idx on public.compliance_waivers (parameter_code) where status = 'active';
alter table public.compliance_waivers enable row level security;
drop policy if exists compliance_waivers_read on public.compliance_waivers;
create policy compliance_waivers_read on public.compliance_waivers for select to authenticated
  using ((select public.has_role(array['admin', 'rh', 'paie'])));
revoke insert, update, delete on public.compliance_waivers from anon, authenticated;
grant select on public.compliance_waivers to authenticated;
drop trigger if exists compliance_waivers_audit on public.compliance_waivers;
create trigger compliance_waivers_audit after insert or update or delete on public.compliance_waivers
  for each row execute function public.business_audit();

-- ------------------------------------------------------------ journal des scans
create table if not exists public.compliance_scans (
  id             uuid primary key default gen_random_uuid(),
  scanned_at     timestamptz not null default now(),
  scanned_by     uuid references auth.users(id) on delete set null default auth.uid(),
  status         text not null check (status in ('vert', 'orange', 'rouge')),
  nb_bloquants   integer not null,
  nb_alertes     integer not null,
  nb_salaries    integer not null,
  nb_derogations integer not null,
  summary        jsonb not null default '{}'::jsonb
);
create index if not exists compliance_scans_scanned_at_idx on public.compliance_scans (scanned_at desc);
create index if not exists compliance_scans_scanned_by_idx on public.compliance_scans (scanned_by);
alter table public.compliance_scans enable row level security;
drop policy if exists compliance_scans_read on public.compliance_scans;
create policy compliance_scans_read on public.compliance_scans for select to authenticated
  using ((select public.has_role(array['admin', 'rh', 'paie'])));
revoke insert, update, delete on public.compliance_scans from anon, authenticated;
grant select on public.compliance_scans to authenticated;

-- ------------------------------------------------------------ détection étendue
create or replace function public.detecter_conformite()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new integer;
  v_cdd integer := coalesce((select a.value::integer from public.app_parameters a where a.code = 'cdd_max_months'), 24);
begin
  if not public.has_role(array['rh','paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis';
  end if;

  drop table if exists pg_temp._found;
  create temp table _found on commit drop as
  select 'EMB-DECL'::text as rule_id, 'A'::text as severity, 'employee'::text as entity, v.employee_id as entity_id, v.employee_id as employee_id,
         'Salarié ' || v.employee_number || ' : déclaration d''embauche non référencée' as message
    from public.v_conformite_embauche v where v.declaration_manquante
  union all
  select 'EMB-AFFIL', 'A', 'employee', v.employee_id, v.employee_id,
         'Salarié ' || v.employee_number || ' : affiliation absente ou au-delà de 2 mois après l''embauche'
    from public.v_conformite_embauche v where v.affiliation_hors_delai
  union all
  select 'RET-04', 'B', 'salary_slip', r.slip_id, r.employee_id,
         'Salarié ' || r.employee_number || ' ' || to_char(r.period_start, 'MM/YYYY') || ' : retenues sur net supérieures à la quotité cessible'
    from public.v_conformite_retenues r where r.depasse_quotite_cessible
  union all
  select 'RET-PLAFOND', 'B', 'salary_slip', r.slip_id, r.employee_id,
         'Salarié ' || r.employee_number || ' ' || to_char(r.period_start, 'MM/YYYY') || ' : retenues sur net supérieures au plafond des 2/3'
    from public.v_conformite_retenues r where r.depasse_plafond_global
  union all
  select 'COT-ECHEANCE', 'A', 'cotisation', md5('cotisation' || e.mois::text)::uuid, null::uuid,
         'Cotisations de ' || to_char(e.mois, 'MM/YYYY') || ' : échéance le ' || to_char(e.echeance, 'DD/MM/YYYY')
         || case when e.jours_restants < 0 then ' dépassée de ' || (-e.jours_restants) || ' j, majoration estimée ' || round(e.majoration_estimee) || ' F'
                 else ' dans ' || e.jours_restants || ' j' end
    from public.v_echeancier_cotisations e where e.paye_le is null and e.jours_restants <= 5
  union all
  -- alertes légales (erreur -> bloquant, alerte -> alerte ; les informations ne sont pas des écarts)
  select 'LEGAL-' || upper(a.code), case a.severity when 'erreur' then 'B' else 'A' end,
         case when a.employee_id is null then 'company' else 'employee' end,
         coalesce(a.employee_id, md5(a.code || coalesce(a.employee_name, ''))::uuid), a.employee_id, a.message
    from public.legal_alerts(current_date, 30) a where a.severity in ('erreur', 'alerte')
  union all
  -- planning : 28 derniers jours
  select 'PLANNING-' || upper(p.code), case p.severity when 'erreur' then 'B' else 'A' end, 'planning',
         md5(p.code || coalesce(p.employee_id::text, '') || coalesce(p.week_start::text, ''))::uuid, p.employee_id,
         p.employee_name || ' (semaine du ' || to_char(p.week_start, 'DD/MM/YYYY') || ') : ' || p.message
    from public.planning_compliance(current_date - 28, current_date) p where p.severity in ('erreur', 'alerte')
  union all
  -- durée maximale du CDD (art. 100) ; l'ouvrage déterminé relève d'une dérogation
  select 'CDD-DUREE', 'B', 'employee', e.id, e.id,
         'Salarié ' || e.employee_number || ' : CDD du ' || to_char(e.contract_start, 'DD/MM/YYYY') || ' au ' || to_char(e.contract_end, 'DD/MM/YYYY')
         || ', au-delà de ' || v_cdd || ' mois (sauf ouvrage déterminé)'
    from public.employees e
   where e.status = 'Active' and e.employment_type = 'CDD' and e.contract_start is not null and e.contract_end is not null
     and e.contract_end > (e.contract_start + make_interval(months => v_cdd))::date
  union all
  -- constantes modifiées dont la source légale n'est pas confirmée
  select 'PARAM-DEFAUT', 'A', 'parameter', md5('param' || o.code)::uuid, null::uuid,
         'Constante « ' || o.label || ' » modifiée (' || o.current_value || ' au lieu de ' || o.default_value || ') sans source légale confirmée'
    from public.parameter_overview(current_date) o
   where o.is_modified and coalesce(o.source_status, 'a_confirmer') <> 'confirme';

  insert into public.compliance_findings(rule_id, severity, entity, entity_id, employee_id, message)
  select f.rule_id, f.severity, f.entity, f.entity_id, f.employee_id, f.message from _found f
  on conflict (rule_id, entity_id) where resolved_on is null do nothing;
  get diagnostics v_new = row_count;

  update public.compliance_findings c set employee_id = f.employee_id
    from _found f where c.resolved_on is null and c.employee_id is null and f.employee_id is not null
     and f.rule_id = c.rule_id and f.entity_id = c.entity_id;

  update public.compliance_findings c set resolved_on = current_date
   where c.resolved_on is null
     and (c.rule_id in ('EMB-DECL','EMB-AFFIL','RET-04','RET-PLAFOND','COT-ECHEANCE','CDD-DUREE','PARAM-DEFAUT')
          or c.rule_id like 'LEGAL-%' or c.rule_id like 'PLANNING-%')
     and not exists (select 1 from _found f where f.rule_id = c.rule_id and f.entity_id = c.entity_id);
  return v_new;
end $$;

-- ------------------------------------------------------------ dérogations : octroi, révocation, levée
create or replace function public.grant_waiver(p_rule_id text, p_entity_id uuid, p_reason text, p_parameter_code text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  f public.compliance_findings;
  v_id uuid;
  v_value numeric;
begin
  if not public.has_role(array['admin']) then
    raise exception 'Droits insuffisants : rôle « admin » requis pour accorder une dérogation';
  end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'Un motif écrit est obligatoire pour déroger'; end if;
  select * into f from public.compliance_findings
   where rule_id = p_rule_id and entity_id = p_entity_id and resolved_on is null;
  if not found then raise exception 'Aucun écart ouvert pour cette règle et cette entité'; end if;
  if p_parameter_code is not null then
    select o.current_value into v_value from public.parameter_overview(current_date) o where o.code = p_parameter_code;
    if not found then raise exception 'Constante inconnue : %', p_parameter_code; end if;
  end if;
  update public.compliance_waivers
     set status = 'remplacée', ended_at = now(), ended_by = auth.uid(), ended_reason = 'Remplacée par une nouvelle dérogation'
   where rule_id = p_rule_id and entity_id = p_entity_id and status = 'active';
  insert into public.compliance_waivers (rule_id, entity_id, employee_id, reason, parameter_code, parameter_value)
  values (p_rule_id, p_entity_id, f.employee_id, btrim(p_reason), p_parameter_code, v_value)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.revoke_waiver(p_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['admin']) then
    raise exception 'Droits insuffisants : rôle « admin » requis pour révoquer une dérogation';
  end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'Un motif est obligatoire pour révoquer'; end if;
  update public.compliance_waivers
     set status = 'révoquée', ended_at = now(), ended_by = auth.uid(), ended_reason = btrim(p_reason)
   where id = p_id and status = 'active';
  if not found then raise exception 'Dérogation introuvable ou déjà terminée'; end if;
end $$;

-- Les dérogations liées à une constante ou à un barème sont levées quand on le réinitialise (appelée par reset_parameter et scale_reset)
create or replace function public.lift_waivers(p_code text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare n integer;
begin
  update public.compliance_waivers
     set status = 'levée', ended_at = now(), ended_by = auth.uid(), ended_reason = 'Réinitialisation de ' || p_code
   where parameter_code = p_code and status = 'active';
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.reset_parameter(p_code text, p_effective_from date default null)
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.parameter_catalog;
  v_eff date;
begin
  if not public.has_role(array['admin']) then
    raise exception 'Droits insuffisants : rôle « admin » requis pour réinitialiser une constante légale';
  end if;
  select * into c from public.parameter_catalog where code = p_code;
  if not found then raise exception 'Constante inconnue : %', p_code; end if;
  v_eff := public.set_parameter(p_code, c.default_value, p_effective_from);
  if c.store = 'payroll_settings' then
    -- les versions futures encore modifiables reviennent aussi à la valeur d'origine
    execute format('update public.payroll_settings set %I = $1 where effective_from > $2', c.column_name)
      using c.default_value, v_eff;
  end if;
  perform public.lift_waivers(p_code);
  return v_eff;
end $$;

create or replace function public.scale_reset(p_code text, p_effective_from date)
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare v_lines jsonb; d date;
begin
  if not public.has_role(array['admin']) then
    raise exception 'Droits insuffisants : rôle « admin » requis pour réinitialiser un barème';
  end if;
  select lines into v_lines from public.scale_defaults where scale_code = p_code;
  if not found then raise exception 'Barème inconnu : %', p_code; end if;
  perform public.scale_save(p_code, p_effective_from, v_lines);
  -- les versions futures encore modifiables reviennent aussi au jeu d'origine
  for d in select x from public.scale_version_dates(p_code) x where x > p_effective_from loop
    perform public.scale_save(p_code, d, v_lines);
  end loop;
  perform public.lift_waivers(p_code);
  return p_effective_from;
end $$;

-- ------------------------------------------------------------ lecture et scan
create or replace function public.compliance_open_findings()
returns table (
  finding_id uuid, rule_id text, rule_label text, domain text, legal_ref text, suggested_action text, fix_target text,
  severity text, entity text, entity_id uuid, employee_id uuid, employee_number text, employee_name text,
  message text, detected_on date, waived boolean, waiver_id uuid, waiver_reason text, waiver_by uuid, waiver_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « admin », « rh » ou « paie » requis';
  end if;
  return query
  select f.id, f.rule_id, coalesce(r.label, f.rule_id), coalesce(r.domain, 'Autres'), r.legal_ref,
         coalesce(r.suggested_action, 'Examiner l''écart et corriger ou déroger.'), coalesce(r.fix_target, 'employee'),
         f.severity, f.entity, f.entity_id, f.employee_id, e.employee_number, e.last_name || ' ' || e.first_name,
         f.message, f.detected_on,
         (w.id is not null or f.waived_by is not null), w.id, coalesce(w.reason, f.waiver_reason),
         coalesce(w.granted_by, f.waived_by), w.granted_at
    from public.compliance_findings f
    left join public.compliance_rules r on r.rule_id = f.rule_id
    left join public.employees e on e.id = f.employee_id
    left join lateral (select x.* from public.compliance_waivers x
                        where x.rule_id = f.rule_id and x.entity_id = f.entity_id and x.status = 'active' limit 1) w on true
   where f.resolved_on is null
   order by (f.severity = 'B') desc, f.detected_on desc, f.rule_id;
end $$;

create or replace function public.run_compliance_scan()
returns public.compliance_scans
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.compliance_scans;
  v_b integer; v_a integer; v_emp integer; v_w integer; v_sum jsonb;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « admin », « rh » ou « paie » requis';
  end if;
  perform public.detecter_conformite();
  select count(*) filter (where not o.waived and o.severity = 'B'),
         count(*) filter (where not o.waived and o.severity = 'A'),
         count(distinct o.employee_id) filter (where not o.waived),
         count(*) filter (where o.waived)
    into v_b, v_a, v_emp, v_w
    from public.compliance_open_findings() o;
  select coalesce(jsonb_object_agg(x.rule_id, x.n), '{}'::jsonb) into v_sum
    from (select o.rule_id, count(*) as n from public.compliance_open_findings() o where not o.waived group by o.rule_id) x;
  insert into public.compliance_scans (status, nb_bloquants, nb_alertes, nb_salaries, nb_derogations, summary)
  values (case when v_b > 0 then 'rouge' when v_a > 0 then 'orange' else 'vert' end, v_b, v_a, v_emp, v_w, v_sum)
  returning * into s;
  return s;
end $$;

-- Dernier scan, pour le tableau de bord (obsolète au-delà de 24 h)
create or replace function public.compliance_status()
returns table (scanned_at timestamptz, status text, nb_bloquants integer, nb_alertes integer, nb_salaries integer, nb_derogations integer, stale boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « admin », « rh » ou « paie » requis';
  end if;
  return query
  select s.scanned_at, s.status, s.nb_bloquants, s.nb_alertes, s.nb_salaries, s.nb_derogations, s.scanned_at < now() - interval '24 hours'
    from public.compliance_scans s order by s.scanned_at desc limit 1;
end $$;

revoke all on function public.detecter_conformite() from public, anon;
revoke all on function public.grant_waiver(text, uuid, text, text) from public, anon;
revoke all on function public.revoke_waiver(uuid, text) from public, anon;
revoke all on function public.lift_waivers(text) from public, anon, authenticated;
revoke all on function public.reset_parameter(text, date) from public, anon;
revoke all on function public.scale_reset(text, date) from public, anon;
revoke all on function public.compliance_open_findings() from public, anon;
revoke all on function public.run_compliance_scan() from public, anon;
revoke all on function public.compliance_status() from public, anon;
grant execute on function public.detecter_conformite() to authenticated;
grant execute on function public.grant_waiver(text, uuid, text, text) to authenticated;
grant execute on function public.revoke_waiver(uuid, text) to authenticated;
grant execute on function public.reset_parameter(text, date) to authenticated;
grant execute on function public.scale_reset(text, date) to authenticated;
grant execute on function public.compliance_open_findings() to authenticated;
grant execute on function public.run_compliance_scan() to authenticated;
grant execute on function public.compliance_status() to authenticated;

notify pgrst, 'reload schema';
