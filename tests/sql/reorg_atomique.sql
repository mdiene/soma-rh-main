-- org_apply_reorg : tout ou rien. Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/reorg_atomique.sql (attendu : "OK reorg_atomique") ; tout est annulé.
-- Prérequis : scénario QA chargé et comptes créés.
begin;
create temp table t_ctx as
select (select id from public.employees where employee_number = 'QA0011') as e1,
       (select id from public.employees where employee_number = 'QA0012') as e2,
       (select id from public.employees where employee_number = 'QA0013') as mgr,
       (select id from auth.users where email = 'qa-rh@example.test') as rh;
grant select on t_ctx to authenticated;
do $$
declare c t_ctx; n int; before_cnt int; r text;
begin
  select * into c from t_ctx;
  if c.e1 is null or c.rh is null then raise exception 'FAIL : prérequis QA absents'; end if;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', c.rh::text, true);
  select count(*) into before_cnt from public.employee_manager_assignments where manager_employee_id = c.mgr and valid_from = current_date;
  -- 2e changement invalide (manager inexistant) : le 1er ne doit pas rester appliqué
  begin
    perform public.org_apply_reorg(jsonb_build_array(
      jsonb_build_object('kind','manager','employee',c.e1,'manager',c.mgr),
      jsonb_build_object('kind','manager','employee',c.e2,'manager','00000000-0000-0000-0000-000000000000')), current_date, null);
    raise exception 'FAIL : changement invalide accepté';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  select count(*) into n from public.employee_manager_assignments where manager_employee_id = c.mgr and valid_from = current_date;
  if n <> before_cnt then raise exception 'FAIL : application partielle (% -> %)', before_cnt, n; end if;
  -- lot valide : appliqué en entier
  if public.org_apply_reorg(jsonb_build_array(jsonb_build_object('kind','manager','employee',c.e1,'manager',c.mgr)), current_date, 'Test') <> 1 then
    raise exception 'FAIL : lot valide non appliqué'; end if;
  execute 'reset role';
  raise notice 'OK reorg_atomique';
end $$;
rollback;
