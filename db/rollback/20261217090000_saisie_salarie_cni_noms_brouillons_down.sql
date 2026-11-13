-- Retour arrière de 20261217090000
drop table if exists public.employee_drafts;
drop index if exists public.employees_id_document_uidx;
drop trigger if exists employees_normalize_names on public.employees;
drop function if exists public.employees_normalize_names();
drop function if exists public.person_name(text);
alter table public.employees drop column if exists maiden_name, drop column if exists mother_first_name, drop column if exists mother_last_name;

-- ancienne version de la création par l'assistant
CREATE OR REPLACE FUNCTION public.create_employee_from_wizard(p_employee jsonb, p_assignment jsonb DEFAULT NULL::jsonb, p_receipts text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if not public.has_role(array['rh']) then
    raise exception 'Droits insuffisants : administrateur ou RH requis pour créer un salarié';
  end if;
  if p_assignment is not null and not public.has_role(array['paie']) then
    raise exception 'Droits insuffisants : l''affectation de la structure salariale relève de la paie ou d''un administrateur';
  end if;
  perform pg_advisory_xact_lock(hashtext('employee_number_seq'));
  v := public.wizard_insert_employee(p_employee, p_assignment, p_receipts);
  insert into public.audit_events (actor_id, action, resource_type, resource_id, after_data, reason)
  values (auth.uid(), 'creation_salarie_assistant', 'employee', (v->>'id')::uuid,
          jsonb_build_object('employee_number', v->>'employee_number', 'structure_assigned', v->'structure_assigned', 'pieces_recues', coalesce(array_length(p_receipts, 1), 0)),
          'Création par l''assistant de saisie');
  return v;
end;
$function$;
revoke all on function public.create_employee_from_wizard(jsonb, jsonb, text[]) from public, anon;
grant execute on function public.create_employee_from_wizard(jsonb, jsonb, text[]) to authenticated, service_role;
notify pgrst, 'reload schema';
