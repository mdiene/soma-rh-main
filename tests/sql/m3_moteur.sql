-- M3 modules métiers : évaluateur JSONLogic, éléments de paie des modules, branchement dans compute_salary_slip. Tout est annulé.
-- Attendu : "OK m3_moteur"
begin;
do $$
declare
  v_emp uuid; v_p0 date := date '2026-08-01'; v_p1 date := date '2026-08-31';
  g0 numeric; n0 numeric; s jsonb; th numeric;
begin
  -- 1. évaluateur : opérateurs, valeurs manquantes (null, jamais 0), division par zéro
  assert public.jl_num('{"*":[{"var":"a"},{"var":"b"},2]}', '{"a":3,"b":1.5}') = 9, 'produit';
  assert public.jl_num('{"min":[{"var":"a"},10]}', '{"a":30}') = 10, 'min / plafond';
  assert public.jl_num('{"max":[0,{"-":[{"var":"a"},40]}]}', '{"a":52}') = 12, 'max / heures au-delà du seuil';
  assert public.jl_num('{"if":[{">":[{"var":"a"},5]},1,0]}', '{"a":6}') = 1, 'if vrai';
  assert public.jl_num('{"if":[{">":[{"var":"a"},5]},1,0]}', '{"a":4}') = 0, 'if faux';
  assert public.jl_num('{"*":[{"var":"absent"},2]}', '{}') is null, 'variable absente => null, pas 0';
  assert public.jl_num('{"/":[1,0]}', '{}') is null, 'division par zéro => null';
  assert public.jl_num('{"+":[0.1,0.2]}', '{}') = 0.3, 'précision numeric';
  assert public.jl_truthy(public.jl_eval('{"and":[{"==":[{"var":"a"},1]},{"!":[{"var":"b"}]}]}', '{"a":1,"b":false}')), 'and / ! / ==';
  begin perform public.jl_eval('{"exec":[1]}', '{}'); assert false, 'opérateur inconnu accepté';
  exception when others then assert sqlerrm like '%inconnu%', 'message opérateur inconnu : ' || sqlerrm; end;

  -- 2. branchement : module de test (règle = saisie × taux horaire × paramètre)
  select e.id into v_emp from public.employees e
   where e.status = 'Active' and exists (select 1 from public.salary_structure_assignments a where a.employee_id = e.id) order by e.id limit 1;
  assert v_emp is not null, 'aucun salarié de test';
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  g0 := (s->'totals'->>'gross_pay')::numeric; n0 := (s->'totals'->>'net_pay')::numeric; th := (s->'totals'->>'hourly_rate')::numeric;

  insert into public.module_manifest(module_id, name, version, status, hash, manifest) values ('zz-test', 'Module de test', '0.0.1', 'draft', 'x',
    '{"parameters":{"rate":{"legal_status":"to_provide","value":null}},
      "payroll_rules":[{"rule_id":"T_PRIME","label":"Prime de test","inputs":["INP_X"],"params":["rate"],"taxable":true,
        "logic":{"*":[{"var":"INP_X"},{"var":"hourly_rate"},{"var":"rate"}]}}]}');
  insert into public.module_activation(module_id, enabled) values ('zz-test', true);
  insert into public.module_payroll_input(employee_id, period, module_id, input_key, value) values (v_emp, v_p0, 'zz-test', 'INP_X', 10);

  -- a. paramètre manquant : aucun montant inventé, une alerte, paie du cœur inchangée
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  assert (s->'totals'->>'gross_pay')::numeric = g0, 'param manquant : le brut ne doit pas bouger';
  assert s->'module_findings'->0->>'code' = 'missing_parameter:rate', 'alerte paramètre manquant : ' || coalesce(s->>'module_findings', 'null');

  -- b. paramètre saisi : brut = brut du cœur + 10 × TH × 0,5, IR / cotisations recalculés par le cœur
  insert into public.module_parameter_value(module_id, param_key, value, legal_status) values ('zz-test', 'rate', '0.5', 'to_provide');
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  assert (s->'totals'->>'gross_pay')::numeric = g0 + 10 * th * 0.5, 'brut avec prime : ' || (s->'totals'->>'gross_pay') || ' vs ' || (g0 + 10 * th * 0.5);
  assert (s->'totals'->>'net_pay')::numeric <> n0, 'le net doit suivre';
  assert exists (select 1 from jsonb_array_elements(s->'lines') l where l->>'code' = 'T_PRIME'), 'ligne de bulletin absente';
  assert jsonb_array_length(s->'module_findings') = 0, 'plus d''alerte';

  -- c. pas de saisie sur la période : aucune ligne, aucune alerte
  assert (public.compute_salary_slip(v_emp, date '2026-07-01', date '2026-07-31')->'module_findings') = '[]'::jsonb, 'période sans saisie';

  -- d. non imposable : ajouté au net, pas au brut
  update public.module_manifest set manifest = jsonb_set(manifest, '{payroll_rules,0,taxable}', 'false') where module_id = 'zz-test';
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  assert (s->'totals'->>'gross_pay')::numeric = g0, 'non imposable : brut inchangé';
  assert (s->'totals'->>'net_pay')::numeric = n0 + 10 * th * 0.5, 'non imposable : net + montant';

  -- e. module éteint : résultat identique à la paie du cœur
  update public.module_activation set enabled = false where module_id = 'zz-test';
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  assert (s->'totals'->>'gross_pay')::numeric = g0 and (s->'totals'->>'net_pay')::numeric = n0, 'module éteint : paie identique';

  -- f. RLS activée sur la nouvelle table
  assert (select relrowsecurity from pg_class where oid = 'public.module_payroll_input'::regclass), 'RLS module_payroll_input';
  raise notice 'OK m3_moteur';
end $$;
rollback;
