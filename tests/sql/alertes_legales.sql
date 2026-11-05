-- legal_alerts : détecte un CDD échu, un salaire sous le SMIG paramétré, une pièce expirée ; refuse les autres rôles.
-- Tout est fait dans une transaction annulée (aucune donnée modifiée).
begin;
do $$
declare uid uuid; suid uuid; emp uuid; n int; smic numeric;
begin
  select ur.user_id into uid from public.user_roles ur where ur.role = 'rh' and not exists (select 1 from public.user_roles o where o.user_id = ur.user_id and o.role = 'admin') limit 1;
  if uid is null then raise exception 'FAIL : aucun compte rh (lancer qa-create-users)'; end if;
  select ur.user_id into suid from public.user_roles ur where ur.role = 'salarie' and not exists (select 1 from public.user_roles o where o.user_id = ur.user_id and o.role <> 'salarie') limit 1;
  if suid is null then raise exception 'FAIL : aucun compte salarié seul'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', uid::text, 'role', 'authenticated')::text, true);
  set local role authenticated;

  select e.id into emp from public.employees e where e.status = 'Active' and e.employee_number like 'QA%' order by e.employee_number limit 1;
  select s.smig_hourly * s.monthly_hours into smic from public.payroll_settings_at(current_date) s;

  -- CDD échu + pièce expirée
  reset role;
  update public.employees set employment_type = 'CDD', contract_end = current_date - 3, id_expiry_date = current_date - 1 where id = emp;
  insert into public.salary_structure_assignments (employee_id, structure_id, from_date, base_salary, transport_mode)
    values (emp, (select id from public.salary_structures limit 1), current_date, smic - 1000, 'Aucun');
  perform set_config('request.jwt.claims', json_build_object('sub', uid::text, 'role', 'authenticated')::text, true);
  set local role authenticated;

  select count(*) into n from public.legal_alerts() where employee_id = emp and code = 'cdd_echu' and severity = 'erreur';
  if n <> 1 then raise exception 'FAIL : CDD échu non détecté (%)', n; end if;
  select count(*) into n from public.legal_alerts() where employee_id = emp and code = 'sous_smig';
  if n <> 1 then raise exception 'FAIL : salaire sous le SMIG non détecté (%)', n; end if;
  select count(*) into n from public.legal_alerts() where employee_id = emp and code = 'piece_expiree';
  if n <> 1 then raise exception 'FAIL : pièce expirée non détectée (%)', n; end if;

  -- un salarié ne peut pas appeler la fonction
  perform set_config('request.jwt.claims', json_build_object('sub', suid::text, 'role', 'authenticated')::text, true);
  begin
    perform * from public.legal_alerts();
    raise exception 'FAIL : un salarié a pu lire les alertes';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'OK alertes_legales';
end $$;
rollback;
