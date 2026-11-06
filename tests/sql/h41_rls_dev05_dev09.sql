-- H41 : RLS des tables recrutement / formation / évaluation / notifications. Tout est annulé.
-- Attendu : "OK h41_rls_dev05_dev09"
begin;
create temp table t_ctx as
select (select user_id from public.user_roles where role = 'rh' and user_id not in (select user_id from public.user_roles where role = 'admin') order by user_id limit 1) as u_rh,
       (select user_id from public.user_roles where role = 'paie' and user_id not in (select user_id from public.user_roles where role in ('rh','admin')) order by user_id limit 1) as u_paie,
       (select e.user_id from public.employees e where e.user_id is not null
          and not exists (select 1 from public.user_roles r where r.user_id = e.user_id and r.role in ('rh','paie','admin')) order by e.id limit 1) as u_sal,
       (select e.user_id from public.employees e where e.user_id is not null
          and not exists (select 1 from public.user_roles r where r.user_id = e.user_id and r.role in ('rh','paie','admin')) order by e.id offset 1 limit 1) as u_sal2;
grant select on t_ctx to authenticated;
create or replace function pg_temp.as_user(p_user uuid) returns void language plpgsql as $$
begin execute 'reset role'; execute 'set local role authenticated'; perform set_config('request.jwt.claim.sub', p_user::text, true); end $$;
create or replace function pg_temp.n(p_sql text) returns bigint language plpgsql as $$
declare r bigint; begin execute p_sql into r; return r; end $$;
create or replace function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'OK'; exception when others then return sqlerrm; end $$;
do $$
declare c record; v_emp uuid; v_emp2 uuid; r text;
begin
  select * into c from t_ctx;
  if c.u_rh is null or c.u_paie is null or c.u_sal is null or c.u_sal2 is null then raise exception 'utilisateurs de test manquants : %', c; end if;
  select id into v_emp  from public.employees where user_id = c.u_sal;
  select id into v_emp2 from public.employees where user_id = c.u_sal2;
  -- RH écrit
  perform pg_temp.as_user(c.u_rh);
  insert into public.trainings(employee_id, title, start_date, end_date) values (v_emp, 'T1', current_date, current_date), (v_emp2, 'T2', current_date, current_date);
  insert into public.evaluations(employee_id, evaluator, period) values (v_emp, 'X', '2026');
  insert into public.job_postulations(employee_id, job_title) values (v_emp, 'Poste');
  insert into public.notifications_log(user_id, type, title, message) values (c.u_sal, 'sms', 'a', 'b'), (c.u_sal2, 'sms', 'a', 'b');
  -- salarié : ses lignes seulement, pas d'évaluation ni d'offre, pas d'écriture
  perform pg_temp.as_user(c.u_sal);
  if pg_temp.n('select count(*) from public.trainings') <> 1 then raise exception 'salarié : formations visibles <> 1'; end if;
  if pg_temp.n('select count(*) from public.notifications_log') <> 1 then raise exception 'salarié : notifications visibles <> 1'; end if;
  if pg_temp.n('select count(*) from public.evaluations') <> 0 then raise exception 'salarié voit des évaluations'; end if;
  if pg_temp.n('select count(*) from public.job_postulations') <> 0 then raise exception 'salarié voit des offres'; end if;
  r := pg_temp.try('insert into public.trainings(employee_id, title, start_date, end_date) values ((select id from public.employees limit 1), ''x'', current_date, current_date)');
  if r = 'OK' then raise exception 'salarié a pu insérer une formation'; end if;
  -- paie : notifications oui, évaluations / formations non
  perform pg_temp.as_user(c.u_paie);
  if pg_temp.n('select count(*) from public.notifications_log') < 2 then raise exception 'paie ne voit pas les notifications'; end if;
  if pg_temp.n('select count(*) from public.evaluations') <> 0 then raise exception 'paie voit des évaluations'; end if;
  if pg_temp.n('select count(*) from public.trainings') <> 0 then raise exception 'paie voit des formations'; end if;
  raise notice 'OK h41_rls_dev05_dev09';
end $$;
rollback;
