-- Lot G : coefficients d'heures supplémentaires lus dans overtime_rates ; préavis lu dans notice_scales. Tout est annulé.
-- Attendu : "OK lotg_hs_preavis"
begin;
-- Le jeu de majorations en vigueur est verrouillé par les paies calculées (L1b) : on lève le garde dans cette transaction annulée,
-- ce test vérifie que le moteur lit le référentiel.
alter table public.overtime_rates disable trigger overtime_rates_guard;
do $$
declare v_emp uuid; v_p date; v_before numeric; v_after numeric; v_th numeric; v_user uuid; v_cat text;
begin
  -- repli et référentiel
  assert public.hs_majoration('HS_JOUR_8_PREMIERES', 9) = 1.15, 'lecture 15 %';
  assert public.hs_majoration('INCONNU', 1.33) = 1.33, 'repli';
  -- un salarié avec 15 % d'HS : le montant suit le référentiel
  select employee_id, period into v_emp, v_p from public.payroll_inputs where overtime_15 > 0 order by period limit 1;
  v_before := (public.compute_salary_slip(v_emp, v_p, (v_p + interval '1 month - 1 day')::date)->'totals'->>'overtime_amount')::numeric;
  v_th     := (public.compute_salary_slip(v_emp, v_p, (v_p + interval '1 month - 1 day')::date)->'totals'->>'hourly_rate')::numeric;
  update public.overtime_rates set rate_uplift = 0.25 where code = 'HS_JOUR_8_PREMIERES';
  v_after  := (public.compute_salary_slip(v_emp, v_p, (v_p + interval '1 month - 1 day')::date)->'totals'->>'overtime_amount')::numeric;
  assert v_before > 0 and v_after > v_before, format('HS non liées au référentiel : % -> %', v_before, v_after);
  assert abs((v_after - v_before) - (v_before / 1.15 * 0.10)) < 0.0001, 'écart attendu = 10 points de majoration';
  -- préavis : un cadre 3 mois, un employé 1 mois (profil RH)
  select user_id into v_user from public.user_roles where role = 'rh' limit 1;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  select e.id into v_emp from public.employees e join public.employee_grades g on g.id = e.grade_id where g.staff_status = 'Cadres' limit 1;
  assert public.preavis_mois(v_emp) = 3, 'préavis cadre';
  select e.id into v_emp from public.employees e join public.employee_grades g on g.id = e.grade_id where lower(g.staff_status) like 'employ%' limit 1;
  assert public.preavis_mois(v_emp) = 1, 'préavis employé';
  raise notice 'OK lotg_hs_preavis';
end $$;
rollback;
