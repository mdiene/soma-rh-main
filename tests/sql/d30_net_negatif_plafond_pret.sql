-- D-30/D-53 : net négatif refusé ; prêt trop lourd refusé ; plafond paramétrable par rh/paie/admin. Tout est annulé.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/d30_net_negatif_plafond_pret.sql  (attendu : "OK d30_net_negatif_plafond_pret")
begin;
create temp table t_ctx as
select
  (select user_id from public.user_roles where role = 'admin' order by user_id limit 1) as user_admin,
  (select user_id from public.user_roles where role = 'rh' and user_id not in (select user_id from public.user_roles where role = 'admin') order by user_id limit 1) as user_rh,
  (select user_id from public.user_roles group by user_id having bool_and(role = 'salarie') order by user_id limit 1) as user_sal,
  (select s.employee_id from public.salary_slips s join public.employees e on e.id = s.employee_id
    where e.status = 'Active' and s.gross_pay > 0 order by s.period_start desc limit 1) as emp,
  (select s.id from public.salary_slips s join public.payroll_entries pe on pe.id = s.payroll_entry_id where s.status <> 'Annulé' and pe.status not in ('Clôturée','Annulée') order by s.period_start desc limit 1) as slip;
grant select on t_ctx to authenticated;
create or replace function pg_temp.as_user(p_user uuid) returns void language plpgsql as $$
begin
  execute 'reset role'; execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;
create or replace function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'OK'; exception when others then return sqlerrm; end $$;
do $$
declare c record; r text; v numeric;
begin
  select * into c from t_ctx;
  -- 1. net négatif refusé (superutilisateur : la règle est un trigger)
  execute 'reset role';
  r := pg_temp.try(format('update public.salary_slips set net_pay = -1 where id = %L', c.slip));
  if r not like '%négatif%' then raise exception 'net négatif accepté : %', r; end if;
  -- 2. prêt disproportionné refusé (rh)
  perform pg_temp.as_user(c.user_rh);
  r := pg_temp.try(format('select public.create_loan(%L, ''test'', 50000000, 1, date_trunc(''month'', current_date + interval ''1 year'')::date)', c.emp));
  if r not like '%Retenue mensuelle trop élevée%' then raise exception 'prêt excessif accepté ou autre erreur : %', r; end if;
  -- 3. plafond paramétrable par rh, refusé au salarié
  v := public.set_loan_max_rate(0.25);
  if public.get_loan_max_rate() <> 0.25 then raise exception 'plafond non enregistré'; end if;
  r := pg_temp.try('select public.set_loan_max_rate(1.5)');
  if r not like '%compris entre 0 et 1%' then raise exception 'taux invalide accepté : %', r; end if;
  perform pg_temp.as_user(c.user_sal);
  r := pg_temp.try('select public.set_loan_max_rate(0.9)');
  if r not like '%Droits insuffisants%' then raise exception 'salarié a modifié le plafond : %', r; end if;
  raise notice 'OK d30_net_negatif_plafond_pret';
end $$;
rollback;
