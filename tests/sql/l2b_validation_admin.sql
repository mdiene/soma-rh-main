-- L2b : le RH saisit, l'administrateur valide (dérogations, constantes, barèmes). Tout est annulé.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/l2b_validation_admin.sql  (attendu : "OK l2b_validation_admin")
begin;
create temp table t_ctx as
select
  (select user_id from public.user_roles where role = 'admin' order by user_id limit 1) as user_admin,
  (select user_id from public.user_roles where role = 'rh' and user_id not in (select user_id from public.user_roles where role = 'admin') order by user_id limit 1) as user_rh,
  (select user_id from public.user_roles group by user_id having bool_and(role = 'salarie') order by user_id limit 1) as user_sal,
  (select id from public.employees where status = 'Active' order by employee_number limit 1) as emp;
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
  c record; r text; q1 uuid; q2 uuid; q3 uuid; n0 int; v_floor date; w public.compliance_waivers; v_hs jsonb;
begin
  select * into c from t_ctx;
  if c.user_admin is null or c.user_rh is null or c.user_sal is null or c.emp is null then raise exception 'FAIL : jeu de données insuffisant'; end if;
  v_floor := coalesce(public.parameters_min_effective_date(), date_trunc('month', current_date)::date);

  -- 1. droits : le salarié ne demande rien ; rh ne décide pas
  perform pg_temp.as_user(c.user_sal);
  r := pg_temp.try('select public.request_parameter_change(''loan_max_rate'', 0.4)');
  if r not like '%Droits insuffisants%' then raise exception 'FAIL : le salarié dépose une demande : %', r; end if;

  -- 2. une demande du rh n'a aucun effet tant qu'elle n'est pas approuvée
  perform pg_temp.as_user(c.user_rh);
  q1 := public.request_parameter_change('loan_max_rate', 0.4);
  if public.get_loan_max_rate() <> 0.33 then raise exception 'FAIL : la demande a modifié la constante avant validation'; end if;
  if (select status from public.approval_requests where id = q1) <> 'en_attente' then raise exception 'FAIL : demande non en attente'; end if;
  r := pg_temp.try('select public.request_parameter_change(''loan_max_rate'', 0.5)');
  if r not like '%déjà en attente%' then raise exception 'FAIL : seconde demande identique acceptée : %', r; end if;
  r := pg_temp.try('select public.request_parameter_change(''css_af_rate'', 1.5)');
  if r not like '%maximum autorisé%' then raise exception 'FAIL : valeur hors bornes acceptée dès la demande : %', r; end if;
  r := pg_temp.try(format('select public.decide_request(%L, true)', q1));
  if r not like '%Droits insuffisants%' then raise exception 'FAIL : rh décide de sa propre demande : %', r; end if;
  if public.approval_pending_count() <> 1 then raise exception 'FAIL : compteur du demandeur (attendu 1)'; end if;
  if exists (select 1 from public.approval_requests_overview() o where o.requested_by <> c.user_rh) then raise exception 'FAIL : rh voit les demandes d''autrui'; end if;

  -- 3. refus : motif obligatoire, aucune application, notification du demandeur
  perform pg_temp.as_user(c.user_admin);
  if public.approval_pending_count() < 1 then raise exception 'FAIL : compteur de l''administrateur'; end if;
  r := pg_temp.try(format('select public.decide_request(%L, false, '' '')', q1));
  if r not like '%motif est obligatoire%' then raise exception 'FAIL : refus sans motif accepté : %', r; end if;
  execute 'reset role';   -- les notifications sont protégées par ligne : on les compte en superutilisateur
  select count(*) into n0 from public.employee_notifications where user_id = c.user_rh and title = 'Demande refusée';
  perform pg_temp.as_user(c.user_admin);
  perform public.decide_request(q1, false, 'Valeur non justifiée');
  if public.get_loan_max_rate() <> 0.33 then raise exception 'FAIL : une demande refusée a été appliquée'; end if;
  execute 'reset role';
  if (select count(*) from public.employee_notifications where user_id = c.user_rh and title = 'Demande refusée') <> n0 + 1 then raise exception 'FAIL : demandeur non notifié du refus'; end if;
  perform pg_temp.as_user(c.user_admin);
  r := pg_temp.try(format('select public.decide_request(%L, true)', q1));
  if r not like '%déjà été traitée%' then raise exception 'FAIL : demande refusée ré-approuvable : %', r; end if;

  -- 4. approbation : la constante change, auteur et décideur tracés
  perform pg_temp.as_user(c.user_rh);
  q2 := public.request_parameter_change('loan_max_rate', 0.4);
  perform pg_temp.as_user(c.user_admin);
  perform public.decide_request(q2, true, 'OK');
  if public.get_loan_max_rate() <> 0.4 then raise exception 'FAIL : demande approuvée non appliquée'; end if;
  if (select requested_by from public.approval_requests where id = q2) <> c.user_rh or (select decided_by from public.approval_requests where id = q2) <> c.user_admin then
    raise exception 'FAIL : demandeur ou décideur non tracés';
  end if;

  -- 5. dérogation demandée par le rh, accordée par l'administrateur
  execute 'reset role';
  insert into public.compliance_findings (rule_id, severity, entity, entity_id, employee_id, message)
  values ('TEST-REGLE', 'B', 'employee', c.emp, c.emp, 'écart de test');
  perform pg_temp.as_user(c.user_rh);
  q1 := public.request_waiver('TEST-REGLE', c.emp, 'Accord signé');
  if exists (select 1 from public.compliance_waivers where rule_id = 'TEST-REGLE' and status = 'active') then raise exception 'FAIL : dérogation active avant validation'; end if;
  r := pg_temp.try(format('select public.request_waiver(''TEST-REGLE'', %L, '' '')', c.emp));
  if r not like '%motif écrit%' then raise exception 'FAIL : demande de dérogation sans motif acceptée : %', r; end if;
  perform pg_temp.as_user(c.user_admin);
  perform public.decide_request(q1, true);
  select * into w from public.compliance_waivers where rule_id = 'TEST-REGLE' and status = 'active';
  if not found then raise exception 'FAIL : dérogation non créée à l''approbation'; end if;
  if w.requested_by <> c.user_rh or w.granted_by <> c.user_admin then raise exception 'FAIL : demandeur / accordeur de la dérogation non tracés'; end if;

  -- 6. approbation impossible (écart résolu entre-temps) : l'erreur est remontée et la demande reste en attente
  execute 'reset role';
  insert into public.compliance_findings (rule_id, severity, entity, entity_id, employee_id, message)
  values ('TEST-REGLE2', 'A', 'employee', c.emp, c.emp, 'second écart de test');
  perform pg_temp.as_user(c.user_rh);
  q3 := public.request_waiver('TEST-REGLE2', c.emp, 'Motif');
  execute 'reset role';
  update public.compliance_findings set resolved_on = current_date where rule_id = 'TEST-REGLE2';
  perform pg_temp.as_user(c.user_admin);
  r := pg_temp.try(format('select public.decide_request(%L, true)', q3));
  if r not like '%Aucun écart ouvert%' then raise exception 'FAIL : approbation d''un écart résolu : %', r; end if;
  if (select status from public.approval_requests where id = q3) <> 'en_attente' then raise exception 'FAIL : la demande n''est pas restée en attente'; end if;

  -- 7. retrait par le demandeur seulement
  r := pg_temp.try(format('select public.cancel_request(%L)', q3));
  if r not like '%non déposée par vous%' then raise exception 'FAIL : l''administrateur retire la demande d''autrui : %', r; end if;
  perform pg_temp.as_user(c.user_rh);
  perform public.cancel_request(q3);
  if (select status from public.approval_requests where id = q3) <> 'annulée' then raise exception 'FAIL : demande non annulée'; end if;

  -- 8. barème : demande du rh sans effet, puis approbation
  perform pg_temp.as_user(c.user_admin);
  v_hs := public.scale_get('HS');
  perform pg_temp.as_user(c.user_rh);
  q1 := public.request_scale_change('HS', v_floor, (select jsonb_agg(case when e ->> 'code' = 'HS_NUIT' then e || '{"rate_uplift": 0.70}' else e end) from jsonb_array_elements(v_hs) e));
  execute 'reset role';
  if public.hs_majoration('HS_NUIT', 9, v_floor) <> 1.60 then raise exception 'FAIL : barème modifié avant validation'; end if;
  perform pg_temp.as_user(c.user_rh);
  r := pg_temp.try(format('select public.request_scale_change(''QUOTITE_PRINCIPAL'', %L, ''[{"lower_bound":0,"upper_bound":10,"rate":0.1}]'')', v_floor));
  if r not like '%sans borne haute%' then raise exception 'FAIL : barème invalide accepté dès la demande : %', r; end if;
  perform pg_temp.as_user(c.user_admin);
  perform public.decide_request(q1, true);
  execute 'reset role';
  if public.hs_majoration('HS_NUIT', 9, v_floor) <> 1.70 then raise exception 'FAIL : barème approuvé non appliqué'; end if;

  -- 9. saisie directe de l'administrateur : approuvée d'office, appliquée tout de suite
  perform pg_temp.as_user(c.user_admin);
  q2 := public.request_parameter_change('loan_max_rate', 0.3);
  if public.get_loan_max_rate() <> 0.3 then raise exception 'FAIL : saisie directe de l''administrateur non appliquée'; end if;
  if (select status from public.approval_requests where id = q2) <> 'approuvée' then raise exception 'FAIL : saisie directe non approuvée d''office'; end if;
  q2 := public.request_parameter_reset('loan_max_rate');
  if public.get_loan_max_rate() <> 0.33 then raise exception 'FAIL : réinitialisation directe non appliquée'; end if;

  -- 10. ancien circuit : deroger_constat crée une demande, ne déroge plus directement
  execute 'reset role';
  insert into public.compliance_findings (rule_id, severity, entity, entity_id, employee_id, message)
  values ('TEST-REGLE3', 'A', 'employee', c.emp, c.emp, 'troisième écart de test');
  perform pg_temp.as_user(c.user_rh);
  perform public.deroger_constat((select id from public.compliance_findings where rule_id = 'TEST-REGLE3'), 'Régularisation en cours');
  if exists (select 1 from public.compliance_findings where rule_id = 'TEST-REGLE3' and waived_by is not null) then raise exception 'FAIL : deroger_constat déroge sans validation'; end if;
  if not exists (select 1 from public.approval_requests where kind = 'derogation' and target like 'TEST-REGLE3:%' and status = 'en_attente') then
    raise exception 'FAIL : deroger_constat n''a pas créé de demande';
  end if;

  execute 'reset role';
  if not exists (select 1 from public.audit_log where table_name = 'approval_requests') then raise exception 'FAIL : demandes non tracées dans audit_log'; end if;
  raise notice 'OK l2b_validation_admin';
end $$;
rollback;
