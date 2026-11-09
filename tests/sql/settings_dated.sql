-- T-I14 / RL-018 : les paramètres légaux sont lus à la date de fin de période (payroll_settings_at).
-- Un taux daté du premier mois libre (après la dernière paie calculée, cf. L1a) ne touche pas le mois précédent et s'applique au mois visé.
-- Indépendant de l'état de la base : le mois visé est calculé, il n'est pas écrit en dur. Transaction annulée.
begin;
do $$
declare
  e uuid; s public.payroll_settings; avant jsonb; apres jsonb; mois jsonb;
  m_start date := coalesce(public.parameters_min_effective_date(), date '2026-12-01');
  m_end date; p_start date; p_end date;
begin
  m_end := (m_start + interval '1 month - 1 day')::date;
  p_start := (m_start - interval '1 month')::date;
  p_end := m_start - 1;
  select id into e from public.employees where employee_number = 'QA0003';
  if e is null then raise exception 'FAIL : chargez d''abord un scénario (scripts/qa-reset-scenario.ps1)'; end if;
  select * into s from public.payroll_settings_at(p_end);
  avant := public.compute_salary_slip(e, p_start, p_end, 0);

  insert into public.payroll_settings select (jsonb_populate_record(s, jsonb_build_object(
      'id', gen_random_uuid(), 'effective_from', m_start, 'cfce_rate', 0.05, 'css_af_rate', 0.08))).*;

  apres := public.compute_salary_slip(e, p_start, p_end, 0);   -- mois précédent : inchangé
  mois  := public.compute_salary_slip(e, m_start, m_end, 0);   -- mois visé : nouveau taux

  if apres->'totals'->>'css_af' is null or mois->'totals'->>'css_af' is null then raise exception 'FAIL : css_af absent du résultat (test non significatif)'; end if;
  if apres is distinct from avant then raise exception 'FAIL : le mois précédent % est modifié par un taux daté du %', p_start, m_start; end if;
  if (mois->'totals'->>'css_af')::numeric = (apres->'totals'->>'css_af')::numeric then
    raise exception 'FAIL : le nouveau taux d''allocations familiales n''est pas appliqué en % (% = %)', m_start, mois->'totals'->>'css_af', apres->'totals'->>'css_af';
  end if;
  if (mois->'totals'->>'css_af')::numeric <> round((mois->'totals'->>'css_base')::numeric * 0.08, 2) then
    raise exception 'FAIL : css_af du mois visé = %, attendu base x 8 %%', mois->'totals'->>'css_af';
  end if;
  raise notice 'OK settings_dated (css_af % -> %)', apres->'totals'->>'css_af', mois->'totals'->>'css_af';
end $$;
rollback;
