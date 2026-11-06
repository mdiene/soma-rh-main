-- D-49 : paiements et éléments variables d'un mois « Clôturée » refusés ; tout est annulé en fin de test.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/d49_periode_cloturee.sql  (attendu : "OK d49_periode_cloturee")
begin;
create or replace function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'OK'; exception when others then return sqlerrm; end $$;
do $$
declare
  v_entry public.payroll_entries; v_slip uuid; v_emp uuid; r text;
begin
  select * into v_entry from public.payroll_entries where status = U&'Cl\00F4tur\00E9e' order by period_start desc limit 1;
  if v_entry.id is null then raise exception 'Aucune paie clôturée : test non significatif'; end if;
  select s.id, s.employee_id into v_slip, v_emp from public.salary_slips s
    join public.salary_payments p on p.slip_id = s.id where s.payroll_entry_id = v_entry.id limit 1;
  r := pg_temp.try(format('update public.salary_payments set note = ''x'' where slip_id = %L', v_slip));
  if r not like '%immuable%' then raise exception 'UPDATE paiement accepté : %', r; end if;
  r := pg_temp.try(format('delete from public.salary_payments where slip_id = %L', v_slip));
  if r not like '%immuable%' then raise exception 'DELETE paiement accepté : %', r; end if;
  r := pg_temp.try(format('insert into public.payroll_inputs(employee_id, period) values (%L, %L) on conflict (employee_id, period) do update set notes = ''x''', v_emp, v_entry.period_start));
  if r not like '%immuable%' then raise exception 'écriture payroll_inputs acceptée : %', r; end if;
  -- Un mois non clôturé reste modifiable.
  select * into v_entry from public.payroll_entries where status not in (U&'Cl\00F4tur\00E9e', 'Annulée') order by period_start desc limit 1;
  r := pg_temp.try(format('update public.payroll_inputs set notes = notes where period = %L', v_entry.period_start));
  if r <> 'OK' then raise exception 'mois non clôturé refusé à tort : %', r; end if;
  raise notice 'OK d49_periode_cloturee';
end $$;
rollback;
