-- M4 : INT-T01 (motif de mission hors liste refusé) et alerte de cumul des missions enchaînées. Tout est annulé.
-- Attendu : "OK m4_motif_cumul"
begin;
do $$
declare
  v_emp uuid; v_u_rh uuid; n int;
begin
  select e.id into v_emp from public.employees e
   where e.status = 'Active' and not exists (select 1 from public.employee_module_data x where x.employee_id = e.id)
   order by e.id limit 1;
  select user_id into v_u_rh from public.user_roles where role = 'rh' order by user_id limit 1;
  assert v_emp is not null and v_u_rh is not null, 'données de test manquantes';
  perform set_config('request.jwt.claim.sub', v_u_rh::text, true);
  insert into public.module_activation(module_id, enabled) values ('soma-mod-services-interim-sn', true)
    on conflict (module_id) do update set enabled = true;

  -- INT-T01 : motif hors liste ou absent => refusé
  begin
    insert into public.employee_module_data(employee_id, module_id, data, valid_from)
      values (v_emp, 'soma-mod-services-interim-sn', '{"is_interim": true, "mission_reason": "CONVENANCE"}', current_date - 100);
    assert false, 'motif hors liste accepté';
  exception when check_violation then null; end;
  begin
    insert into public.employee_module_data(employee_id, module_id, data, valid_from)
      values (v_emp, 'soma-mod-services-interim-sn', '{"is_interim": true}', current_date - 100);
    assert false, 'motif absent accepté';
  exception when check_violation then null; end;
  -- non intérimaire : le motif n'est pas exigé
  insert into public.employee_module_data(employee_id, module_id, data, valid_from, valid_to)
    values (v_emp, 'soma-mod-services-interim-sn', '{"is_interim": false}', current_date - 2000, current_date - 1900);

  -- motif valide : accepté
  insert into public.employee_module_data(employee_id, module_id, data, valid_from, valid_to)
    values (v_emp, 'soma-mod-services-interim-sn', '{"is_interim": true, "mission_reason": "REMPLACEMENT_SUSPENSION", "client_company_id": "CLI-1"}',
            current_date - 1500, current_date - 800);

  -- une seule mission chez le client : pas de cumul
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where employee_id = v_emp and code = 'mission_interim_cumul';
  execute 'reset role';
  assert n = 0, 'une mission : pas de cumul (' || n || ')';

  -- seconde mission chez le même client : 700 + 600 jours > 2 ans => alerte
  insert into public.employee_module_data(employee_id, module_id, data, valid_from, valid_to)
    values (v_emp, 'soma-mod-services-interim-sn', '{"is_interim": true, "mission_reason": "ACCROISSEMENT_TEMPORAIRE", "client_company_id": "CLI-1"}',
            current_date - 700, current_date - 100);
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where employee_id = v_emp and code = 'mission_interim_cumul';
  execute 'reset role';
  assert n = 1, 'cumul attendu (' || n || ')';

  -- autre client pour la seconde mission : plus de cumul
  update public.employee_module_data set data = jsonb_set(data, '{client_company_id}', '"CLI-2"')
   where employee_id = v_emp and data->>'mission_reason' = 'ACCROISSEMENT_TEMPORAIRE';
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where employee_id = v_emp and code = 'mission_interim_cumul';
  execute 'reset role';
  assert n = 0, 'clients différents : pas de cumul (' || n || ')';
  raise notice 'OK m4_motif_cumul';
end $$;
rollback;
