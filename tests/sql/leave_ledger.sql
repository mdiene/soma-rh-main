-- L7 : registre des congés. (1) le solde lu depuis le registre égale l'ancien calcul sur les données de la base ;
-- (2) cycle de vie : attribution, congé approuvé, retour à « Ouverte », suppression ; (3) registre en ajout seul. Tout est annulé.
-- Attendu : "OK leave_ledger"
begin;
do $$
declare
  v_emp uuid; v_type text; n int; bal numeric; b0 numeric; v_la uuid; v_ap uuid; v_year date := date_trunc('year', current_date)::date;
begin
  -- (1) équivalence avec l'ancienne définition (relue ici depuis les tables sources)
  create temp table t_old on commit drop as
  with alloc as (select employee_id, leave_type, sum(days) a from public.leave_allocations where to_date >= date_trunc('year', current_date) group by 1, 2),
       used as (select employee_id, leave_type, sum(total_days) u from public.leave_applications where status = 'Approuvée' and from_date >= date_trunc('year', current_date) group by 1, 2)
  select e.id employee_id, lt.code leave_type, coalesce(a.a, 0) allocated, coalesce(u.u, 0) taken
    from public.employees e cross join public.leave_types lt
    left join alloc a on a.employee_id = e.id and a.leave_type = lt.code left join used u on u.employee_id = e.id and u.leave_type = lt.code
   where e.status = 'Active' and (a.a is not null or u.u is not null);
  select count(*) into n from (
    (select employee_id, leave_type, allocated, taken from t_old except select employee_id, leave_type, allocated, taken from public.v_leave_balances)
    union all
    (select employee_id, leave_type, allocated, taken from public.v_leave_balances except select employee_id, leave_type, allocated, taken from t_old)) d;
  assert n = 0, 'équivalence : ' || n || ' ligne(s) différente(s) entre registre et ancien calcul';

  -- (2) cycle de vie sur un salarié actif et un type de congé
  select e.id into v_emp from public.employees e where e.status = 'Active' order by e.id limit 1;
  select code into v_type from public.leave_types order by code limit 1;
  insert into public.leave_allocations(employee_id, leave_type, from_date, to_date, days) values (v_emp, v_type, v_year, v_year + 364, 1000) returning id into v_la;
  select balance into b0 from public.v_leave_balances where employee_id = v_emp and leave_type = v_type;
  assert b0 is not null, 'solde absent après attribution';
  perform set_config('soma.leave_decision', 'on', true);
  insert into public.leave_applications(employee_id, leave_type, from_date, to_date, status) values (v_emp, v_type, current_date, current_date + 2, 'Approuvée') returning id into v_ap;
  select balance into bal from public.v_leave_balances where employee_id = v_emp and leave_type = v_type;
  assert bal = b0 - 3, 'congé approuvé de 3 jours : attendu ' || (b0 - 3) || ', obtenu ' || bal;
  update public.leave_applications set status = 'Ouverte' where id = v_ap;
  select balance into bal from public.v_leave_balances where employee_id = v_emp and leave_type = v_type;
  assert bal = b0, 'retour à Ouverte : solde rétabli (' || bal || ' au lieu de ' || b0 || ')';
  update public.leave_applications set status = 'Approuvée' where id = v_ap;
  delete from public.leave_applications where id = v_ap;
  select balance into bal from public.v_leave_balances where employee_id = v_emp and leave_type = v_type;
  assert bal = b0, 'suppression du congé : solde rétabli (' || bal || ')';
  -- toutes les écritures d'une source supprimée s'annulent
  select count(*) into n from (select source_id from public.leave_ledger where source_id = v_ap group by 1 having sum(days) <> 0) z;
  assert n = 0, 'écritures du congé non annulées après suppression';

  -- (3) ajout seul
  begin
    update public.leave_ledger set note = 'x' where source_id = v_la;
    raise exception 'FAIL : modification du registre acceptée';
  exception when others then
    assert sqlerrm like '%ajout seul%', 'modification : mauvais message (' || sqlerrm || ')';
  end;
  raise notice 'OK leave_ledger';
end $$;
rollback;
