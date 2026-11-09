-- =============================================================================
-- Centre de conformité, lot L1b (2/2) : catalogue et édition des barèmes (réservées à l'administrateur ; circuit RH -> admin en L2b).
-- Barèmes : IR (barème, réductions familiales, TRIMF), HS, PREAVIS, QUOTITE_PRINCIPAL, QUOTITE_SUPPLEMENTAIRE, LICENCIEMENT, RETRAITE.
--   scale_catalog / scale_defaults   description et jeu d'origine de chaque barème
--   scale_overview(date)             barème en vigueur, modifié ou non, nombre de versions, prochaine date libre
--   scale_versions(code)             versions datées et leur verrou
--   scale_get(code, date)            lignes en vigueur (jsonb)
--   scale_save(code, date, lignes)   crée (ou remplace, si non verrouillé) le jeu daté, après contrôles de continuité des tranches
--   scale_reset(code, date)          remet le jeu d'origine à cette date et sur les versions futures encore modifiables
--   set_scale_reference(...)         texte de loi et source, réglables par l'administrateur
-- Retour : db/rollback/20261206100000_l1b_baremes_edition_down.sql
-- =============================================================================

create table if not exists public.scale_catalog (
  code         text primary key,
  label        text not null,
  sort         integer not null default 0,
  source_code  text references public.legal_sources(code) on delete set null,
  legal_text   text,
  updated_at   timestamptz not null default now()
);
create index if not exists scale_catalog_source_idx on public.scale_catalog (source_code);
create table if not exists public.scale_defaults (
  scale_code  text primary key references public.scale_catalog(code) on delete cascade,
  lines       jsonb not null
);
alter table public.scale_catalog enable row level security;
alter table public.scale_defaults enable row level security;
drop policy if exists scale_catalog_read on public.scale_catalog;
create policy scale_catalog_read on public.scale_catalog for select to authenticated
  using ((select public.has_role(array['admin', 'rh', 'paie'])));
drop policy if exists scale_defaults_read on public.scale_defaults;
create policy scale_defaults_read on public.scale_defaults for select to authenticated
  using ((select public.has_role(array['admin', 'rh', 'paie'])));
revoke insert, update, delete on public.scale_catalog, public.scale_defaults from anon, authenticated;
grant select on public.scale_catalog, public.scale_defaults to authenticated;
drop trigger if exists scale_catalog_audit on public.scale_catalog;
create trigger scale_catalog_audit after insert or update or delete on public.scale_catalog
  for each row execute function public.business_audit();

-- ------------------------------------------------------------ lecture interne
create or replace function public.scale_lines(p_code text, p_on date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v jsonb; v_slab uuid;
begin
  case p_code
    when 'HS' then
      select coalesce(jsonb_agg(jsonb_build_object('code', r.code, 'label', r.label, 'rate_uplift', r.rate_uplift,
               'hours_from', r.hours_from, 'hours_to', r.hours_to, 'source_code', r.source_code,
               'legal_min_uplift', r.legal_min_uplift, 'legal_min_source', r.legal_min_source) order by r.code), '[]'::jsonb)
        into v from public.overtime_rates r
       where r.effective_from = (select max(x.effective_from) from public.overtime_rates x where x.effective_from <= p_on);
    when 'PREAVIS' then
      select coalesce(jsonb_agg(jsonb_build_object('agreement_code', n.agreement_code, 'category', n.category,
               'notice_months', n.notice_months, 'free_days_week', n.free_days_week, 'source_code', n.source_code)
               order by n.category, n.agreement_code nulls first), '[]'::jsonb)
        into v from public.notice_scales n
       where n.valid_from = (select max(x.valid_from) from public.notice_scales x where x.valid_from <= p_on);
    when 'QUOTITE_PRINCIPAL', 'QUOTITE_SUPPLEMENTAIRE' then
      select coalesce(jsonb_agg(jsonb_build_object('lower_bound', g.lower_bound, 'upper_bound', g.upper_bound,
               'rate', g.rate, 'source_code', g.source_code) order by g.lower_bound), '[]'::jsonb)
        into v from public.garnishment_scale g
       where g.kind = substr(p_code, 9)
         and g.effective_from = (select max(x.effective_from) from public.garnishment_scale x
                                  where x.kind = substr(p_code, 9) and x.effective_from <= p_on);
    when 'LICENCIEMENT', 'RETRAITE' then
      select coalesce(jsonb_agg(jsonb_build_object('year_from', s.year_from, 'year_to', s.year_to,
               'rate', s.rate, 'source_code', s.source_code) order by s.year_from), '[]'::jsonb)
        into v from public.severance_scales s
       where s.kind = p_code
         and s.effective_from = (select max(x.effective_from) from public.severance_scales x
                                  where x.kind = p_code and x.effective_from <= p_on);
    when 'IR' then
      v_slab := public.tax_slab_at(p_on);
      v := jsonb_build_object(
        'brackets', (select coalesce(jsonb_agg(jsonb_build_object('from_amount', b.from_amount, 'rate', b.rate) order by b.from_amount), '[]'::jsonb)
                       from public.tax_slab_brackets b where b.slab_id = v_slab),
        'reductions', (select coalesce(jsonb_agg(jsonb_build_object('parts', f.parts, 'rate', f.rate,
                         'min_amount', f.min_amount, 'max_amount', f.max_amount) order by f.parts), '[]'::jsonb)
                       from public.ir_family_reductions f where f.slab_id = v_slab),
        'trimf', (select coalesce(jsonb_agg(jsonb_build_object('min_annual_gross', t.min_annual_gross,
                    'annual_amount', t.annual_amount, 'per_part', t.per_part) order by t.min_annual_gross), '[]'::jsonb)
                  from public.trimf_brackets t where t.slab_id = v_slab));
    else
      raise exception 'Barème inconnu : %', p_code;
  end case;
  return v;
end $$;

create or replace function public.scale_version_dates(p_code text)
returns setof date
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  case p_code
    when 'HS' then return query select distinct effective_from from public.overtime_rates order by 1;
    when 'PREAVIS' then return query select distinct valid_from from public.notice_scales order by 1;
    when 'QUOTITE_PRINCIPAL', 'QUOTITE_SUPPLEMENTAIRE' then
      return query select distinct effective_from from public.garnishment_scale where kind = substr(p_code, 9) order by 1;
    when 'LICENCIEMENT', 'RETRAITE' then
      return query select distinct effective_from from public.severance_scales where kind = p_code order by 1;
    when 'IR' then return query select effective_from from public.tax_slabs order by 1;
    else raise exception 'Barème inconnu : %', p_code;
  end case;
end $$;

-- ------------------------------------------------------------ contrôles
create or replace function public.scale_check_ranges(p_lines jsonb, p_lo text, p_hi text, p_label text)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare r record; v_prev_hi numeric; v_first boolean := true;
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception '% : au moins une tranche est requise', p_label;
  end if;
  for r in select (e ->> p_lo)::numeric as lo, (e ->> p_hi)::numeric as hi, (e ->> 'rate')::numeric as rate
             from jsonb_array_elements(p_lines) e order by (e ->> p_lo)::numeric loop
    if r.lo is null then raise exception '% : borne basse manquante', p_label; end if;
    if v_first then
      if r.lo <> 0 then raise exception '% : la première tranche doit commencer à 0 (reçu %)', p_label, r.lo; end if;
      v_first := false;
    else
      if v_prev_hi is null then raise exception '% : seule la dernière tranche peut être sans borne haute', p_label; end if;
      if r.lo <> v_prev_hi then
        raise exception '% : la tranche commençant à % ne suit pas la précédente (qui finit à %)', p_label, r.lo, v_prev_hi;
      end if;
    end if;
    if r.hi is not null and r.hi <= r.lo then raise exception '% : la tranche % est vide ou inversée', p_label, r.lo; end if;
    if r.rate is null or r.rate <= 0 or r.rate > 1 then
      raise exception '% : le taux de la tranche % doit être compris entre 0 (exclu) et 1', p_label, r.lo;
    end if;
    v_prev_hi := r.hi;
  end loop;
  if v_prev_hi is not null then raise exception '% : la dernière tranche doit être sans borne haute', p_label; end if;
end $$;

create or replace function public.scale_validate(p_code text, p_lines jsonb)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare r record; v_base jsonb;
begin
  case p_code
    when 'QUOTITE_PRINCIPAL', 'QUOTITE_SUPPLEMENTAIRE' then
      perform public.scale_check_ranges(p_lines, 'lower_bound', 'upper_bound', 'Quotité cessible');
    when 'LICENCIEMENT', 'RETRAITE' then
      perform public.scale_check_ranges(p_lines, 'year_from', 'year_to', 'Indemnité ' || lower(p_code));
    when 'HS' then
      if jsonb_typeof(p_lines) <> 'array' then raise exception 'Heures supplémentaires : une liste de lignes est attendue'; end if;
      v_base := public.scale_lines('HS', current_date);
      if (select array_agg(e ->> 'code' order by e ->> 'code') from jsonb_array_elements(p_lines) e)
         is distinct from (select array_agg(e ->> 'code' order by e ->> 'code') from jsonb_array_elements(v_base) e) then
        raise exception 'Heures supplémentaires : les codes de majoration doivent rester les mêmes que ceux du barème en vigueur (aucun ajout ni retrait)';
      end if;
      for r in select l.code, l.rate_uplift, b.legal_min_uplift
                 from jsonb_to_recordset(p_lines) as l(code text, rate_uplift numeric)
                 join jsonb_to_recordset(v_base) as b(code text, legal_min_uplift numeric) on b.code = l.code loop
        if r.rate_uplift is null or r.rate_uplift < 0 then raise exception 'Heures supplémentaires : majoration invalide pour %', r.code; end if;
        if r.rate_uplift < coalesce(r.legal_min_uplift, 0) then
          raise exception 'Heures supplémentaires : la majoration de % (%) est inférieure au minimum légal (%)', r.code, r.rate_uplift, r.legal_min_uplift;
        end if;
      end loop;
    when 'PREAVIS' then
      if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'Préavis : au moins une ligne est requise'; end if;
      for r in select * from jsonb_to_recordset(p_lines) as l(agreement_code text, category text, notice_months numeric, free_days_week smallint, source_code text) loop
        if r.category not in ('OUVRIER_EMPLOYE', 'MAITRISE', 'CADRE') then raise exception 'Préavis : catégorie invalide (%)', r.category; end if;
        if r.notice_months is null or r.notice_months < 0 then raise exception 'Préavis : durée invalide pour %', r.category; end if;
        if coalesce(r.free_days_week, 0) < 0 then raise exception 'Préavis : jours libres invalides pour %', r.category; end if;
      end loop;
    when 'IR' then
      if jsonb_typeof(p_lines) <> 'object' then raise exception 'Impôt : un objet {brackets, reductions, trimf} est attendu'; end if;
      if jsonb_array_length(coalesce(p_lines -> 'brackets', '[]'::jsonb)) = 0 then raise exception 'Impôt : le barème doit contenir au moins une tranche'; end if;
      if (select min((e ->> 'from_amount')::numeric) from jsonb_array_elements(p_lines -> 'brackets') e) <> 0 then
        raise exception 'Impôt : la première tranche doit commencer à 0';
      end if;
      if exists (select 1 from jsonb_array_elements(p_lines -> 'brackets') e group by e ->> 'from_amount' having count(*) > 1) then
        raise exception 'Impôt : deux tranches commencent au même montant';
      end if;
      if exists (select 1 from jsonb_array_elements(p_lines -> 'brackets') e where (e ->> 'rate')::numeric < 0 or (e ->> 'rate')::numeric >= 1) then
        raise exception 'Impôt : un taux de tranche doit être compris entre 0 et 1 (exclu)';
      end if;
      if exists (select 1 from jsonb_array_elements(coalesce(p_lines -> 'reductions', '[]'::jsonb)) e group by e ->> 'parts' having count(*) > 1) then
        raise exception 'Impôt : deux réductions familiales ont le même nombre de parts';
      end if;
      if exists (select 1 from jsonb_array_elements(coalesce(p_lines -> 'trimf', '[]'::jsonb)) e group by e ->> 'min_annual_gross' having count(*) > 1) then
        raise exception 'Impôt : deux tranches de TRIMF ont le même seuil';
      end if;
    else
      raise exception 'Barème inconnu : %', p_code;
  end case;
end $$;

-- ------------------------------------------------------------ amorçage
insert into public.scale_catalog (code, label, sort, source_code, legal_text) values
  ('IR',                     'Impôt sur le revenu : barème, réductions familiales, TRIMF', 10, null,
     'Barème du Code général des impôts repris du classeur de paie historique (version 2013). Source légale à fournir et à confirmer.'),
  ('HS',                     'Majorations des heures supplémentaires',                      20, 'CCNI_49',
     'Majorations de 15 %, 40 %, 60 % et 100 % (CCNI art. 49) ; le Code du Travail 2026 (art. 244) renvoie à ces taux. Le minimum légal de chaque majoration est contrôlé.'),
  ('PREAVIS',                'Durées de préavis',                                            30, 'CCNI_74_77',
     'Préavis d''un mois pour les ouvriers et employés, deux pour la maîtrise, trois pour les cadres (CCNI art. 74-77), à confirmer.'),
  ('QUOTITE_PRINCIPAL',      'Quotité cessible : tranches du salaire principal',              40, 'CPC_381',
     'Lecture progressive des tranches du salaire (Code de procédure civile art. 381), à confirmer par le juriste.'),
  ('QUOTITE_SUPPLEMENTAIRE', 'Quotité cessible : tranches des suppléments familiaux',         50, 'CPC_381',
     'Tranches applicables aux éléments de rémunération supplémentaires (Code de procédure civile art. 381), à confirmer.'),
  ('LICENCIEMENT',           'Indemnité de licenciement : taux par tranche d''ancienneté',    60, 'CCNI_80',
     '25 % jusqu''à 5 ans, 30 % de 5 à 10 ans, 40 % au-delà (CCNI art. 80), à confirmer.'),
  ('RETRAITE',               'Indemnité de départ à la retraite : taux par tranche',          70, 'CCNI_84',
     '25 %, 30 %, 45 % puis 50 % selon l''ancienneté (CCNI art. 84), à confirmer.')
on conflict (code) do nothing;

insert into public.scale_defaults (scale_code, lines)
select c.code, public.scale_lines(c.code, current_date) from public.scale_catalog c
on conflict (scale_code) do nothing;

-- ------------------------------------------------------------ lecture
create or replace function public.scale_overview(p_as_of date default current_date)
returns table (
  code text, label text, sort integer, effective_from date, is_modified boolean, nb_versions integer, next_free_date date,
  source_code text, source_label text, source_document text, source_article text, source_status text, legal_text text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['admin', 'rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « admin », « rh » ou « paie » requis';
  end if;
  return query
  select c.code, c.label, c.sort,
         (select max(d) from public.scale_version_dates(c.code) d where d <= p_as_of),
         public.scale_lines(c.code, p_as_of) is distinct from df.lines,
         (select count(*)::integer from public.scale_version_dates(c.code)),
         public.parameters_min_effective_date(),
         c.source_code, ls.label, ls.document, ls.article, ls.status, c.legal_text
    from public.scale_catalog c
    join public.scale_defaults df on df.scale_code = c.code
    left join public.legal_sources ls on ls.code = c.source_code
   order by c.sort;
end $$;

create or replace function public.scale_versions(p_code text)
returns table (effective_from date, locked boolean, nb_lines integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['admin', 'rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « admin », « rh » ou « paie » requis';
  end if;
  return query
  select v.d, public.scale_version_locked(v.d, v.nxt),
         case when jsonb_typeof(public.scale_lines(p_code, v.d)) = 'array'
              then jsonb_array_length(public.scale_lines(p_code, v.d))
              else (select sum(jsonb_array_length(x.value))::integer from jsonb_each(public.scale_lines(p_code, v.d)) x) end
    from (select d, lead(d) over (order by d) as nxt from public.scale_version_dates(p_code) d) v
   order by v.d desc;
end $$;

create or replace function public.scale_get(p_code text, p_on date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['admin', 'rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « admin », « rh » ou « paie » requis';
  end if;
  return public.scale_lines(p_code, p_on);
end $$;

-- ------------------------------------------------------------ écriture
create or replace function public.scale_save(p_code text, p_effective_from date, p_lines jsonb)
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_floor date := public.parameters_min_effective_date();
  v_base jsonb;
  v_name text;
  v_slab uuid;
begin
  if not public.has_role(array['admin']) then
    raise exception 'Droits insuffisants : rôle « admin » requis pour modifier un barème';
  end if;
  if not exists (select 1 from public.scale_catalog where code = p_code) then raise exception 'Barème inconnu : %', p_code; end if;
  if p_effective_from is null then raise exception 'Une date d''effet est obligatoire'; end if;
  if p_effective_from <> date_trunc('month', p_effective_from)::date then
    raise exception 'La date d''effet doit être le premier jour d''un mois (reçu : %)', p_effective_from;
  end if;
  if v_floor is not null and p_effective_from < v_floor then
    raise exception 'Date d''effet % refusée : des paies sont déjà calculées. Première date possible : %', p_effective_from, v_floor;
  end if;
  perform public.scale_validate(p_code, p_lines);

  case p_code
    when 'HS' then
      v_base := public.scale_lines('HS', p_effective_from);
      if v_base = '[]'::jsonb then v_base := public.scale_lines('HS', current_date); end if;
      delete from public.overtime_rates where effective_from = p_effective_from;
      insert into public.overtime_rates (code, label, rate_uplift, hours_from, hours_to, source_code, legal_min_uplift, legal_min_source, effective_from)
      select b.code, b.label, l.rate_uplift, b.hours_from, b.hours_to, b.source_code, b.legal_min_uplift, b.legal_min_source, p_effective_from
        from jsonb_to_recordset(p_lines) as l(code text, rate_uplift numeric)
        join jsonb_to_recordset(v_base) as b(code text, label text, hours_from numeric, hours_to numeric, source_code text, legal_min_uplift numeric, legal_min_source text)
          on b.code = l.code;
    when 'PREAVIS' then
      delete from public.notice_scales where valid_from = p_effective_from;
      insert into public.notice_scales (agreement_code, category, notice_months, free_days_week, source_code, valid_from)
      select l.agreement_code, l.category, l.notice_months, coalesce(l.free_days_week, 0), l.source_code, p_effective_from
        from jsonb_to_recordset(p_lines) as l(agreement_code text, category text, notice_months numeric, free_days_week smallint, source_code text);
    when 'QUOTITE_PRINCIPAL', 'QUOTITE_SUPPLEMENTAIRE' then
      delete from public.garnishment_scale where kind = substr(p_code, 9) and effective_from = p_effective_from;
      insert into public.garnishment_scale (kind, lower_bound, upper_bound, rate, source_code, effective_from)
      select substr(p_code, 9), l.lower_bound, l.upper_bound, l.rate, l.source_code, p_effective_from
        from jsonb_to_recordset(p_lines) as l(lower_bound numeric, upper_bound numeric, rate numeric, source_code text);
    when 'LICENCIEMENT', 'RETRAITE' then
      delete from public.severance_scales where kind = p_code and effective_from = p_effective_from;
      insert into public.severance_scales (kind, year_from, year_to, rate, source_code, effective_from)
      select p_code, l.year_from, l.year_to, l.rate, l.source_code, p_effective_from
        from jsonb_to_recordset(p_lines) as l(year_from smallint, year_to smallint, rate numeric, source_code text);
    when 'IR' then
      select name into v_name from public.tax_slabs where id = public.tax_slab_at(p_effective_from);
      if v_name is null then select name into v_name from public.tax_slabs order by effective_from desc limit 1; end if;
      delete from public.tax_slabs where effective_from = p_effective_from;   -- les lignes enfants suivent (cascade)
      insert into public.tax_slabs (name, effective_from) values (v_name, p_effective_from) returning id into v_slab;
      insert into public.tax_slab_brackets (slab_id, from_amount, rate)
        select v_slab, l.from_amount, l.rate from jsonb_to_recordset(p_lines -> 'brackets') as l(from_amount numeric, rate numeric);
      insert into public.ir_family_reductions (slab_id, parts, rate, min_amount, max_amount)
        select v_slab, l.parts, l.rate, l.min_amount, l.max_amount
          from jsonb_to_recordset(coalesce(p_lines -> 'reductions', '[]'::jsonb)) as l(parts numeric, rate numeric, min_amount numeric, max_amount numeric);
      insert into public.trimf_brackets (slab_id, min_annual_gross, annual_amount, per_part)
        select v_slab, l.min_annual_gross, l.annual_amount, coalesce(l.per_part, false)
          from jsonb_to_recordset(coalesce(p_lines -> 'trimf', '[]'::jsonb)) as l(min_annual_gross numeric, annual_amount numeric, per_part boolean);
  end case;
  return p_effective_from;
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
  return p_effective_from;
end $$;

create or replace function public.set_scale_reference(p_code text, p_legal_text text, p_source_code text default null)
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
  update public.scale_catalog
     set legal_text = nullif(trim(p_legal_text), ''), source_code = p_source_code, updated_at = now()
   where code = p_code;
  if not found then raise exception 'Barème inconnu : %', p_code; end if;
end $$;

revoke all on function public.scale_lines(text, date) from public, anon, authenticated;
revoke all on function public.scale_version_dates(text) from public, anon, authenticated;
revoke all on function public.scale_check_ranges(jsonb, text, text, text) from public, anon, authenticated;
revoke all on function public.scale_validate(text, jsonb) from public, anon, authenticated;
revoke all on function public.scale_overview(date) from public, anon;
revoke all on function public.scale_versions(text) from public, anon;
revoke all on function public.scale_get(text, date) from public, anon;
revoke all on function public.scale_save(text, date, jsonb) from public, anon;
revoke all on function public.scale_reset(text, date) from public, anon;
revoke all on function public.set_scale_reference(text, text, text) from public, anon;
grant execute on function public.scale_overview(date) to authenticated;
grant execute on function public.scale_versions(text) to authenticated;
grant execute on function public.scale_get(text, date) to authenticated;
grant execute on function public.scale_save(text, date, jsonb) to authenticated;
grant execute on function public.scale_reset(text, date) to authenticated;
grant execute on function public.set_scale_reference(text, text, text) to authenticated;

notify pgrst, 'reload schema';
