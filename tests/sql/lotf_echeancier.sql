-- Lot F : échéances, majoration de retard, alerte COT-ECHEANCE résolue par un versement. Tout est annulé.
-- Attendu : "OK lotf_echeancier"
begin;
create temp table t_ctx as
select (select user_id from public.user_roles where role = 'paie' order by user_id limit 1) as user_paie;
grant select on t_ctx to authenticated;
do $$
declare c record; n int; m date;
begin
  select * into c from t_ctx;
  assert public.echeance_cotisations(date '2026-07-01', 125) = date '2026-08-15', 'échéance mensuelle';
  assert public.echeance_cotisations(date '2026-07-01', 10)  = date '2026-10-15', 'échéance trimestrielle';
  assert public.majoration_retard_cotisations(1000, date '2026-08-15', date '2026-08-15') = 0, 'à l''échéance';
  assert public.majoration_retard_cotisations(1000, date '2026-08-15', date '2026-08-16') = 100, '1 jour de retard = 10 %';
  assert public.majoration_retard_cotisations(1000, date '2026-08-15', date '2027-01-01') = 500, 'plafond 50 %';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', c.user_paie::text, true);
  select mois into m from public.v_echeancier_cotisations where paye_le is null order by mois limit 1;
  perform public.detecter_conformite();
  select count(*) into n from public.compliance_findings where rule_id = 'COT-ECHEANCE' and resolved_on is null;
  assert n > 0, 'aucune alerte COT-ECHEANCE';
  insert into public.contribution_payments(month, paid_on, amount) values (m, current_date, 1);
  perform public.detecter_conformite();
  assert (select count(*) from public.compliance_findings where rule_id = 'COT-ECHEANCE' and resolved_on is null) = n - 1, 'le versement n''a pas résolu l''alerte';
  raise notice 'OK lotf_echeancier';
end $$;
rollback;
