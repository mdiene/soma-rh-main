-- Suivi des versements de cotisations par caisse : le mois n'est « versé » (échéancier) que si toutes les caisses de l'échéancier sont payées. Tout est annulé à la fin.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/cotisations_versements.sql  (attendu : "OK cotisations_versements")
begin;

do $$
declare v_month date; v_n integer;
begin
  select mois into v_month from public.v_contribution_follow where dans_echeancier group by mois having count(*) = 2 order by mois limit 1;
  if v_month is null then raise notice 'aucun mois à deux caisses d''échéancier : test sans objet'; return; end if;
  delete from public.contribution_payments where month = v_month;

  insert into public.contribution_payment_lines (month, caisse, status, paid_at, payment_mode, reference) values (v_month, 'IPRES', 'Payé', current_date, 'virement', 'VIR-T');
  select count(*) into v_n from public.contribution_payments where month = v_month;
  if v_n <> 0 then raise exception 'mois déclaré versé alors qu''une caisse reste à payer'; end if;

  insert into public.contribution_payment_lines (month, caisse, status, paid_at, payment_mode, reference) values (v_month, 'Caisse de sécurité sociale', 'Payé', current_date, 'chèque', 'CHQ-T');
  select count(*) into v_n from public.contribution_payments where month = v_month;
  if v_n <> 1 then raise exception 'mois non déclaré versé alors que toutes les caisses sont payées'; end if;

  update public.contribution_payment_lines set status = 'À payer', paid_at = null where month = v_month and caisse = 'IPRES';
  select count(*) into v_n from public.contribution_payments where month = v_month;
  if v_n <> 0 then raise exception 'versement non effacé après remise à payer'; end if;

  begin
    insert into public.contribution_payment_lines (month, caisse, status) values (v_month, 'IPM', 'Payé');
    raise exception 'Payé accepté sans date';
  exception when check_violation then null; end;
end $$;

rollback;
select 'OK cotisations_versements';
