-- M5 (gardiennage) : alertes d'attestation de régularité sociale (art. 291) et de seuil d'équivalence manquant (GARD-T01). Tout est annulé.
-- Attendu : "OK m5_gardiennage_alertes"
begin;
do $$
declare
  v_emp uuid; v_u_rh uuid; n int; c text; sev text;
begin
  select e.id into v_emp from public.employees e
   where e.status = 'Active' and not exists (select 1 from public.employee_module_data x where x.employee_id = e.id)
   order by e.id limit 1;
  select user_id into v_u_rh from public.user_roles where role = 'rh' order by user_id limit 1;
  assert v_emp is not null and v_u_rh is not null, 'données de test manquantes';
  perform set_config('request.jwt.claim.sub', v_u_rh::text, true);

  -- module éteint : aucune alerte gardiennage
  update public.module_activation set enabled = false where module_id = 'soma-mod-securite-gardiennage-sn';
  update public.companies set social_regularity_cert_date = null;
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where code like 'attestation_regularite%' or code = 'equivalence_manquante';
  execute 'reset role';
  assert n = 0, 'module éteint : rien (' || n || ')';

  insert into public.module_activation(module_id, enabled) values ('soma-mod-securite-gardiennage-sn', true)
    on conflict (module_id) do update set enabled = true;

  -- attestation : absente => erreur ; échue => erreur ; échéance < 30 j => alerte ; récente => rien
  execute 'set local role authenticated';
  select code into c from public.legal_alerts() where code like 'attestation_regularite%';
  execute 'reset role';
  assert c = 'attestation_regularite_manquante', 'absente : ' || coalesce(c, 'rien');

  update public.companies set social_regularity_cert_date = current_date - interval '7 months';
  execute 'set local role authenticated';
  select code into c from public.legal_alerts() where code like 'attestation_regularite%';
  execute 'reset role';
  assert c = 'attestation_regularite_echue', 'échue : ' || coalesce(c, 'rien');

  update public.companies set social_regularity_cert_date = current_date - interval '6 months' + interval '10 days';
  execute 'set local role authenticated';
  select code, severity into c, sev from public.legal_alerts() where code like 'attestation_regularite%';
  execute 'reset role';
  assert c = 'attestation_regularite_echeance' and sev = 'alerte', 'échéance : ' || coalesce(c, 'rien');

  update public.companies set social_regularity_cert_date = current_date - interval '1 month';
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where code like 'attestation_regularite%';
  execute 'reset role';
  assert n = 0, 'attestation récente : rien (' || n || ')';

  -- GARD-T01 : salarié gardien sans seuil d'équivalence saisi => erreur, aucun montant inventé
  insert into public.employee_module_data(employee_id, module_id, data, valid_from)
    values (v_emp, 'soma-mod-securite-gardiennage-sn', '{"sec_categorie_poste": "GARDIEN_NUIT"}', current_date - 30);
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where code = 'equivalence_manquante' and employee_id = v_emp;
  execute 'reset role';
  assert n = 1, 'seuil absent : alerte attendue (' || n || ')';

  -- seuil saisi pour une autre catégorie : toujours en erreur ; pour la bonne catégorie : plus d'alerte
  insert into public.module_parameter_value(module_id, param_key, value, legal_status, source)
    values ('soma-mod-securite-gardiennage-sn', 'equivalence_thresholds', '{"VEILLEUR": 56}', 'to_provide', 'test');
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where code = 'equivalence_manquante' and employee_id = v_emp;
  execute 'reset role';
  assert n = 1, 'autre catégorie : alerte maintenue (' || n || ')';

  update public.module_parameter_value set value = '{"VEILLEUR": 56, "GARDIEN_NUIT": 60}'
   where module_id = 'soma-mod-securite-gardiennage-sn' and param_key = 'equivalence_thresholds';
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where code = 'equivalence_manquante' and employee_id = v_emp;
  execute 'reset role';
  assert n = 0, 'seuil saisi : plus d''alerte (' || n || ')';
  -- durée de validité paramétrable : attestation de 4 mois, validité réglée à 3 mois => échue
  update public.companies set social_regularity_cert_date = current_date - interval '4 months';
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where code = 'attestation_regularite_echue';
  execute 'reset role';
  assert n = 0, 'validité 6 mois : 4 mois non échue (' || n || ')';
  insert into public.module_parameter_value(module_id, param_key, value, legal_status, source)
    values ('soma-mod-securite-gardiennage-sn', 'attestation_validity_months', '3', 'verified', 'test')
    on conflict on constraint module_parameter_value_module_id_param_key_daterange_excl do nothing;
  update public.module_parameter_value set value = '3'
   where module_id = 'soma-mod-securite-gardiennage-sn' and param_key = 'attestation_validity_months';
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where code = 'attestation_regularite_echue';
  execute 'reset role';
  assert n = 1, 'validité 3 mois : échue (' || n || ')';
  raise notice 'OK m5_gardiennage_alertes';
end $$;
rollback;
