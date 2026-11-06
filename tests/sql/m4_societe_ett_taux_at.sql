-- M4 (société) : taux AT/MP propre à la société dans compute_salary_slip ; alerte d'agrément ETT dans legal_alerts. Tout est annulé.
-- Attendu : "OK m4_societe_ett_taux_at"
begin;
do $$
declare
  v_emp uuid; v_u_rh uuid; v_p0 date := date '2026-08-01'; v_p1 date := date '2026-08-31';
  s0 jsonb; s jsonb; v_default numeric; v_base numeric; n int;
begin
  select e.id into v_emp from public.employees e
   where e.status = 'Active' and exists (select 1 from public.salary_structure_assignments a where a.employee_id = e.id) order by e.id limit 1;
  select user_id into v_u_rh from public.user_roles where role = 'rh' order by user_id limit 1;
  assert v_emp is not null and v_u_rh is not null, 'données de test manquantes';

  -- 1. taux AT : sans valeur société, le taux du paramétrage s'applique (comportement historique)
  assert (select css_at_rate from public.companies limit 1) is null, 'la société ne doit pas avoir de taux AT au départ';
  s0 := public.compute_salary_slip(v_emp, v_p0, v_p1);
  v_default := (public.payroll_settings_at(v_p1)).css_at_rate;
  v_base := (s0->'totals'->>'css_base')::numeric;
  assert v_base > 0, 'assiette CSS nulle : salarié de test inadapté';
  assert (s0->'totals'->>'css_at')::numeric = v_base * v_default, 'taux par défaut : ' || (s0->'totals'->>'css_at');

  -- 2. taux de la société : seule la charge patronale AT change, ni le brut ni le net
  update public.companies set css_at_rate = 0.03;
  s := public.compute_salary_slip(v_emp, v_p0, v_p1);
  assert (s->'totals'->>'css_at')::numeric = v_base * 0.03, 'taux société 3 % : ' || (s->'totals'->>'css_at');
  assert (s->'totals'->>'css_base')::numeric = v_base, 'le plafond ne change pas';
  assert (s->'totals'->>'gross_pay') = (s0->'totals'->>'gross_pay') and (s->'totals'->>'net_pay') = (s0->'totals'->>'net_pay'), 'brut et net inchangés';
  assert (s->'totals'->>'employer_charges')::numeric = (s0->'totals'->>'employer_charges')::numeric - v_base * v_default + v_base * 0.03, 'charges patronales';

  -- 3. retour à null : résultat identique au départ
  update public.companies set css_at_rate = null;
  assert public.compute_salary_slip(v_emp, v_p0, v_p1)->'totals' = s0->'totals', 'retour à null : totaux identiques';

  -- 4. contrainte de plage
  begin update public.companies set css_at_rate = 2; assert false, 'taux 200 % accepté';
  exception when check_violation then null; end;

  -- 5. alerte d'agrément : module Intérim actif + société ETT + numéro absent
  insert into public.module_activation(module_id, enabled) values ('soma-mod-services-interim-sn', true)
    on conflict (module_id) do update set enabled = true;
  update public.companies set is_ett = true, ett_agreement_number = null;
  perform set_config('request.jwt.claim.sub', v_u_rh::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where code = 'agrement_ett_manquant';
  assert n = 1, 'alerte attendue : ' || n;
  execute 'reset role';
  update public.companies set ett_agreement_number = '   ';
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where code = 'agrement_ett_manquant';
  assert n = 1, 'un numéro blanc compte comme absent : ' || n;
  execute 'reset role';
  update public.companies set ett_agreement_number = 'AG-TEST-1';
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where code = 'agrement_ett_manquant';
  assert n = 0, 'numéro saisi : plus d''alerte';
  execute 'reset role';
  update public.companies set ett_agreement_number = null, is_ett = false;
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where code = 'agrement_ett_manquant';
  assert n = 0, 'société non ETT : pas d''alerte';
  execute 'reset role';
  update public.companies set is_ett = true;
  update public.module_activation set enabled = false where module_id = 'soma-mod-services-interim-sn';
  execute 'set local role authenticated';
  select count(*) into n from public.legal_alerts() where code = 'agrement_ett_manquant';
  assert n = 0, 'module éteint : pas d''alerte';
  execute 'reset role';
  raise notice 'OK m4_societe_ett_taux_at';
end $$;
rollback;
