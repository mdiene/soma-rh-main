-- =============================================================================
-- Centre de conformité, lot L1a : catalogue des constantes légales, modification versionnée, remise à la valeur d'origine.
-- Cadrage : docs/CADRAGE_CENTRE_CONFORMITE.md (§4.1, §4.2, §8).
--   parameter_catalog            métadonnées (libellé, unité, bornes, valeur d'origine, texte de loi, source) ; ne stocke PAS la valeur
--   payroll_locked_until()       dernier jour couvert par une paie déjà calculée (statut autre que Brouillon / Annulée)
--   parameters_min_effective_date() première date d'effet permise (1er du mois suivant)
--   parameter_overview(date)     catalogue + valeur en vigueur à une date (alimente l'onglet « Constantes »)
--   set_parameter / reset_parameter / set_parameter_reference   réservés à l'administrateur (le circuit RH -> admin vient en L2b)
--   payroll_settings_guard       une ligne de paramètres utilisée par une paie calculée ne peut plus être modifiée ni supprimée
-- Valeur d'origine = valeur par défaut de la colonne payroll_settings (reprise du classeur historique) ; 0,33 pour le plafond de prêt.
-- Les références légales ne reprennent que ce que legal_sources documente déjà ; le reste est laissé vide (« à fournir »).
-- Retour : db/rollback/20261204090000_l1a_catalogue_constantes_down.sql
-- =============================================================================

-- ------------------------------------------------------------ paies verrouillées
create or replace function public.payroll_locked_until()
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select max(d) from (
    select period_end as d from public.payroll_entries where status not in ('Brouillon', 'Annulée')
    union all
    select period_end from public.payroll_periods where status not in ('Brouillon', 'Annulée')
  ) x;
$$;

create or replace function public.parameters_min_effective_date()
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (date_trunc('month', public.payroll_locked_until()) + interval '1 month')::date;
$$;

-- ------------------------------------------------------------ garde sur payroll_settings
create or replace function public.payroll_settings_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_until date := public.payroll_locked_until();
  v_next date;
begin
  if tg_op in ('INSERT', 'UPDATE') and v_until is not null
     and (tg_op = 'INSERT' or new.effective_from is distinct from old.effective_from)
     and new.effective_from <= v_until then
    raise exception 'Date d''effet % refusée : des paies sont déjà calculées jusqu''au %. Choisissez le % ou une date postérieure.',
      new.effective_from, v_until, public.parameters_min_effective_date();
  end if;
  if tg_op in ('UPDATE', 'DELETE') then
    select min(s.effective_from) into v_next from public.payroll_settings s where s.effective_from > old.effective_from;
    if exists (
      select 1 from (
        select period_end from public.payroll_entries where status not in ('Brouillon', 'Annulée')
        union all
        select period_end from public.payroll_periods where status not in ('Brouillon', 'Annulée')
      ) l
      where l.period_end >= old.effective_from and (v_next is null or l.period_end < v_next)
    ) then
      raise exception 'Les paramètres en vigueur depuis le % servent à des paies déjà calculées : ils ne peuvent plus être modifiés. Créez une nouvelle version datée.', old.effective_from;
    end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
revoke execute on function public.payroll_settings_guard() from public, anon, authenticated;

drop trigger if exists payroll_settings_guard on public.payroll_settings;
create trigger payroll_settings_guard before insert or update or delete on public.payroll_settings
  for each row execute function public.payroll_settings_guard();

-- ------------------------------------------------------------ catalogue
create table if not exists public.parameter_catalog (
  code           text primary key,
  domain         text not null,
  label          text not null,
  unit           text not null check (unit in ('FCFA', 'taux', 'h', 'nb', 'mois', 'ans')),
  sort           integer not null default 0,
  store          text not null check (store in ('payroll_settings', 'app_parameters')),
  column_name    text not null,
  default_value  numeric not null,
  min_value      numeric,
  max_value      numeric,
  source_code    text references public.legal_sources(code) on delete set null,
  legal_text     text,
  updated_at     timestamptz not null default now(),
  check (min_value is null or max_value is null or min_value <= max_value)
);
create index if not exists parameter_catalog_source_idx on public.parameter_catalog (source_code);
comment on table public.parameter_catalog is 'Description des constantes légales éditables. La valeur vit dans payroll_settings (versionnée par date d''effet) ou app_parameters.';
comment on column public.parameter_catalog.unit is '« taux » = fraction stockée (0,07) affichée en pourcentage.';

alter table public.parameter_catalog enable row level security;
drop policy if exists parameter_catalog_read on public.parameter_catalog;
create policy parameter_catalog_read on public.parameter_catalog for select to authenticated
  using ((select public.has_role(array['admin', 'rh', 'paie'])));
revoke insert, update, delete on public.parameter_catalog from anon, authenticated;
grant select on public.parameter_catalog to authenticated;

drop trigger if exists parameter_catalog_audit on public.parameter_catalog;
create trigger parameter_catalog_audit after insert or update or delete on public.parameter_catalog
  for each row execute function public.business_audit();

-- Amorçage : (code, domaine, libellé, unité, ordre, magasin, colonne, min, max, source, texte)
do $$
declare
  r record;
  v_default numeric;
  v_txt text;
begin
  for r in
    select * from (values
      ('monthly_hours',           'Temps de travail',    'Base horaire mensuelle',                         'h',    10, 'payroll_settings', 'monthly_hours',           1,   300,  null,           'Base mensuelle de 173,33 h (40 h x 52 / 12) ; valeur du classeur de paie historique.'),
      ('hourly_rate_divisor',     'Temps de travail',    'Diviseur du taux horaire',                       'h',    20, 'payroll_settings', 'hourly_rate_divisor',     1,   300,  null,           'Diviseur 40 x 52 / 12 servant à calculer le taux horaire à partir du salaire mensuel.'),
      ('ipres_rg_ceiling',        'Cotisations sociales','Plafond IPRES régime général (mensuel)',          'FCFA', 10, 'payroll_settings', 'ipres_rg_ceiling',        0,   null, null,           'Plafond mensuel du régime général : 360 000 x 1,2 (classeur historique).'),
      ('ipres_rg_rate',           'Cotisations sociales','Taux IPRES régime général',                      'taux', 20, 'payroll_settings', 'ipres_rg_rate',           0,   1,    null,           'Taux global du régime général, réparti entre employeur et salarié.'),
      ('ipres_rg_employee_share', 'Cotisations sociales','Part salariale IPRES régime général',            'taux', 30, 'payroll_settings', 'ipres_rg_employee_share', 0,   1,    null,           'Part du taux global supportée par le salarié.'),
      ('ipres_rc_ceiling',        'Cotisations sociales','Plafond IPRES régime complémentaire (mensuel)',   'FCFA', 40, 'payroll_settings', 'ipres_rc_ceiling',        0,   null, null,           'Plafond mensuel du régime complémentaire : 1 080 000 x 1,2 (classeur historique).'),
      ('ipres_rc_rate',           'Cotisations sociales','Taux IPRES régime complémentaire',               'taux', 50, 'payroll_settings', 'ipres_rc_rate',           0,   1,    null,           'Taux global du régime complémentaire (cadres), réparti entre employeur et salarié.'),
      ('ipres_rc_employee_share', 'Cotisations sociales','Part salariale IPRES régime complémentaire',     'taux', 60, 'payroll_settings', 'ipres_rc_employee_share', 0,   1,    null,           'Part du taux global supportée par le salarié.'),
      ('css_ceiling',             'Cotisations sociales','Plafond CSS (mensuel)',                          'FCFA', 70, 'payroll_settings', 'css_ceiling',             0,   null, 'CSS_PLAFOND_AT','Plafond mensuel des cotisations de Sécurité sociale (prestations familiales, accidents du travail). Source à fournir et à confirmer.'),
      ('css_af_rate',             'Cotisations sociales','Taux CSS prestations familiales',                'taux', 80, 'payroll_settings', 'css_af_rate',             0,   1,    null,           'Cotisation patronale de prestations familiales.'),
      ('css_at_rate',             'Cotisations sociales','Taux CSS accidents du travail',                  'taux', 90, 'payroll_settings', 'css_at_rate',             0,   1,    'CSS_PLAFOND_AT','Taux accidents du travail par défaut ; le taux propre à la société prévaut s''il est renseigné.'),
      ('ipm_ceiling',             'Cotisations sociales','Plafond IPM (mensuel)',                          'FCFA', 100,'payroll_settings', 'ipm_ceiling',             0,   null, null,           'Plafond de l''assiette de l''institution de prévoyance maladie.'),
      ('ipm_rate',                'Cotisations sociales','Taux IPM',                                       'taux', 110,'payroll_settings', 'ipm_rate',                0,   1,    null,           'Taux appliqué à l''assiette IPM.'),
      ('ipm_employee_share',      'Cotisations sociales','Part salariale IPM',                             'taux', 120,'payroll_settings', 'ipm_employee_share',      0,   1,    null,           'Part de la cotisation IPM supportée par le salarié.'),
      ('cfce_rate',               'Cotisations sociales','Taux CFCE',                                      'taux', 130,'payroll_settings', 'cfce_rate',               0,   1,    null,           'Contribution forfaitaire à la charge de l''employeur.'),
      ('brs_rate',                'Cotisations sociales','Taux BRS',                                       'taux', 140,'payroll_settings', 'brs_rate',                0,   1,    null,           'Taux de la retenue appliquée selon le classeur de paie historique.'),
      ('ir_abatement_rate',       'Impôt',               'Taux d''abattement de l''impôt sur le revenu',   'taux', 10, 'payroll_settings', 'ir_abatement_rate',       0,   1,    null,           'Abattement forfaitaire sur le revenu imposable.'),
      ('ir_abatement_cap',        'Impôt',               'Plafond annuel de l''abattement',                'FCFA', 20, 'payroll_settings', 'ir_abatement_cap',        0,   null, null,           'Plafond annuel de l''abattement forfaitaire.'),
      ('smig_hourly',             'Salaire et indemnités','SMIG horaire',                                  'FCFA', 10, 'payroll_settings', 'smig_hourly',             0,   null, null,           'Salaire minimum horaire. Le plancher légal retenu par le contrôle de conformité est documenté dans la migration C26 JO 4091.'),
      ('transport_allowance',     'Salaire et indemnités','Indemnité de transport',                        'FCFA', 20, 'payroll_settings', 'transport_allowance',     0,   null, null,           'Montant mensuel de l''indemnité de transport.'),
      ('meal_allowance_factor',   'Salaire et indemnités','Coefficient de l''indemnité de panier',         'nb',   30, 'payroll_settings', 'meal_allowance_factor',   0,   null, null,           'Indemnité de panier = nombre de jours x SMIG horaire x ce coefficient.'),
      ('km_allowance',            'Salaire et indemnités','Indemnité kilométrique (montant de référence)', 'FCFA', 40, 'payroll_settings', 'km_allowance',            0,   null, null,           'Montant de référence de l''indemnité kilométrique du classeur historique.'),
      ('precarity_rate',          'Salaire et indemnités','Taux d''indemnité de précarité',                'taux', 50, 'payroll_settings', 'precarity_rate',          0,   1,    null,           'Taux de l''indemnité de fin de contrat à durée déterminée.'),
      ('seniority_min_years',     'Salaire et indemnités','Ancienneté minimale pour la prime d''ancienneté','ans',  60, 'payroll_settings', 'seniority_min_years',     0,   50,   null,           'Nombre d''années révolues avant que la prime d''ancienneté ne commence.'),
      ('severance_min_months',    'Salaire et indemnités','Ancienneté minimale pour l''indemnité de licenciement','mois',70,'payroll_settings','severance_min_months',   0,   120,  'CCNI_80',      'Ancienneté minimale en mois ouvrant droit à l''indemnité de licenciement (CCNI, à confirmer).'),
      ('deduction_global_cap',    'Retenues',            'Plafond global des retenues sur net (part du salaire)','taux',10,'payroll_settings','deduction_global_cap',  0,   1,    'CT26_216',     'Plafond des deux tiers pour l''ensemble des retenues sur salaire (renvoi du Code du Travail 2026 art. 216).'),
      ('loan_max_rate',           'Retenues',            'Plafond de la retenue mensuelle de prêt (part du brut)','taux',20,'app_parameters','loan_max_rate',          0.01,1,    null,           'Une échéance de prêt ne peut dépasser cette part du brut mensuel.'),
      ('interim_ifc_rate',        'Intérim',             'Taux de l''indemnité de fin de mission (IFC)',   'taux', 10, 'payroll_settings', 'interim_ifc_rate',        0,   1,    'IFC_INTERIM',  'Indemnité de fin de mission des travailleurs intérimaires (décret 2009-1412).')
    ) as v(code, domain, label, unit, sort, store, column_name, min_value, max_value, source_code, legal_text)
  loop
    if r.store = 'app_parameters' then
      v_default := 0.33;
    else
      select split_part(column_default, '::', 1) into v_txt
        from information_schema.columns
       where table_schema = 'public' and table_name = 'payroll_settings' and column_name = r.column_name;
      begin
        v_default := trim(both '()' from v_txt)::numeric;
      exception when others then
        v_default := null;
      end;
      if v_default is null then   -- pas de valeur par défaut de colonne : on retient la valeur actuelle
        execute format('select %I::numeric from public.payroll_settings order by effective_from limit 1', r.column_name) into v_default;
      end if;
    end if;
    if v_default is null then raise exception 'Valeur d''origine introuvable pour %', r.code; end if;
    insert into public.parameter_catalog (code, domain, label, unit, sort, store, column_name, default_value, min_value, max_value, source_code, legal_text)
    values (r.code, r.domain, r.label, r.unit, r.sort, r.store, r.column_name, v_default, r.min_value, r.max_value, r.source_code, r.legal_text)
    on conflict (code) do nothing;
  end loop;
end $$;

-- ------------------------------------------------------------ lecture : catalogue + valeur en vigueur
create or replace function public.parameter_overview(p_as_of date default current_date)
returns table (
  code text, domain text, label text, unit text, sort integer,
  current_value numeric, default_value numeric, is_modified boolean, effective_from date,
  min_value numeric, max_value numeric,
  source_code text, source_label text, source_document text, source_article text, source_status text, legal_text text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare s public.payroll_settings;
begin
  if not public.has_role(array['admin', 'rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « admin », « rh » ou « paie » requis';
  end if;
  s := public.payroll_settings_at(p_as_of);
  return query
  select c.code, c.domain, c.label, c.unit, c.sort,
         v.val, c.default_value, v.val is distinct from c.default_value, v.eff,
         c.min_value, c.max_value,
         c.source_code, ls.label, ls.document, ls.article, ls.status, c.legal_text
    from public.parameter_catalog c
    left join public.legal_sources ls on ls.code = c.source_code
    cross join lateral (
      select case c.store
               when 'payroll_settings' then (to_jsonb(s) ->> c.column_name)::numeric
               else (select a.value from public.app_parameters a where a.code = c.column_name)
             end as val,
             case c.store when 'payroll_settings' then s.effective_from end as eff
    ) v
   order by c.domain, c.sort, c.code;
end $$;

-- ------------------------------------------------------------ écriture (administrateur)
create or replace function public.set_parameter(p_code text, p_value numeric, p_effective_from date default null)
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.parameter_catalog;
  v_floor date := public.parameters_min_effective_date();
  v_eff date;
  v_row public.payroll_settings;
  v_type text;
begin
  if not public.has_role(array['admin']) then
    raise exception 'Droits insuffisants : rôle « admin » requis pour modifier une constante légale';
  end if;
  select * into c from public.parameter_catalog where code = p_code;
  if not found then raise exception 'Constante inconnue : %', p_code; end if;
  if p_value is null then raise exception 'Une valeur est obligatoire'; end if;
  if c.min_value is not null and p_value < c.min_value then
    raise exception '« % » : la valeur % est inférieure au minimum autorisé (%)', c.label, p_value, c.min_value;
  end if;
  if c.max_value is not null and p_value > c.max_value then
    raise exception '« % » : la valeur % dépasse le maximum autorisé (%)', c.label, p_value, c.max_value;
  end if;

  if c.store = 'app_parameters' then
    insert into public.app_parameters (code, label, value, updated_by)
    values (c.column_name, c.label, p_value, auth.uid())
    on conflict (code) do update set value = excluded.value, updated_by = auth.uid(), updated_at = now();
    return null;
  end if;

  select data_type into v_type from information_schema.columns
   where table_schema = 'public' and table_name = 'payroll_settings' and column_name = c.column_name;
  if v_type in ('integer', 'smallint', 'bigint') and p_value <> trunc(p_value) then
    raise exception '« % » doit être un nombre entier', c.label;
  end if;

  v_eff := coalesce(p_effective_from, v_floor, date_trunc('month', current_date)::date);
  if v_eff <> date_trunc('month', v_eff)::date then
    raise exception 'La date d''effet doit être le premier jour d''un mois (reçu : %)', v_eff;
  end if;
  if v_floor is not null and v_eff < v_floor then
    raise exception 'Date d''effet % refusée : des paies sont déjà calculées. Première date possible : %', v_eff, v_floor;
  end if;

  if exists (select 1 from public.payroll_settings where effective_from = v_eff) then
    execute format('update public.payroll_settings set %I = $1 where effective_from = $2', c.column_name)
      using p_value, v_eff;
  else
    v_row := public.payroll_settings_at(v_eff);
    if v_row.id is null then
      select * into v_row from public.payroll_settings order by effective_from limit 1;   -- date antérieure à toute version : on part de la plus ancienne
    end if;
    insert into public.payroll_settings
    select (jsonb_populate_record(v_row, jsonb_build_object(
      'id', gen_random_uuid(), 'effective_from', v_eff, 'created_at', now(), c.column_name, p_value))).*;
  end if;
  return v_eff;
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
  return v_eff;
end $$;

create or replace function public.set_parameter_reference(p_code text, p_legal_text text, p_source_code text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['admin']) then
    raise exception 'Droits insuffisants : rôle « admin » requis pour modifier une référence légale';
  end if;
  if p_source_code is not null and not exists (select 1 from public.legal_sources where code = p_source_code) then
    raise exception 'Source légale inconnue : %', p_source_code;
  end if;
  update public.parameter_catalog
     set legal_text = nullif(trim(p_legal_text), ''), source_code = p_source_code, updated_at = now()
   where code = p_code;
  if not found then raise exception 'Constante inconnue : %', p_code; end if;
end $$;

revoke all on function public.payroll_locked_until() from public, anon;
revoke all on function public.parameters_min_effective_date() from public, anon;
revoke all on function public.parameter_overview(date) from public, anon;
revoke all on function public.set_parameter(text, numeric, date) from public, anon;
revoke all on function public.reset_parameter(text, date) from public, anon;
revoke all on function public.set_parameter_reference(text, text, text) from public, anon;
grant execute on function public.payroll_locked_until() to authenticated;
grant execute on function public.parameters_min_effective_date() to authenticated;
grant execute on function public.parameter_overview(date) to authenticated;
grant execute on function public.set_parameter(text, numeric, date) to authenticated;
grant execute on function public.reset_parameter(text, date) to authenticated;
grant execute on function public.set_parameter_reference(text, text, text) to authenticated;

notify pgrst, 'reload schema';
