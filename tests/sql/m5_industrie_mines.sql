-- M5 (industrie et mines) : alerte d'habilitation (IND-T02) et prime de nuit sans taux / avec taux (IND-T01). Tout est annulé.
-- Attendu : "OK m5_industrie_mines"
begin;
do $$
declare
  v_emp uuid; v_u_rh uuid; n int; c text; s jsonb; s0 jsonb; th numeric; g numeric;
  v_mod text := 'soma-mod-industrie-mines-sn';
  v_p0 date := date '2026-08-01'; v_p1 date := date '2026-08-31';
begin
  select e.id into v_emp from public.employees e
   where e.status = 'Active' and exists (select 1 from public.salary_structure_assignments a where a.employee_id = e.id)
     and not exists (select 1 from public.employee_module_data x where x.employee_id = e.id)
   order by e.id limit 1;
  select user_id into v_u_rh from public.user_roles where role = 'rh' order by user_id limit 1;
  assert v_emp is not null and v_u_rh is not null, 'données de test manquantes';
  perform set_config('request.jwt.claim.sub', v_u_rh::text, true);

  insert into public.module_activation(module_id, enabled) values (v_mod, true) on conflict (module_id) do update set enabled = true;
  insert into public.employee_module_data(employee_id, module_id, data, valid_from)
    values (v_emp, v_mod, jsonb_build_object('ind_habilitation_expiry', (current_date - 5)::text), date '2026-01-01');

  -- IND-T02 : habilitation échue => erreur ; dans 10 jours => alerte ; dans 90 jours => rien ; module éteint => rien
  execute 'set local role authenticated';
  select code into c from public.legal_alerts() where employee_id = v_emp and code like 'habilitation%';
  execute 'reset role';
  assert c = 'habilitation_echue', 'échue : ' || coalesce(c, 'rien');

  update public.employee_module_data set data = jsonb_build_object('ind_habilitation_expiry', (current_date + 10)::text) where employee_id = v_emp;
  execute 'set local role authenticated';
  select code into c from public.legal_alerts() where employee_id = v_emp and code like 'habilitation%';
  execute 'reset role';
  assert c = 'habilitation_echeance', 'échéance : ' || coalesce(c, 'rien');

  update public.employee_module_data set data = jsonb_build_object('ind_habilitation_expiry', (current_date + 90)::text) where employee_id = v_emp;
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where employee_id = v_emp and code like 'habilitation%';
  execute 'reset role';
  assert n = 0, 'loin de l''échéance : rien (' || n || ')';

  update public.employee_module_data set data = jsonb_build_object('ind_habilitation_expiry', (current_date - 5)::text) where employee_id = v_emp;
  update public.module_activation set enabled = false where module_id = v_mod;
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where employee_id = v_emp and code like 'habilitation%';
  execute 'reset role';
  assert n = 0, 'module éteint : rien (' || n || ')';
  update public.module_activation set enabled = true where module_id = v_mod;

  -- IND-T01 : heures de nuit saisies sans taux => constat, aucune ligne
  s0 := public.compute_salary_slip(v_emp, v_p0, v_p1);
  th := (s0->'totals'->>'hourly_rate')::numeric;
  insert into public.module_payroll_input(employee_id, period, module_id, input_key, value) values (v_emp, v_p0, v_mod, 'INP_NIGHT_HOURS', 20);
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  assert not exists (select 1 from jsonb_array_elements(s->'lines') l where l->>'code' = 'IND_NIGHT_BONUS'), 'sans taux : pas de ligne';
  assert exists (select 1 from jsonb_array_elements(s->'module_findings') f where f->>'code' = 'missing_parameter:night_bonus_rate'), 'sans taux : constat attendu';
  assert (s->'totals'->>'gross_pay') = (s0->'totals'->>'gross_pay'), 'sans taux : brut inchangé';

  -- avec taux saisi : 20 h × TH_40 × 0,5
  insert into public.module_parameter_value(module_id, param_key, value, legal_status, source)
    values (v_mod, 'night_bonus_rate', '0.5', 'to_provide', 'test');
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  g := (select (l->>'gain')::numeric from jsonb_array_elements(s->'lines') l where l->>'code' = 'IND_NIGHT_BONUS');
  assert g is not null and abs(g - 20 * th * 0.5) < 0.01, 'prime de nuit : attendu ' || (20 * th * 0.5) || ', obtenu ' || coalesce(g::text, 'rien');
  raise notice 'OK m5_industrie_mines';
end $$;
rollback;
