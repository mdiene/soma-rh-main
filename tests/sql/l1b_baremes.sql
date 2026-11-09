-- L1b : barèmes datés (HS, quotité cessible, indemnités, préavis, impôt), contrôles de continuité, verrou des jeux utilisés, droits, audit.
-- Contient aussi la preuve d'équivalence de severance_coefficient (lecture de la table) avec l'ancienne formule codée en dur.
-- Tout est annulé. Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/l1b_baremes.sql  (attendu : "OK l1b_baremes")
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

-- Ancienne formule (codée en dur) de severance_coefficient, reprise telle quelle de la migration d'origine du moteur.
create or replace function pg_temp.sev_old(p_entry date, p_exit date, p_kind text) returns numeric language plpgsql as $$
declare v_years numeric; y int; m int; d int;
begin
  if p_entry is null or p_exit is null then return 0; end if;
  v_years := (p_exit - p_entry)::numeric / 365;
  y := public.excel_datedif(p_entry, p_exit + 1, 'y');
  m := public.excel_datedif(p_entry, p_exit + 1, 'ym');
  d := public.excel_datedif(p_entry, p_exit + 1, 'md');
  if p_kind = 'LICENCIEMENT' then
    if v_years > 10 then return 0.25*5 + 0.30*5 + 0.40*(y-10) + 0.40*m/12.0 + 0.40*d/360.0;
    elsif v_years > 5 then return 0.25*5 + 0.30*(y-5) + 0.30*m/12.0 + 0.30*d/360.0;
    elsif v_years >= 0 then return 0.25*y + 0.25*m/12.0 + 0.25*d/360.0; end if;
  elsif p_kind = 'RETRAITE' then
    if v_years > 20 then return 0.25*5 + 0.30*5 + 0.45*10 + 0.50*(y-20) + 0.50*m/12.0 + 0.50*d/360.0;
    elsif v_years > 10 then return 0.25*5 + 0.30*5 + 0.45*(y-10) + 0.45*m/12.0 + 0.45*d/360.0;
    elsif v_years > 5 then return 0.25*5 + 0.30*(y-5) + 0.30*m/12.0 + 0.30*d/360.0;
    elsif v_years >= 0 then return 0.25*y + 0.25*m/12.0 + 0.25*d/360.0; end if;
  end if;
  return 0;
end $$;

do $$
declare
  c record; r text; v_locked date; v_floor date; v_n int; v_bad int;
  v_hs jsonb; v_q jsonb; v_ir jsonb; v_pv jsonb; v_a numeric; v_b numeric;
begin
  select * into c from t_ctx;
  if c.user_admin is null or c.user_rh is null or c.user_sal is null then raise exception 'FAIL : comptes admin / rh / salarié introuvables'; end if;
  v_locked := public.payroll_locked_until();
  v_floor := coalesce(public.parameters_min_effective_date(), date_trunc('month', current_date)::date);

  -- 1. équivalence de severance_coefficient avec l'ancienne formule (grille de dates, trois natures dont une inconnue)
  select count(*), count(*) filter (where pg_temp.sev_old(g.e, g.x, g.k) is distinct from public.severance_coefficient(g.e, g.x, g.k))
    into v_n, v_bad
    from (
      select kk.k, ee::date as e, xs.x
        from (values ('LICENCIEMENT'), ('RETRAITE'), ('AUTRE')) kk(k)
        cross join generate_series(date '1995-03-17', date '2020-06-30', interval '151 days') ee
        cross join (select (date '2021-01-01' + (n * 53) * interval '1 day')::date as x from generate_series(0, 300) n
                    union select date '2019-02-28' union select date '2021-01-01') xs
       where xs.x > ee::date
    ) g;
  if v_n < 1000 then raise exception 'FAIL : grille d''équivalence trop petite (%)', v_n; end if;
  if v_bad > 0 then raise exception 'FAIL : % écart(s) entre severance_coefficient et l''ancienne formule sur % cas', v_bad, v_n; end if;

  -- 2. vue d'ensemble : sept barèmes, aucun modifié au départ, lisible par rh, pas par un salarié
  perform pg_temp.as_user(c.user_rh);
  if (select count(*) from public.scale_overview()) <> 7 then raise exception 'FAIL : 7 barèmes attendus'; end if;
  if exists (select 1 from public.scale_overview() where is_modified) then raise exception 'FAIL : un barème apparaît modifié avant toute saisie'; end if;
  perform pg_temp.as_user(c.user_sal);
  r := pg_temp.try('select * from public.scale_overview()');
  if r not like '%Droits insuffisants%' then raise exception 'FAIL : le salarié lit les barèmes : %', r; end if;
  perform pg_temp.as_user(c.user_rh);
  r := pg_temp.try(format('select public.scale_save(''HS'', %L, public.scale_get(''HS''))', v_floor));
  if r not like '%Droits insuffisants%' then raise exception 'FAIL : rh a modifié un barème : %', r; end if;

  -- 3. heures supplémentaires : nouvelle version datée, ancienne intacte, minimum légal et codes contrôlés
  perform pg_temp.as_user(c.user_admin);
  v_hs := public.scale_get('HS');
  v_a := public.hs_majoration('HS_NUIT', 9, v_floor - 1);
  perform public.scale_save('HS', v_floor, (select jsonb_agg(case when e ->> 'code' = 'HS_NUIT' then e || '{"rate_uplift": 0.70}' else e end) from jsonb_array_elements(v_hs) e));
  execute 'reset role';
  if public.hs_majoration('HS_NUIT', 9, v_floor) <> 1.70 then raise exception 'FAIL : HS_NUIT non appliquée à la date d''effet (%)', public.hs_majoration('HS_NUIT', 9, v_floor); end if;
  if public.hs_majoration('HS_NUIT', 9, v_floor - 1) <> v_a then raise exception 'FAIL : HS_NUIT avant la date d''effet a changé'; end if;
  if public.hs_majoration('HS_JOUR_8_PREMIERES', 9, v_floor) <> 1.15 then raise exception 'FAIL : une majoration non modifiée a changé'; end if;
  perform pg_temp.as_user(c.user_admin);
  r := pg_temp.try(format('select public.scale_save(''HS'', %L, (select jsonb_agg(case when e ->> ''code'' = ''HS_NUIT'' then e || ''{"rate_uplift": 0.10}'' else e end) from jsonb_array_elements(public.scale_get(''HS'')) e))', (v_floor + interval '1 month')::date));
  if r not like '%minimum légal%' then raise exception 'FAIL : majoration sous le minimum légal acceptée : %', r; end if;
  r := pg_temp.try(format('select public.scale_save(''HS'', %L, (select jsonb_agg(e) from jsonb_array_elements(public.scale_get(''HS'')) e where e ->> ''code'' <> ''HS_NUIT''))', (v_floor + interval '1 month')::date));
  if r not like '%codes de majoration%' then raise exception 'FAIL : retrait d''un code accepté : %', r; end if;

  -- 4. quotité cessible : continuité des tranches, nouvelle version, ancienne intacte
  r := pg_temp.try(format('select public.scale_save(''QUOTITE_PRINCIPAL'', %L, ''[{"lower_bound":0,"upper_bound":50000,"rate":0.1},{"lower_bound":60000,"upper_bound":null,"rate":0.2}]'')', v_floor));
  if r not like '%ne suit pas la précédente%' then raise exception 'FAIL : trou entre tranches accepté : %', r; end if;
  r := pg_temp.try(format('select public.scale_save(''QUOTITE_PRINCIPAL'', %L, ''[{"lower_bound":10,"upper_bound":null,"rate":0.1}]'')', v_floor));
  if r not like '%commencer à 0%' then raise exception 'FAIL : première tranche non nulle acceptée : %', r; end if;
  r := pg_temp.try(format('select public.scale_save(''QUOTITE_PRINCIPAL'', %L, ''[{"lower_bound":0,"upper_bound":50000,"rate":0.1}]'')', v_floor));
  if r not like '%sans borne haute%' then raise exception 'FAIL : dernière tranche bornée acceptée : %', r; end if;
  execute 'reset role';
  v_a := public.quotite_cessible_at(400000, 'PRINCIPAL', v_floor);
  perform pg_temp.as_user(c.user_admin);
  perform public.scale_save('QUOTITE_PRINCIPAL', v_floor, '[{"lower_bound":0,"upper_bound":null,"rate":0.5}]'::jsonb);
  execute 'reset role';
  if public.quotite_cessible_at(400000, 'PRINCIPAL', v_floor) <> 200000 then raise exception 'FAIL : nouvelle quotité non appliquée (%)', public.quotite_cessible_at(400000, 'PRINCIPAL', v_floor); end if;
  if public.quotite_cessible_at(400000, 'PRINCIPAL', v_floor - 1) <> v_a then raise exception 'FAIL : quotité avant la date d''effet modifiée'; end if;

  -- 5. indemnité de licenciement : version datée lue par severance_coefficient à la date de sortie
  perform pg_temp.as_user(c.user_admin);
  perform public.scale_save('LICENCIEMENT', v_floor, '[{"year_from":0,"year_to":null,"rate":0.5}]'::jsonb);
  execute 'reset role';
  v_a := public.severance_coefficient(date '2015-01-01', v_floor - 1, 'LICENCIEMENT');
  v_b := public.severance_coefficient(date '2015-01-01', v_floor + 30, 'LICENCIEMENT');
  if v_a <> pg_temp.sev_old(date '2015-01-01', v_floor - 1, 'LICENCIEMENT') then raise exception 'FAIL : sortie avant la date d''effet modifiée'; end if;
  if v_b <= v_a then raise exception 'FAIL : nouveau taux de licenciement non appliqué (% <= %)', v_b, v_a; end if;

  -- 6. préavis
  perform pg_temp.as_user(c.user_admin);
  v_pv := public.scale_get('PREAVIS');
  perform public.scale_save('PREAVIS', v_floor, (select jsonb_agg(case when e ->> 'category' = 'CADRE' then e || '{"notice_months": 4}' else e end) from jsonb_array_elements(v_pv) e));
  if (select (e ->> 'notice_months')::numeric from jsonb_array_elements(public.scale_get('PREAVIS', v_floor)) e where e ->> 'category' = 'CADRE') <> 4 then raise exception 'FAIL : préavis cadre non enregistré'; end if;
  if (select (e ->> 'notice_months')::numeric from jsonb_array_elements(public.scale_get('PREAVIS', v_floor - 1)) e where e ->> 'category' = 'CADRE') = 4 then raise exception 'FAIL : préavis modifié avant la date d''effet'; end if;
  r := pg_temp.try(format('select public.scale_save(''PREAVIS'', %L, ''[{"agreement_code":null,"category":"INCONNU","notice_months":1}]'')', (v_floor + interval '1 month')::date));
  if r not like '%catégorie invalide%' then raise exception 'FAIL : catégorie invalide acceptée : %', r; end if;

  -- 7. impôt : nouveau barème daté (tranches, réductions, TRIMF), ancien intact, erreurs de saisie refusées
  v_ir := public.scale_get('IR');
  perform public.scale_save('IR', v_floor, v_ir);
  execute 'reset role';
  if public.tax_slab_at(v_floor) = public.tax_slab_at(v_floor - 1) then raise exception 'FAIL : le barème d''impôt n''a pas de nouvelle version'; end if;
  perform pg_temp.as_user(c.user_admin);
  if public.scale_get('IR', v_floor) is distinct from public.scale_get('IR', v_floor - 1) then raise exception 'FAIL : la copie du barème d''impôt diffère de l''original'; end if;
  r := pg_temp.try(format('select public.scale_save(''IR'', %L, ''{"brackets":[{"from_amount":5,"rate":0.1}],"reductions":[],"trimf":[]}'')', (v_floor + interval '1 month')::date));
  if r not like '%commencer à 0%' then raise exception 'FAIL : barème d''impôt sans tranche à 0 accepté : %', r; end if;
  r := pg_temp.try(format('select public.scale_save(''IR'', %L, ''{"brackets":[{"from_amount":0,"rate":1.2}],"reductions":[],"trimf":[]}'')', (v_floor + interval '1 month')::date));
  if r not like '%taux de tranche%' then raise exception 'FAIL : taux d''impôt > 1 accepté : %', r; end if;

  -- 8. versions : les nouvelles sont libres, l'origine est verrouillée si des paies en dépendent
  if (select count(*) from public.scale_versions('HS')) < 2 then raise exception 'FAIL : scale_versions ne montre pas la nouvelle version'; end if;
  if v_locked is not null and not (select locked from public.scale_versions('HS') where effective_from = date '2000-01-01') then
    raise exception 'FAIL : la version d''origine devrait être verrouillée';
  end if;
  if (select locked from public.scale_versions('HS') where effective_from = v_floor) then raise exception 'FAIL : la nouvelle version ne devrait pas être verrouillée'; end if;

  -- 9. réinitialisation : revient au jeu d'origine ; is_modified retombe
  perform public.scale_reset('HS', v_floor);
  if (select is_modified from public.scale_overview(v_floor) where code = 'HS') then raise exception 'FAIL : HS toujours modifié après réinitialisation'; end if;
  execute 'reset role';
  if public.hs_majoration('HS_NUIT', 9, v_floor) <> 1.60 then raise exception 'FAIL : HS_NUIT non rétablie (%)', public.hs_majoration('HS_NUIT', 9, v_floor); end if;

  -- 10. garde : un jeu utilisé par une paie calculée est immuable (modification directe refusée) ; pas de jeu daté dans le passé
  if v_locked is not null then
    r := pg_temp.try('update public.overtime_rates set rate_uplift = rate_uplift + 0.01 where effective_from = date ''2000-01-01''');
    if r not like '%sert à des paies déjà calculées%' then raise exception 'FAIL : barème HS verrouillé modifiable : %', r; end if;
    r := pg_temp.try('update public.tax_slab_brackets set rate = rate where slab_id = public.tax_slab_at(' || quote_literal(v_locked) || ')');
    if r not like '%sert à des paies déjà calculées%' then raise exception 'FAIL : barème d''impôt verrouillé modifiable : %', r; end if;
    r := pg_temp.try('delete from public.severance_scales where effective_from = date ''2000-01-01''');
    if r not like '%sert à des paies déjà calculées%' then raise exception 'FAIL : indemnités verrouillées supprimables : %', r; end if;
    perform pg_temp.as_user(c.user_admin);
    r := pg_temp.try(format('select public.scale_save(''HS'', %L, public.scale_get(''HS''))', (v_floor - interval '1 month')::date));
    if r not like '%paies sont déjà calculées%' then raise exception 'FAIL : barème daté dans le passé accepté : %', r; end if;
  end if;

  -- 11. références et audit
  perform pg_temp.as_user(c.user_admin);
  perform public.set_scale_reference('HS', 'Texte de test', 'CCNI_49');
  r := pg_temp.try('select public.set_scale_reference(''HS'', ''x'', ''N_EXISTE_PAS'')');
  if r not like '%Source légale inconnue%' then raise exception 'FAIL : source inconnue acceptée : %', r; end if;
  execute 'reset role';
  if not exists (select 1 from public.audit_log where table_name = 'overtime_rates') then raise exception 'FAIL : modifications des majorations HS non tracées'; end if;
  if not exists (select 1 from public.audit_log where table_name = 'scale_catalog' and record_key = 'HS') then raise exception 'FAIL : modification du catalogue non tracée'; end if;
  raise notice 'OK l1b_baremes (% cas d''équivalence)', v_n;
end $$;
rollback;
