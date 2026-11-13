-- Alerte « structure à affecter » : (1) un salarié créé sans structure apparaît ; (2) il disparaît dès qu'une structure est affectée ;
-- (3) un compte salarié ne peut pas lire l'alerte. Tout est annulé. Attendu : "OK alerte_structure_a_affecter"
begin;
do $$
declare
  v_rh uuid; v_sal uuid; v_emp jsonb; v_id uuid; n int; v_ok boolean; v_struct uuid;
begin
  select user_id into v_rh from public.user_roles where role in ('rh', 'admin') order by user_id limit 1;
  select e.user_id into v_sal from public.employees e
   where e.user_id is not null and not exists (select 1 from public.user_roles x where x.user_id = e.user_id and x.role in ('rh', 'paie', 'admin')) limit 1;
  select id into v_struct from public.salary_structures limit 1;
  assert v_rh is not null and v_sal is not null and v_struct is not null, 'FAIL : prérequis absents (compte rh, compte salarié, structure)';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_rh::text, true);
  v_emp := public.create_employee_from_wizard(jsonb_build_object('first_name', 'AlerteTest', 'last_name', 'Structure', 'employment_type', 'CDI', 'date_of_joining', current_date::text, 'id_document_number', 'TEST-CNI-ALERTE'), null, null);
  v_id := (v_emp->>'id')::uuid;

  select count(*) into n from public.structure_pending_alerts() a where a.employee_id = v_id and a.code = 'structure_a_affecter';
  assert n = 1, '(1) alerte présente pour le salarié sans structure';

  reset role;
  insert into public.salary_structure_assignments (employee_id, structure_id, from_date, sursalaire, fees, other_fixed, transport_mode, leave_paid_monthly)
  values (v_id, v_struct, current_date, 0, 0, 0, 'Aucun', true);
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_rh::text, true);
  select count(*) into n from public.structure_pending_alerts() a where a.employee_id = v_id;
  assert n = 0, '(2) alerte disparue après affectation';

  perform set_config('request.jwt.claim.sub', v_sal::text, true);
  begin
    perform * from public.structure_pending_alerts();
    v_ok := false;
  exception when others then v_ok := sqlerrm like '%Réservé%'; end;
  assert v_ok, '(3) refusé au salarié';

  raise notice 'OK alerte_structure_a_affecter';
end $$;
rollback;
