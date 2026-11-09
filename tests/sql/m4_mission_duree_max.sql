-- M4 : alerte de durée maximale d'une mission d'intérim dans legal_alerts. Tout est annulé.
-- Attendu : "OK m4_mission_duree_max"
begin;
do $$
declare
  v_emp uuid; v_u_rh uuid; n int; sev text; d date;
begin
  select e.id into v_emp from public.employees e
   where e.status = 'Active' and not exists (select 1 from public.employee_module_data x where x.employee_id = e.id)
   order by e.id limit 1;
  select user_id into v_u_rh from public.user_roles where role = 'rh' order by user_id limit 1;
  assert v_emp is not null and v_u_rh is not null, 'données de test manquantes';
  perform set_config('request.jwt.claim.sub', v_u_rh::text, true);

  insert into public.module_activation(module_id, enabled) values ('soma-mod-services-interim-sn', true)
    on conflict (module_id) do update set enabled = true;

  -- 1. mission commencée il y a 3 ans, en cours : durée dépassée => erreur
  insert into public.employee_module_data(employee_id, module_id, data, valid_from)
    values (v_emp, 'soma-mod-services-interim-sn', '{"is_interim": true}', current_date - interval '3 years');
  execute 'set local role authenticated';
  select severity into sev from public.legal_alerts() where code = 'mission_interim_duree_max' and employee_id = v_emp;
  execute 'reset role';
  assert sev = 'erreur', 'dépassement attendu : ' || coalesce(sev, 'aucune alerte');

  -- 2. échéance dans 15 jours => alerte
  update public.employee_module_data set valid_from = current_date - interval '2 years' + interval '15 days' where employee_id = v_emp;
  execute 'set local role authenticated';
  select severity, due_date into sev, d from public.legal_alerts() where code = 'mission_interim_echeance' and employee_id = v_emp;
  execute 'reset role';
  assert sev = 'alerte' and d = current_date + 15, 'échéance attendue : ' || coalesce(sev, 'aucune') || ' ' || coalesce(d::text, '');

  -- 3. mission récente : rien
  update public.employee_module_data set valid_from = current_date - interval '3 months' where employee_id = v_emp;
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where employee_id = v_emp and code like 'mission_interim%';
  execute 'reset role';
  assert n = 0, 'mission récente : pas d''alerte (' || n || ')';

  -- 4. mission close avant les 2 ans : rien
  update public.employee_module_data set valid_from = current_date - interval '5 years', valid_to = current_date - interval '4 years' where employee_id = v_emp;
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where employee_id = v_emp and code like 'mission_interim%';
  execute 'reset role';
  assert n = 0, 'mission close : pas d''alerte (' || n || ')';

  -- 5. non intérimaire : rien
  update public.employee_module_data set valid_from = current_date - interval '3 years', valid_to = null, data = '{"is_interim": false}' where employee_id = v_emp;
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where employee_id = v_emp and code like 'mission_interim%';
  execute 'reset role';
  assert n = 0, 'non intérimaire : pas d''alerte (' || n || ')';

  -- 6. module éteint : rien
  update public.employee_module_data set data = '{"is_interim": true}' where employee_id = v_emp;
  update public.module_activation set enabled = false where module_id = 'soma-mod-services-interim-sn';
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where employee_id = v_emp and code like 'mission_interim%';
  execute 'reset role';
  assert n = 0, 'module éteint : pas d''alerte (' || n || ')';
  raise notice 'OK m4_mission_duree_max';
end $$;
rollback;
