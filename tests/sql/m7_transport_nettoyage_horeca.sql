-- M7 : cas dorés Transport (TR-T01..T03), Nettoyage/BTP (NBTP-T01..T03), HORECA (HOR-T01..T02). Tout est annulé.
-- Attendu : "OK m7_transport_nettoyage_horeca"
begin;
do $$
declare
  v_emp uuid; v_u_rh uuid; n int; c text; s jsonb; s0 jsonb; th numeric; g numeric;
  v_t text := 'soma-mod-transport-sn'; v_n text := 'soma-mod-nettoyage-btp-sn'; v_h text := 'soma-mod-horeca-sn';
  v_p0 date := date '2026-08-01'; v_p1 date := date '2026-08-31';
begin
  select e.id into v_emp from public.employees e
   where e.status = 'Active' and exists (select 1 from public.salary_structure_assignments a where a.employee_id = e.id)
     and not exists (select 1 from public.employee_module_data x where x.employee_id = e.id)
   order by e.id limit 1;
  select user_id into v_u_rh from public.user_roles where role = 'rh' order by user_id limit 1;
  assert v_emp is not null and v_u_rh is not null, 'données de test manquantes';
  assert (select count(*) from public.module_manifest where module_id in (v_t, v_n, v_h)) = 3, 'manifestes non chargés (node scripts/load-modules.mjs)';
  perform set_config('request.jwt.claim.sub', v_u_rh::text, true);
  insert into public.module_activation(module_id, enabled) select m, true from unnest(array[v_t, v_n, v_h]) m
    on conflict (module_id) do update set enabled = true;
  s0 := public.compute_salary_slip(v_emp, v_p0, v_p1);
  th := (s0->'totals'->>'hourly_rate')::numeric;

  -- TR-T01 : trajets sans tarif => constat, aucune ligne, brut inchangé
  insert into public.module_payroll_input(employee_id, period, module_id, input_key, value) values (v_emp, v_p0, v_t, 'INP_TRIPS', 20);
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  assert not exists (select 1 from jsonb_array_elements(s->'lines') l where l->>'code' = 'TR_TRIP'), 'TR-T01 : pas de ligne';
  assert exists (select 1 from jsonb_array_elements(s->'module_findings') f where f->>'code' = 'missing_parameter:trip_rate'), 'TR-T01 : constat attendu';
  assert (s->'totals'->>'gross_pay') = (s0->'totals'->>'gross_pay'), 'TR-T01 : brut inchangé';

  -- TR-T02 : 20 trajets à 5 000 F + 2 découchés à 3 × TH
  insert into public.module_parameter_value(module_id, param_key, value, legal_status, source) values
    (v_t, 'trip_rate', '5000', 'to_provide', 'test'), (v_t, 'overnight_allowance_rate', '3', 'to_provide', 'test');
  insert into public.module_payroll_input(employee_id, period, module_id, input_key, value) values (v_emp, v_p0, v_t, 'INP_OVERNIGHTS', 2);
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  g := (select (l->>'gain')::numeric from jsonb_array_elements(s->'lines') l where l->>'code' = 'TR_TRIP');
  assert g is not null and abs(g - 100000) < 0.01, 'TR-T02 trajets : ' || coalesce(g::text, 'rien');
  g := (select (l->>'gain')::numeric from jsonb_array_elements(s->'lines') l where l->>'code' = 'TR_OVERNIGHT');
  assert g is not null and abs(g - 2 * th * 3) < 0.01, 'TR-T02 découché : attendu ' || (2 * th * 3) || ', obtenu ' || coalesce(g::text, 'rien');

  -- TR-T03 : permis échu => erreur ; dans 10 jours => alerte ; module éteint => rien
  insert into public.employee_module_data(employee_id, module_id, data, valid_from)
    values (v_emp, v_t, jsonb_build_object('tr_permis_expiry', (current_date - 3)::text), date '2026-01-01');
  execute 'set local role authenticated';
  select code into c from public.legal_alerts() where employee_id = v_emp and code like 'permis%';
  execute 'reset role';
  assert c = 'permis_echu', 'TR-T03 échu : ' || coalesce(c, 'rien');
  update public.employee_module_data set data = jsonb_build_object('tr_permis_expiry', (current_date + 10)::text) where employee_id = v_emp and module_id = v_t;
  execute 'set local role authenticated';
  select code into c from public.legal_alerts() where employee_id = v_emp and code like 'permis%';
  execute 'reset role';
  assert c = 'permis_echeance', 'TR-T03 échéance : ' || coalesce(c, 'rien');
  update public.module_activation set enabled = false where module_id = v_t;
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where employee_id = v_emp and code like 'permis%';
  execute 'reset role';
  assert n = 0, 'TR-T03 module éteint : rien (' || n || ')';

  -- NBTP-T01 : heures de hauteur sans multiple => constat, aucune ligne
  insert into public.module_payroll_input(employee_id, period, module_id, input_key, value) values (v_emp, v_p0, v_n, 'INP_HEIGHT_HOURS', 15);
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  assert not exists (select 1 from jsonb_array_elements(s->'lines') l where l->>'code' = 'NBTP_HEIGHT'), 'NBTP-T01 : pas de ligne';
  assert exists (select 1 from jsonb_array_elements(s->'module_findings') f where f->>'code' = 'missing_parameter:height_rate'), 'NBTP-T01 : constat attendu';

  -- NBTP-T02 : 15 h × TH × 0,3
  insert into public.module_parameter_value(module_id, param_key, value, legal_status, source) values (v_n, 'height_rate', '0.3', 'to_provide', 'test');
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  g := (select (l->>'gain')::numeric from jsonb_array_elements(s->'lines') l where l->>'code' = 'NBTP_HEIGHT');
  assert g is not null and abs(g - 15 * th * 0.3) < 0.01, 'NBTP-T02 : attendu ' || (15 * th * 0.3) || ', obtenu ' || coalesce(g::text, 'rien');

  -- NBTP-T03 : habilitation échue + attestation art. 291 manquante (société sans date)
  insert into public.employee_module_data(employee_id, module_id, data, valid_from)
    values (v_emp, v_n, jsonb_build_object('nbtp_habilitation_expiry', (current_date - 5)::text), date '2026-01-01');
  execute 'set local role authenticated';
  select code into c from public.legal_alerts() where employee_id = v_emp and code like 'habilitation%';
  select count(*) into n from public.legal_alerts() where code = 'attestation_regularite_manquante';
  execute 'reset role';
  assert c = 'habilitation_echue', 'NBTP-T03 habilitation : ' || coalesce(c, 'rien');
  assert n >= 1 or not exists (select 1 from public.companies where social_regularity_cert_date is null), 'NBTP-T03 : attestation art. 291 attendue';

  -- HOR-T01 : service saisi sans traitement paramétré => constat, aucune ligne
  insert into public.module_payroll_input(employee_id, period, module_id, input_key, value) values (v_emp, v_p0, v_h, 'INP_SERVICE_AMOUNT', 40000);
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  assert not exists (select 1 from jsonb_array_elements(s->'lines') l where l->>'code' = 'HOR_SERVICE'), 'HOR-T01 : pas de ligne';
  assert exists (select 1 from jsonb_array_elements(s->'module_findings') f where f->>'code' = 'missing_parameter:service_share_taxable'), 'HOR-T01 : constat attendu';

  -- HOR-T02 : traitement saisi => 40 000 F
  insert into public.module_parameter_value(module_id, param_key, value, legal_status, source) values (v_h, 'service_share_taxable', '"texte-test"', 'to_provide', 'test');
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  g := (select (l->>'gain')::numeric from jsonb_array_elements(s->'lines') l where l->>'code' = 'HOR_SERVICE');
  assert g is not null and abs(g - 40000) < 0.01, 'HOR-T02 : ' || coalesce(g::text, 'rien');
  raise notice 'OK m7_transport_nettoyage_horeca';
end $$;
rollback;
