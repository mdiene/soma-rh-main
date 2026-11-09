-- L2 : scan de conformité (vert / orange / rouge), dérogations durables (octroi, remplacement, révocation, levée), règles CDD-DUREE et PARAM-DEFAUT.
-- Les mesures sont des écarts avant / après : le test ne dépend pas des écarts déjà présents dans la base. Tout est annulé.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/l2_scan_derogations.sql  (attendu : "OK l2_scan_derogations")
begin;
create temp table t_ctx as
select
  (select user_id from public.user_roles where role = 'admin' order by user_id limit 1) as user_admin,
  (select user_id from public.user_roles where role = 'rh' and user_id not in (select user_id from public.user_roles where role = 'admin') order by user_id limit 1) as user_rh,
  (select user_id from public.user_roles group by user_id having bool_and(role = 'salarie') order by user_id limit 1) as user_sal,
  (select id from public.employees where status = 'Active' and employment_type = 'CDI' order by employee_number limit 1) as emp;
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
  c record; r text; s1 public.compliance_scans; s2 public.compliance_scans; s3 public.compliance_scans;
  w1 uuid; w2 uuid; n int;
begin
  select * into c from t_ctx;
  if c.user_admin is null or c.user_rh is null or c.user_sal is null or c.emp is null then raise exception 'FAIL : jeu de données insuffisant (admin, rh, salarié, employé actif en CDI)'; end if;

  -- 1. droits : le salarié ne scanne pas ; rh scanne mais ne déroge pas ; admin déroge
  perform pg_temp.as_user(c.user_sal);
  r := pg_temp.try('select * from public.run_compliance_scan()');
  if r not like '%Droits insuffisants%' then raise exception 'FAIL : le salarié lance un scan : %', r; end if;
  r := pg_temp.try('select * from public.compliance_open_findings()');
  if r not like '%Droits insuffisants%' then raise exception 'FAIL : le salarié lit les écarts : %', r; end if;
  perform pg_temp.as_user(c.user_rh);
  r := pg_temp.try(format('select public.grant_waiver(''TEST-REGLE'', %L, ''motif'')', c.emp));
  if r not like '%Droits insuffisants%' then raise exception 'FAIL : rh accorde une dérogation : %', r; end if;

  -- 2. cycle de vie d'une dérogation sur un écart de test (règle non gérée par la détection : elle n'est pas résolue automatiquement)
  execute 'reset role';
  insert into public.compliance_findings (rule_id, severity, entity, entity_id, employee_id, message)
  values ('TEST-REGLE', 'B', 'employee', c.emp, c.emp, 'écart de test');
  perform pg_temp.as_user(c.user_rh);
  s1 := public.run_compliance_scan();
  if s1.nb_bloquants < 1 or s1.status <> 'rouge' then raise exception 'FAIL : état attendu rouge, reçu % (% bloquants)', s1.status, s1.nb_bloquants; end if;
  if coalesce((s1.summary ->> 'TEST-REGLE')::int, 0) <> 1 then raise exception 'FAIL : le résumé du scan ignore l''écart de test'; end if;
  if (select status from public.compliance_status()) <> s1.status then raise exception 'FAIL : compliance_status ne renvoie pas le dernier scan'; end if;

  perform pg_temp.as_user(c.user_admin);
  r := pg_temp.try(format('select public.grant_waiver(''TEST-REGLE'', %L, ''   '')', c.emp));
  if r not like '%motif écrit%' then raise exception 'FAIL : dérogation sans motif acceptée : %', r; end if;
  r := pg_temp.try(format('select public.grant_waiver(''TEST-REGLE'', %L, ''motif'')', gen_random_uuid()));
  if r not like '%Aucun écart ouvert%' then raise exception 'FAIL : dérogation sur un écart inexistant acceptée : %', r; end if;
  w1 := public.grant_waiver('TEST-REGLE', c.emp, 'Accord d''entreprise validé');
  s2 := public.run_compliance_scan();
  if s2.nb_bloquants <> s1.nb_bloquants - 1 or s2.nb_derogations <> s1.nb_derogations + 1 then
    raise exception 'FAIL : la dérogation ne retire pas l''écart du décompte (% -> %, dérogations % -> %)', s1.nb_bloquants, s2.nb_bloquants, s1.nb_derogations, s2.nb_derogations;
  end if;
  if not (select o.waived from public.compliance_open_findings() o where o.rule_id = 'TEST-REGLE') then raise exception 'FAIL : l''écart n''apparaît pas comme dérogé'; end if;

  -- nouvelle dérogation sur le même écart : l'ancienne est remplacée, une seule reste active
  w2 := public.grant_waiver('TEST-REGLE', c.emp, 'Avenant signé');
  if (select status from public.compliance_waivers where id = w1) <> 'remplacée' then raise exception 'FAIL : l''ancienne dérogation n''est pas remplacée'; end if;
  if (select count(*) from public.compliance_waivers where rule_id = 'TEST-REGLE' and entity_id = c.emp and status = 'active') <> 1 then raise exception 'FAIL : plusieurs dérogations actives'; end if;

  -- révocation : l'écart redevient compté
  r := pg_temp.try(format('select public.revoke_waiver(%L, '' '')', w2));
  if r not like '%motif est obligatoire%' then raise exception 'FAIL : révocation sans motif acceptée : %', r; end if;
  perform public.revoke_waiver(w2, 'Accord expiré');
  s3 := public.run_compliance_scan();
  if s3.nb_bloquants <> s1.nb_bloquants then raise exception 'FAIL : l''écart révoqué n''est pas recompté'; end if;
  if (select status from public.compliance_waivers where id = w2) <> 'révoquée' then raise exception 'FAIL : statut révoquée absent'; end if;

  -- 3. règle CDD-DUREE : durée maximale paramétrable
  execute 'reset role';
  update public.employees set employment_type = 'CDD', contract_start = date '2020-01-01', contract_end = date '2024-06-01' where id = c.emp;
  perform pg_temp.as_user(c.user_admin);
  perform public.run_compliance_scan();
  if not exists (select 1 from public.compliance_open_findings() o where o.rule_id = 'CDD-DUREE' and o.employee_id = c.emp and o.severity = 'B') then
    raise exception 'FAIL : CDD de 53 mois non signalé (limite 24 mois)';
  end if;

  -- 4. règle PARAM-DEFAUT et levée des dérogations à la réinitialisation
  perform public.set_parameter('cdd_max_months', 120);
  perform public.run_compliance_scan();
  if exists (select 1 from public.compliance_open_findings() o where o.rule_id = 'CDD-DUREE' and o.employee_id = c.emp) then
    raise exception 'FAIL : CDD toujours signalé avec une limite de 120 mois';
  end if;
  if not exists (select 1 from public.compliance_open_findings() o where o.rule_id = 'PARAM-DEFAUT' and o.message like '%durée déterminée%') then
    raise exception 'FAIL : constante modifiée sans source confirmée non signalée';
  end if;
  w1 := public.grant_waiver('PARAM-DEFAUT', (select o.entity_id from public.compliance_open_findings() o where o.rule_id = 'PARAM-DEFAUT' and o.message like '%durée déterminée%'),
                            'Tolérance en attendant la revue juridique', 'cdd_max_months');
  if (select parameter_value from public.compliance_waivers where id = w1) <> 120 then raise exception 'FAIL : valeur de la constante non mémorisée dans la dérogation'; end if;
  perform public.reset_parameter('cdd_max_months');
  if (select status from public.compliance_waivers where id = w1) <> 'levée' then raise exception 'FAIL : dérogation liée non levée à la réinitialisation'; end if;
  perform public.run_compliance_scan();
  if not exists (select 1 from public.compliance_open_findings() o where o.rule_id = 'CDD-DUREE' and o.employee_id = c.emp) then
    raise exception 'FAIL : CDD de nouveau hors limite non signalé après réinitialisation';
  end if;
  if exists (select 1 from public.compliance_open_findings() o where o.rule_id = 'PARAM-DEFAUT' and o.message like '%durée déterminée%') then
    raise exception 'FAIL : écart de constante toujours ouvert après réinitialisation';
  end if;

  -- 5. règles décrites pour l'affichage et traçabilité
  select count(*) into n from public.compliance_open_findings() o where o.suggested_action is null or o.rule_label is null;
  if n > 0 then raise exception 'FAIL : % écart(s) sans libellé ou action recommandée', n; end if;
  execute 'reset role';
  if not exists (select 1 from public.audit_log where table_name = 'compliance_waivers') then raise exception 'FAIL : dérogations non tracées dans audit_log'; end if;
  raise notice 'OK l2_scan_derogations';
end $$;
rollback;
