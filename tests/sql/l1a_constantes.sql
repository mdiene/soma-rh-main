-- L1a : catalogue des constantes, modification versionnée, remise à la valeur d'origine, verrou des paies calculées.
-- Tout est annulé. Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/l1a_constantes.sql  (attendu : "OK l1a_constantes")
begin;
create temp table t_ctx as
select
  (select user_id from public.user_roles where role = 'admin' order by user_id limit 1) as user_admin,
  (select user_id from public.user_roles where role = 'rh' and user_id not in (select user_id from public.user_roles where role = 'admin') order by user_id limit 1) as user_rh,
  (select user_id from public.user_roles group by user_id having bool_and(role = 'salarie') order by user_id limit 1) as user_sal;
grant select on t_ctx to authenticated;
create or replace function pg_temp.as_user(p_user uuid) returns void language plpgsql as $$
begin
  execute 'reset role'; execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;
create or replace function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'OK'; exception when others then return sqlerrm; end $$;
do $$
declare
  c record; r text; v_floor date; v_eff date; v_before numeric; v_after numeric; v_n int; v_def numeric; v_locked date;
begin
  select * into c from t_ctx;
  if c.user_admin is null or c.user_rh is null or c.user_sal is null then raise exception 'FAIL : comptes admin / rh / salarié introuvables'; end if;
  v_locked := public.payroll_locked_until();
  v_floor := coalesce(public.parameters_min_effective_date(), date_trunc('month', current_date)::date);

  -- 1. catalogue : valeurs courantes et valeurs d'origine renseignées ; illisible pour un salarié
  perform pg_temp.as_user(c.user_rh);
  select count(*) into v_n from public.parameter_overview(current_date);
  if v_n < 25 then raise exception 'FAIL : catalogue trop court (% lignes)', v_n; end if;
  if exists (select 1 from public.parameter_overview(current_date) where current_value is null or default_value is null) then
    raise exception 'FAIL : valeur courante ou valeur d''origine manquante';
  end if;
  perform pg_temp.as_user(c.user_sal);
  r := pg_temp.try('select * from public.parameter_overview(current_date)');
  if r not like '%Droits insuffisants%' then raise exception 'FAIL : le salarié lit le catalogue : %', r; end if;

  -- 2. rh ne modifie pas une constante (circuit de validation en L2b)
  perform pg_temp.as_user(c.user_rh);
  r := pg_temp.try('select public.set_parameter(''css_ceiling'', 70000)');
  if r not like '%Droits insuffisants%' then raise exception 'FAIL : rh a modifié une constante : %', r; end if;
  r := pg_temp.try('select public.reset_parameter(''css_ceiling'')');
  if r not like '%Droits insuffisants%' then raise exception 'FAIL : rh a réinitialisé une constante : %', r; end if;

  -- 3. admin : nouvelle version datée, ancienne valeur intacte
  execute 'reset role';
  v_before := (select css_ceiling from public.payroll_settings_at(v_floor - 1));
  perform pg_temp.as_user(c.user_admin);
  v_eff := public.set_parameter('css_ceiling', 71000, v_floor);
  if v_eff <> v_floor then raise exception 'FAIL : date d''effet % au lieu de %', v_eff, v_floor; end if;
  execute 'reset role';
  v_after := (select css_ceiling from public.payroll_settings_at(v_floor));
  if v_after <> 71000 then raise exception 'FAIL : nouvelle valeur non appliquée (%)', v_after; end if;
  if (select css_ceiling from public.payroll_settings_at(v_floor - 1)) is distinct from v_before then
    raise exception 'FAIL : la période précédente a changé';
  end if;
  perform pg_temp.as_user(c.user_admin);
  if (select current_value from public.parameter_overview(v_floor) where code = 'css_ceiling') <> 71000 then raise exception 'FAIL : parameter_overview ne montre pas la nouvelle valeur'; end if;
  if not (select is_modified from public.parameter_overview(v_floor) where code = 'css_ceiling') then raise exception 'FAIL : is_modified faux'; end if;

  -- 4. refus : date dans une période calculée, jour non premier du mois, hors bornes, entier, code inconnu
  if v_locked is not null then
    r := pg_temp.try(format('select public.set_parameter(''css_ceiling'', 72000, %L)', (v_floor - interval '1 month')::date));
    if r not like '%paies sont déjà calculées%' then raise exception 'FAIL : date dans le passé acceptée : %', r; end if;
  end if;
  r := pg_temp.try(format('select public.set_parameter(''css_ceiling'', 72000, %L)', v_floor + 14));
  if r not like '%premier jour%' then raise exception 'FAIL : date en cours de mois acceptée : %', r; end if;
  r := pg_temp.try('select public.set_parameter(''css_af_rate'', 1.5)');
  if r not like '%maximum autorisé%' then raise exception 'FAIL : taux > 1 accepté : %', r; end if;
  r := pg_temp.try('select public.set_parameter(''seniority_min_years'', 2.5)');
  if r not like '%nombre entier%' then raise exception 'FAIL : entier non contrôlé : %', r; end if;
  r := pg_temp.try('select public.set_parameter(''inconnue'', 1)');
  if r not like '%inconnue%' then raise exception 'FAIL : code inconnu accepté : %', r; end if;

  -- 5. réinitialisation : revient à la valeur d'origine, y compris sur les versions futures
  execute 'reset role';
  insert into public.payroll_settings select (jsonb_populate_record(s, jsonb_build_object(
      'id', gen_random_uuid(), 'effective_from', (v_floor + interval '1 month')::date, 'css_ceiling', 99000))).*
    from public.payroll_settings_at(v_floor) s;
  perform pg_temp.as_user(c.user_admin);
  select default_value into v_def from public.parameter_catalog where code = 'css_ceiling';
  perform public.reset_parameter('css_ceiling', v_floor);
  execute 'reset role';
  if exists (select 1 from public.payroll_settings where effective_from >= v_floor and css_ceiling <> v_def) then
    raise exception 'FAIL : réinitialisation incomplète (valeur d''origine %)', v_def;
  end if;

  -- 6. plafond de prêt (app_parameters)
  perform pg_temp.as_user(c.user_admin);
  perform public.set_parameter('loan_max_rate', 0.4);
  if public.get_loan_max_rate() <> 0.4 then raise exception 'FAIL : plafond de prêt non modifié'; end if;
  perform public.reset_parameter('loan_max_rate');
  if public.get_loan_max_rate() <> 0.33 then raise exception 'FAIL : plafond de prêt non réinitialisé'; end if;

  -- 7. garde : une version utilisée par une paie calculée est immuable
  execute 'reset role';
  if v_locked is not null then
    r := pg_temp.try('update public.payroll_settings set css_ceiling = css_ceiling + 1 where effective_from = (select max(effective_from) from public.payroll_settings where effective_from <= ' || quote_literal(v_locked) || ')');
    if r not like '%servent à des paies déjà calculées%' then raise exception 'FAIL : version verrouillée modifiable : %', r; end if;
    r := pg_temp.try(format('insert into public.payroll_settings select (jsonb_populate_record(s, jsonb_build_object(''id'', gen_random_uuid(), ''effective_from'', %L))).* from public.payroll_settings_at(%L) s', v_locked, v_locked));
    if r not like '%Date d''effet%refusée%' then raise exception 'FAIL : insertion dans le passé verrouillé acceptée : %', r; end if;
  end if;

  -- 8. références : admin règle texte et source ; source inconnue refusée ; trace d'audit
  perform pg_temp.as_user(c.user_admin);
  perform public.set_parameter_reference('css_ceiling', 'Texte de test', 'CT26_216');
  if (select legal_text from public.parameter_catalog where code = 'css_ceiling') <> 'Texte de test' then raise exception 'FAIL : texte non enregistré'; end if;
  r := pg_temp.try('select public.set_parameter_reference(''css_ceiling'', ''x'', ''N_EXISTE_PAS'')');
  if r not like '%Source légale inconnue%' then raise exception 'FAIL : source inconnue acceptée : %', r; end if;
  execute 'reset role';
  if not exists (select 1 from public.audit_log where table_name = 'parameter_catalog' and record_key = 'css_ceiling') then
    raise exception 'FAIL : modification du catalogue non tracée dans audit_log';
  end if;
  raise notice 'OK l1a_constantes';
end $$;
rollback;
