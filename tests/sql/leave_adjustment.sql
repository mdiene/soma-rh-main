-- L7 : ajustement manuel d'un solde de congés. RH seule ; motif obligatoire ; jours non nuls ; effet sur le solde ; ajout seul. Tout est annulé.
-- Attendu : "OK leave_adjustment"
begin;
do $$
declare
  v_rh uuid; v_paie uuid; v_emp uuid; v_type text; b0 numeric; b1 numeric; n int; v_id uuid;
begin
  select user_id into v_rh from public.user_roles where role = 'rh' order by user_id limit 1;
  select user_id into v_paie from public.user_roles r where role = 'paie'
    and not exists (select 1 from public.user_roles x where x.user_id = r.user_id and x.role in ('rh', 'admin')) order by user_id limit 1;
  select e.id into v_emp from public.employees e where e.status = 'Active' order by e.id limit 1;
  select code into v_type from public.leave_types order by code limit 1;
  assert v_rh is not null and v_emp is not null, 'données de test manquantes';

  -- une attribution de départ pour que la ligne de solde existe
  insert into public.leave_allocations(employee_id, leave_type, from_date, to_date, days)
    values (v_emp, v_type, date_trunc('year', current_date)::date, date_trunc('year', current_date)::date + 364, 10);
  select balance into b0 from public.v_leave_balances where employee_id = v_emp and leave_type = v_type;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_rh::text, true);
  v_id := public.adjust_leave_balance(v_emp, v_type, 2.5, current_date, 'Régularisation de test');
  select balance into b1 from public.v_leave_balances where employee_id = v_emp and leave_type = v_type;
  assert b1 = b0 + 2.5, 'ajustement +2,5 : attendu ' || (b0 + 2.5) || ', obtenu ' || b1;
  perform public.adjust_leave_balance(v_emp, v_type, -2.5, current_date, 'Correction de l''ajustement');
  select balance into b1 from public.v_leave_balances where employee_id = v_emp and leave_type = v_type;
  assert b1 = b0, 'ajustement inverse : solde rétabli (' || b1 || ')';

  -- refus : zéro, motif court, motif absent
  begin perform public.adjust_leave_balance(v_emp, v_type, 0, current_date, 'Motif valable'); raise exception 'FAIL zéro accepté';
  exception when others then assert sqlerrm like '%invalide%', 'zéro : ' || sqlerrm; end;
  begin perform public.adjust_leave_balance(v_emp, v_type, 1, current_date, 'abc'); raise exception 'FAIL motif court accepté';
  exception when others then assert sqlerrm like '%motif%', 'motif court : ' || sqlerrm; end;
  begin perform public.adjust_leave_balance(v_emp, v_type, 1, current_date, null); raise exception 'FAIL motif nul accepté';
  exception when others then assert sqlerrm like '%motif%', 'motif nul : ' || sqlerrm; end;

  -- la paie ne peut pas ajuster
  if v_paie is not null then
    perform set_config('request.jwt.claim.sub', v_paie::text, true);
    begin perform public.adjust_leave_balance(v_emp, v_type, 1, current_date, 'Tentative de la paie'); raise exception 'FAIL paie acceptée';
    exception when others then assert sqlerrm like '%Droits insuffisants%', 'paie : ' || sqlerrm; end;
  end if;
  execute 'reset role';

  -- la trace : écritures manuelles, motif conservé
  select count(*) into n from public.leave_ledger where source_table = 'manual' and employee_id = v_emp and note in ('Régularisation de test', 'Correction de l''ajustement');
  assert n = 2, 'écritures manuelles tracées : ' || n;
  raise notice 'OK leave_adjustment';
end $$;
rollback;
