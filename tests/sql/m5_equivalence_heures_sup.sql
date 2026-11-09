-- M5 (gardiennage) : heures supplémentaires au-delà du seuil d'équivalence, depuis la grille de présences. Tout est annulé.
-- Attendu : "OK m5_equivalence_heures_sup"
begin;
do $$
declare
  v_emp uuid; s jsonb; s0 jsonb; th numeric; g numeric; exp numeric; d date;
  v_mod text := 'soma-mod-securite-gardiennage-sn';
  v_p0 date := date '2026-08-01'; v_p1 date := date '2026-08-31';
begin
  select e.id into v_emp from public.employees e
   where e.status = 'Active' and exists (select 1 from public.salary_structure_assignments a where a.employee_id = e.id)
     and not exists (select 1 from public.employee_module_data x where x.employee_id = e.id)
     and not exists (select 1 from public.attendance t where t.employee_id = e.id and t.attendance_date between v_p0 and v_p1)
   order by e.id limit 1;
  assert v_emp is not null, 'données de test manquantes';

  insert into public.module_activation(module_id, enabled) values (v_mod, true) on conflict (module_id) do update set enabled = true;
  insert into public.employee_module_data(employee_id, module_id, data, valid_from)
    values (v_emp, v_mod, '{"sec_categorie_poste": "JOUR"}', date '2026-01-01');
  delete from public.module_parameter_value where module_id = v_mod and param_key = 'equivalence_thresholds';
  insert into public.module_parameter_value(module_id, param_key, value, legal_status, source)
    values (v_mod, 'equivalence_thresholds', '{"JOUR": 56, "SUPPORT": 40}', 'secondary', 'test');

  -- sans présence saisie : aucune ligne, aucun constat de valeur manquante
  s0 := public.compute_salary_slip(v_emp, v_p0, v_p1);
  assert not exists (select 1 from jsonb_array_elements(s0->'lines') l where l->>'code' = 'GARD_OVERTIME'), 'sans présence : pas de ligne';
  assert not exists (select 1 from jsonb_array_elements(s0->'module_findings') f where f->>'rule_id' = 'GARD_OVERTIME'), 'sans présence : pas de constat';
  th := (s0->'totals'->>'hourly_rate')::numeric;

  -- 11 jours de 24 h = 264 h de présence ; seuil 56 h/sem = 242,667 h/mois => 21,333 h en première tranche (+10 %)
  for d in select generate_series(date '2026-08-03', date '2026-08-13', interval '1 day')::date loop
    insert into public.attendance(employee_id, attendance_date, status, working_hours) values (v_emp, d, 'Présent', 24);
  end loop;
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  g := (select (l->>'gain')::numeric from jsonb_array_elements(s->'lines') l where l->>'code' = 'GARD_OVERTIME');
  exp := th * (40.0 * 52 / 12) / (56.0 * 52 / 12) * (264 - 56.0 * 52 / 12) * 1.10;
  assert g is not null and abs(g - exp) < 0.01, 'seuil 56 h : attendu ' || exp || ', obtenu ' || coalesce(g::text, 'rien');
  assert (s->'totals'->>'gross_pay')::numeric > (s0->'totals'->>'gross_pay')::numeric, 'le brut augmente';

  -- seuil 40 h (support) : 264 - 173,333 = 90,667 h ; 34,667 h à +10 %, 56 h à +35 %
  update public.employee_module_data set data = '{"sec_categorie_poste": "SUPPORT"}' where employee_id = v_emp;
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  g := (select (l->>'gain')::numeric from jsonb_array_elements(s->'lines') l where l->>'code' = 'GARD_OVERTIME');
  exp := th * (8.0 * 52 / 12 * 1.10 + (264 - 40.0 * 52 / 12 - 8.0 * 52 / 12) * 1.35);
  assert g is not null and abs(g - exp) < 0.01, 'seuil 40 h : attendu ' || exp || ', obtenu ' || coalesce(g::text, 'rien');

  -- catégorie sans seuil : aucun montant inventé, constat émis
  update public.employee_module_data set data = '{"sec_categorie_poste": "INCONNUE"}' where employee_id = v_emp;
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  assert not exists (select 1 from jsonb_array_elements(s->'lines') l where l->>'code' = 'GARD_OVERTIME'), 'catégorie inconnue : pas de montant';
  assert exists (select 1 from jsonb_array_elements(s->'module_findings') f where f->>'rule_id' = 'GARD_OVERTIME'), 'catégorie inconnue : constat attendu';

  -- module éteint : plus de ligne
  update public.module_activation set enabled = false where module_id = v_mod;
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  assert not exists (select 1 from jsonb_array_elements(s->'lines') l where l->>'code' = 'GARD_OVERTIME'), 'module éteint : pas de ligne';
  raise notice 'OK m5_equivalence_heures_sup';
end $$;
rollback;
