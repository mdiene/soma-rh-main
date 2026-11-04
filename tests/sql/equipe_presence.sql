-- Mon équipe : un manager voit le pointage et les prêts (sans montant) de son équipe seulement.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/equipe_presence.sql  (attendu : "OK equipe_presence") ; tout est annulé.
-- Prérequis : scénario QA chargé et comptes créés (scripts/qa-reset-scenario.ps1, scripts/qa-create-users.ps1).
begin;
-- Le manager fictif QA0013 encadre QA0011 ; QA0012 est hors de son équipe.
insert into public.employee_manager_assignments (manager_employee_id, employee_id, valid_from, delegated_by)
select m.id, e.id, current_date - 5, (select id from auth.users where email = 'qa-admin@example.test') from public.employees m, public.employees e
where m.employee_number = 'QA0013' and e.employee_number = 'QA0011'
  and not exists (select 1 from public.employee_manager_assignments x where x.employee_id = e.id and x.valid_to is null);
create temp table t_ctx as
select (select user_id from public.employees where employee_number = 'QA0013') as mgr,
       (select id from public.employees where employee_number = 'QA0011') as mine,
       (select id from public.employees where employee_number = 'QA0012') as other;
grant select on t_ctx to authenticated;

insert into public.attendance (employee_id, attendance_date, status)
select e, current_date - 1, 'Absent' from t_ctx, unnest(array[mine, other]) e
on conflict (employee_id, attendance_date) do update set status = 'Absent';
insert into public.loans (employee_id, label, principal, installments, first_period)
select e, 'Test prêt', 1000, 2, date_trunc('month', current_date)::date from t_ctx, unnest(array[mine, other]) e;
insert into public.loan_installments (loan_id, due_period, amount)
select l.id, date_trunc('month', current_date)::date, 500 from public.loans l where l.label = 'Test prêt';

do $$
declare c t_ctx; n_mine int; n_other int; l_mine int; l_other int;
begin
  select * into c from t_ctx;
  if c.mgr is null or c.other is null then raise exception 'FAIL : prérequis QA absents (manager ou salarié hors équipe)'; end if;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', c.mgr::text, true);
  select count(*) filter (where employee_id = c.mine), count(*) filter (where employee_id = c.other)
    into n_mine, n_other from public.attendance where attendance_date = current_date - 1;
  select count(*) filter (where employee_id = c.mine), count(*) filter (where employee_id = c.other)
    into l_mine, l_other from public.team_loans_summary() where label = 'Test prêt';
  execute 'reset role';
  if n_mine <> 1 then raise exception 'FAIL : le manager ne voit pas le pointage de son équipe'; end if;
  if n_other <> 0 then raise exception 'FAIL : le manager voit le pointage d''un salarié hors équipe'; end if;
  if l_mine <> 1 then raise exception 'FAIL : le manager ne voit pas le prêt de son équipe'; end if;
  if l_other <> 0 then raise exception 'FAIL : le manager voit le prêt d''un salarié hors équipe'; end if;
  execute 'set local role authenticated';
  begin perform 1 from public.loans; if found then raise exception 'FAIL : lecture directe de loans ouverte au manager'; end if;
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  execute 'reset role';
  raise notice 'OK equipe_presence';
end $$;
rollback;
