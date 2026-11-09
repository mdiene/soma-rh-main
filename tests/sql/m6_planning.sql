-- M6 : planning métier (modèles de postes, planification, report présences + heures de nuit, conformité hebdomadaire). Tout est annulé.
-- Attendu : "OK m6_planning"
begin;
do $$
declare
  v_emp uuid; v_u_rh uuid; n int; r jsonb; d date; wk date := date '2026-08-03'; nt numeric;
begin
  select e.id into v_emp from public.employees e
   where e.status = 'Active' and not exists (select 1 from public.employee_module_data x where x.employee_id = e.id)
     and not exists (select 1 from public.attendance t where t.employee_id = e.id and t.attendance_date between date '2026-08-01' and date '2026-08-31')
   order by e.id limit 1;
  select user_id into v_u_rh from public.user_roles where role = 'rh' order by user_id limit 1;
  assert v_emp is not null and v_u_rh is not null, 'données de test manquantes';
  perform set_config('request.jwt.claim.sub', v_u_rh::text, true);
  execute 'set local role authenticated';

  -- modèles : seuls ceux des modules actifs
  insert into public.module_activation(module_id, enabled) values ('soma-mod-securite-gardiennage-sn', false)
    on conflict (module_id) do update set enabled = false;
  select count(*) into n from public.shift_templates() where code = 'V12N';
  assert n = 0, 'module éteint : pas de modèle (' || n || ')';
  update public.module_activation set enabled = true where module_id = 'soma-mod-securite-gardiennage-sn';
  select night_hours into nt from public.shift_templates() where code = 'V12N';
  assert nt = 7, 'V12N : 7 h de nuit (' || coalesce(nt::text, 'rien') || ')';

  -- code inconnu refusé
  begin
    perform public.plan_shifts(jsonb_build_array(jsonb_build_object('employee_id', v_emp, 'work_date', wk, 'code', 'XXX')));
    assert false, 'code inconnu accepté';
  exception when check_violation then null; end;

  -- 5 nuits de 12 h du lundi au vendredi
  for d in select generate_series(wk, wk + 4, interval '1 day')::date loop
    perform public.plan_shifts(jsonb_build_array(jsonb_build_object('employee_id', v_emp, 'work_date', d, 'code', 'V12N')));
  end loop;
  select count(*) into n from public.module_shift where employee_id = v_emp;
  assert n = 5, '5 postes planifiés (' || n || ')';

  -- remplacer / supprimer
  perform public.plan_shifts(jsonb_build_array(jsonb_build_object('employee_id', v_emp, 'work_date', wk, 'code', 'V12J')));
  assert (select night_hours from public.module_shift where employee_id = v_emp and work_date = wk) = 0, 'poste de jour : 0 h de nuit';
  perform public.plan_shifts(jsonb_build_array(jsonb_build_object('employee_id', v_emp, 'work_date', wk, 'code', '')));
  select count(*) into n from public.module_shift where employee_id = v_emp;
  assert n = 4, 'poste supprimé (' || n || ')';

  -- conformité : 4 × 12 = 48 h > 40 h (aucune catégorie de seuil) => alerte ; pas 7 jours => pas d'erreur de repos
  select count(*) into n from public.planning_compliance(date '2026-08-01', date '2026-08-31') where employee_id = v_emp and code = 'duree_hebdo_depassee';
  assert n = 1, 'dépassement attendu (' || n || ')';
  select count(*) into n from public.planning_compliance(date '2026-08-01', date '2026-08-31') where employee_id = v_emp and code = 'repos_hebdo_manquant';
  assert n = 0, 'repos présent (' || n || ')';
  -- 7 jours planifiés => repos hebdomadaire manquant
  for d in select generate_series(wk, wk + 6, interval '1 day')::date loop
    perform public.plan_shifts(jsonb_build_array(jsonb_build_object('employee_id', v_emp, 'work_date', d, 'code', 'V12J')));
  end loop;
  select count(*) into n from public.planning_compliance(date '2026-08-01', date '2026-08-31') where employee_id = v_emp and code = 'repos_hebdo_manquant';
  assert n = 1, 'repos manquant attendu (' || n || ')';

  -- report : présences créées sans écraser l'existant ; heures de nuit en saisie de période
  for d in select generate_series(wk, wk + 6, interval '1 day')::date loop
    perform public.plan_shifts(jsonb_build_array(jsonb_build_object('employee_id', v_emp, 'work_date', d, 'code', 'V12N')));
  end loop;
  execute 'reset role';
  insert into public.attendance(employee_id, attendance_date, status, working_hours) values (v_emp, wk, 'Présent', 8);
  execute 'set local role authenticated';
  r := public.apply_planning(date '2026-08-15');
  assert (r->>'attendance_created')::int = 6, 'présences créées : 6 (' || r::text || ')';
  assert (select working_hours from public.attendance where employee_id = v_emp and attendance_date = wk) = 8, 'présence saisie conservée';
  assert (select value from public.module_payroll_input where employee_id = v_emp and period = date '2026-08-01' and input_key = 'INP_NIGHT_HOURS') = 49, 'heures de nuit : 7 × 7 = 49';
  r := public.apply_planning(date '2026-08-15');
  assert (r->>'attendance_created')::int = 0, 'report idempotent';
  raise notice 'OK m6_planning';
end $$;
rollback;
