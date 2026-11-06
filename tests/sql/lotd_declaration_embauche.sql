-- Lot D : validation refusée si un salarié en 1re paie n'a pas de déclaration d'embauche ; passe une fois la référence saisie. Tout est annulé.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/lotd_declaration_embauche.sql  (attendu : "OK lotd_declaration_embauche")
begin;
create temp table t_ctx as
select (select user_id from public.user_roles where role = 'paie' order by user_id limit 1) as user_paie,
       (select id from public.payroll_entries where status = 'Approuvée' order by period_start limit 1) as entry;
grant select on t_ctx to authenticated;
do $$
declare c record; v_emp uuid; r text;
begin
  select * into c from t_ctx;
  if c.entry is null then raise exception 'Aucune paie Approuvée : test non significatif'; end if;
  select employee_id into v_emp from public.salary_slips where payroll_entry_id = c.entry limit 1;
  -- l'employé n'a plus de bulletin validé antérieur => 1re paie
  set local session_replication_role = replica;  -- les bulletins clôturés sont immuables : préparation hors triggers
  update public.salary_slips set status = 'Brouillon'
   where employee_id = v_emp and payroll_entry_id is distinct from c.entry;
  update public.employees set hire_declaration_ref = null where id = v_emp;
  set local session_replication_role = origin;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', c.user_paie::text, true);
  begin
    perform public.transition_payroll_entry(c.entry, 'Validée', null);
    raise exception 'validation acceptée sans déclaration';
  exception when others then
    if sqlerrm not like '%déclaration d''embauche%' then raise exception 'autre erreur : %', sqlerrm; end if;
  end;
  execute 'reset role';
  update public.employees set hire_declaration_ref = 'TEST' where id in (select employee_id from public.salary_slips where payroll_entry_id = c.entry);
  execute 'set local role authenticated';
  begin
    perform public.transition_payroll_entry(c.entry, 'Validée', null);
  exception when others then  -- une autre garde (ex. mois futur) peut refuser : seul le message d'embauche compte
    if sqlerrm like '%déclaration d''embauche%' then raise exception 'encore refusée : %', sqlerrm; end if;
  end;
  raise notice 'OK lotd_declaration_embauche';
end $$;
rollback;
