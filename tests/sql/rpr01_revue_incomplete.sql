-- RPR-01 : l'envoi en revue est refusé tant que des salariés attendus n'ont pas de bulletin. Tout est annulé.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/rpr01_revue_incomplete.sql  (attendu : "OK rpr01_revue_incomplete")
begin;
create temp table t_ctx as
select
  (select user_id from public.user_roles where role = 'paie' and user_id not in (select user_id from public.user_roles where role = 'admin') order by user_id limit 1) as user_paie,
  (select company_id from public.payroll_entries limit 1) as company;
grant select on t_ctx to authenticated;
create or replace function pg_temp.as_user(p_user uuid) returns void language plpgsql as $$
begin
  execute 'reset role'; execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;
create or replace function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'OK'; exception when others then return sqlerrm; end $$;
do $$
declare
  c t_ctx; e uuid; r text; n integer;
begin
  select * into c from t_ctx;
  if c.user_paie is null or c.company is null then raise exception 'jeu de données insuffisant (un compte paie seul, une société)'; end if;
  select count(*) into n from public.employees where status in ('Active', 'Left') and date_of_joining <= '2030-01-31' and (relieving_date is null or relieving_date >= '2030-01-01');
  if n < 2 then raise exception 'au moins 2 salariés attendus'; end if;

  -- une paie « Calculée » avec un seul bulletin : les autres salariés n'ont pas été calculés
  perform set_config('soma.payroll_transition', 'on', true);
  insert into public.payroll_entries (company_id, period_start, period_end, status) values (c.company, '2030-01-01', '2030-01-31', 'Calculée') returning id into e;
  insert into public.salary_slips (payroll_entry_id, employee_id, period_start, period_end, status, employee_number, employee_name)
    select e, id, '2030-01-01', '2030-01-31', 'Brouillon', employee_number, last_name from public.employees
     where status in ('Active', 'Left') and date_of_joining <= '2030-01-31' and (relieving_date is null or relieving_date >= '2030-01-01')
     order by employee_number limit 1;

  -- 1. refus, avec le nombre et les noms des salariés sans bulletin
  perform pg_temp.as_user(c.user_paie);
  r := pg_temp.try(format('select public.transition_payroll_entry(%L, ''En revue'')', e));
  if r not like format('Envoi en revue refusé : %s salarié(s) sans bulletin%%', n - 1) then raise exception '1 : refus attendu pour % salarié(s), obtenu : %', n - 1, r; end if;
  if (select status from public.payroll_entries where id = e) <> 'Calculée' then raise exception '1 : statut modifié malgré le refus'; end if;

  -- 2. paie complète : l'envoi en revue passe
  execute 'reset role';
  insert into public.salary_slips (payroll_entry_id, employee_id, period_start, period_end, status, employee_number, employee_name)
    select e, x.id, '2030-01-01', '2030-01-31', 'Brouillon', x.employee_number, x.last_name from public.employees x
     where x.status in ('Active', 'Left') and x.date_of_joining <= '2030-01-31' and (x.relieving_date is null or x.relieving_date >= '2030-01-01')
       and not exists (select 1 from public.salary_slips s where s.payroll_entry_id = e and s.employee_id = x.id);
  perform pg_temp.as_user(c.user_paie);
  r := pg_temp.try(format('select public.transition_payroll_entry(%L, ''En revue'')', e));
  if r <> 'OK' then raise exception '2 : envoi en revue refusé pour une paie complète : %', r; end if;
end $$;
select 'OK rpr01_revue_incomplete';
rollback;
