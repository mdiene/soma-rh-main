-- RPR-05 : recalcul d'une paie « Réouverte » (les bulletins validés repassent en brouillon avant le recalcul).
-- Retour : db/rollback/20261214100000_rpr05_recalcul_paie_rouverte_down.sql

CREATE OR REPLACE FUNCTION public.run_payroll_batch(p_payroll_entry_id uuid, p_employment_type text DEFAULT NULL::text, p_employee_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  pe       public.payroll_entries;
  emp      record;
  v_done   int := 0;
  v_synced int := 0;
  v_errors jsonb := '[]'::jsonb;
begin
  if not public.has_role(array['paie','rh']) then
    raise exception 'Droits insuffisants : rôle « paie » ou « rh » requis';
  end if;
  select * into pe from public.payroll_entries where id = p_payroll_entry_id for update;
  if pe.id is null then raise exception 'Traitement de paie introuvable'; end if;
  if pe.status in ('Validée','Annulée') then
    raise exception 'Le traitement est % : recalcul impossible', pe.status;
  end if;

  -- RPR-05 : une paie rouverte repart de bulletins en brouillon ; sans cela chaque bulletin validé refuse le recalcul
  -- (« Un bulletin validé existe déjà ») et l'erreur passait inaperçue.
  if pe.status = 'Réouverte' then
    perform set_config('soma.payroll_transition', 'on', true);
    update public.salary_slips set status = 'Brouillon' where payroll_entry_id = pe.id and status = 'Validé';
  end if;

  v_synced := public.sync_attendance_to_payroll_inputs(pe.period_start);
  perform public.apply_period_adjustments(pe.id);

  for emp in
    select e.id, e.employee_number, e.last_name
    from public.employees e
    where e.company_id = pe.company_id
      and e.status in ('Active','Left')
      and e.date_of_joining <= pe.period_end
      and (e.relieving_date is null or e.relieving_date >= pe.period_start)
      and (p_employment_type is null or e.employment_type = p_employment_type)
      and (p_employee_ids is null or e.id = any(p_employee_ids))
    order by e.employee_number
  loop
    begin
      perform public.calculate_salary_slip(emp.id, pe.period_start, pe.period_end, pe.id);
      v_done := v_done + 1;
    exception when others then
      v_errors := v_errors || jsonb_build_object('employee_number', emp.employee_number,
                                                 'name', emp.last_name, 'error', sqlerrm);
    end;
  end loop;

  update public.payroll_entries set status = 'Calculée' where id = pe.id;
  return jsonb_build_object('calculated', v_done, 'errors', v_errors, 'attendance_synced', v_synced);
end;
$function$;

revoke execute on function public.run_payroll_batch(uuid, text, uuid[]) from public, anon;
grant execute on function public.run_payroll_batch(uuid, text, uuid[]) to authenticated, service_role;
notify pgrst, 'reload schema';
