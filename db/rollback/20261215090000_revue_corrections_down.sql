-- Retour arrière de 20261215090000_revue_corrections : rétablit les définitions antérieures.
CREATE OR REPLACE FUNCTION public.transition_payroll_entry(p_payroll_entry_id uuid, p_target_status text, p_reason text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_entry public.payroll_entries;
  v_allowed boolean := false;
  v_actor uuid := auth.uid();
  v_missing_n integer;
  v_missing_list text;
begin
  select * into v_entry from public.payroll_entries
  where id = p_payroll_entry_id for update;
  if v_entry.id is null then raise exception 'Traitement de paie introuvable'; end if;
  if p_target_status not in ('En revue','Approuvée','Validée','Payée','Clôturée','Réouverte','Annulée') then
    raise exception 'Statut de transition invalide : « % »', p_target_status;
  end if;
  if p_target_status in ('Annulée','Réouverte') and not public.has_role(array['admin']) then
    raise exception 'Seul un administrateur peut annuler ou rouvrir une paie';
  end if;
  if p_target_status in ('Payée','Clôturée') and not public.has_role(array['paie']) then
    raise exception 'Droits insuffisants : rôle « paie » requis pour passer la paie à « % »', p_target_status;
  end if;
  if p_target_status in ('En revue','Validée') and not public.has_role(array['rh','paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis pour passer la paie à « % »', p_target_status;
  end if;
  -- RPR-02 (décision du 09/11/2026) : l'approbation revient à l'administrateur et au détenteur du rôle paie ; le rôle rh n'approuve pas
  if p_target_status = 'Approuvée' and not public.has_role(array['paie']) then
    raise exception 'Droits insuffisants : rôle « paie » ou administrateur requis pour approuver une paie';
  end if;

  if p_target_status = 'En revue' and v_entry.status = 'Calculée' then v_allowed := true; end if;
  if p_target_status = 'Approuvée' and v_entry.status = 'En revue' then v_allowed := true; end if;
  if p_target_status = 'Validée' and v_entry.status in ('Calculée','Approuvée') then v_allowed := true; end if;
  if p_target_status = 'Payée' and v_entry.status = 'Validée' then v_allowed := true; end if;
  if p_target_status = 'Clôturée' and v_entry.status in ('Validée','Payée') then v_allowed := true; end if;
  if p_target_status = 'Réouverte' and v_entry.status = 'Clôturée' and nullif(trim(p_reason), '') is not null then v_allowed := true; end if;
  if p_target_status = 'Annulée' and v_entry.status <> 'Clôturée' then v_allowed := true; end if;
  if not v_allowed then
    if p_target_status = 'Réouverte' and v_entry.status = 'Clôturée' then
      raise exception 'Un motif est obligatoire pour rouvrir une paie clôturée';
    end if;
    raise exception 'Transition interdite : la paie est « % » et ne peut pas passer à « % »', v_entry.status, p_target_status;
  end if;

  -- RPR-01 : pas d'envoi en revue tant que des salariés attendus n'ont pas de bulletin (structure salariale manquante, erreur de calcul)
  -- Mêmes salariés que ceux retenus par run_payroll_batch.
  if p_target_status = 'En revue' then
    select count(*), string_agg(x.employee_number || ' ' || x.employee_name, ', ' order by x.employee_number) filter (where x.rn <= 10)
      into v_missing_n, v_missing_list
      from (select m.employee_number, m.employee_name, row_number() over (order by m.employee_number) as rn
              from public.payroll_missing_employees(p_payroll_entry_id) m) x;
    if v_missing_n > 0 then
      raise exception 'Envoi en revue refusé : % salarié(s) sans bulletin (%). Affectez-leur une structure salariale puis recalculez.',
        v_missing_n, v_missing_list || case when v_missing_n > 10 then ', …' else '' end;
    end if;
  end if;

  -- D-43 : la validation directe d'une paie « Calculée » (sans revue ni approbation) est une dérogation réservée à l'administrateur, motivée
  if p_target_status = 'Validée' and v_entry.status = 'Calculée' then
    if not public.has_role(array['admin']) then
      raise exception 'La paie doit être approuvée (En revue puis Approuvée) avant d''être validée';
    end if;
    if nullif(trim(p_reason), '') is null then
      raise exception 'Validation sans approbation : un motif de dérogation est obligatoire';
    end if;
  end if;

  -- Lot D (C26-09) : à la 1re paie d'un salarié, la déclaration d'embauche doit être référencée
  if p_target_status = 'Validée' then
    perform public.assert_declaration_embauche(p_payroll_entry_id);
  end if;

  -- I4 : le préparateur ne contrôle pas son propre travail (dérogation admin motivée)
  if p_target_status = 'Approuvée' then
    perform public.payroll_assert_separation(v_entry, 'approuver', p_reason);
  elsif p_target_status = 'Validée' and v_entry.status = 'Calculée' then
    perform public.payroll_assert_separation(v_entry, 'valider', p_reason);
  end if;

  perform set_config('soma.payroll_transition', 'on', true);
  if p_target_status = 'Clôturée' then
    perform public.create_payroll_snapshot(p_payroll_entry_id);
    update public.payroll_entries
       set status = p_target_status, closed_by = v_actor, closed_at = now()
     where id = p_payroll_entry_id;
  elsif p_target_status = 'Réouverte' then
    update public.payroll_entries
       set status = p_target_status, reopened_by = v_actor, reopened_at = now(), reopen_reason = p_reason
     where id = p_payroll_entry_id;
  elsif p_target_status = 'Approuvée' then
    update public.payroll_entries
       set status = p_target_status, approved_by = v_actor, approved_at = now()
     where id = p_payroll_entry_id;
  elsif p_target_status = 'Payée' then
    update public.payroll_entries
       set status = p_target_status, paid_by = v_actor, paid_at = now()
     where id = p_payroll_entry_id;
  elsif p_target_status = 'En revue' then
    update public.payroll_entries
       set status = p_target_status, submitted_by = coalesce(submitted_by, v_actor)
     where id = p_payroll_entry_id;
  elsif p_target_status = 'Validée' then
    update public.payroll_entries
       set status = p_target_status, submitted_at = coalesce(submitted_at, now())
     where id = p_payroll_entry_id;
    update public.salary_slips set status = 'Validé'
     where payroll_entry_id = p_payroll_entry_id and status = 'Brouillon';
  else
    update public.payroll_entries set status = p_target_status where id = p_payroll_entry_id;
  end if;
  update public.payroll_periods set status = p_target_status where id = v_entry.period_id;
  if p_target_status = 'Validée' and v_entry.status = 'Calculée' then
    insert into public.audit_events(actor_id, action, resource_type, resource_id, payroll_entry_id, before_data, after_data, reason)
    values (v_actor, 'validation_derogatoire', 'payroll_entry', p_payroll_entry_id, p_payroll_entry_id,
            jsonb_build_object('status', v_entry.status), jsonb_build_object('status', p_target_status), p_reason);
  end if;
  insert into public.audit_events(actor_id, action, resource_type, resource_id, payroll_entry_id, before_data, after_data, reason)
  values (v_actor, 'transition', 'payroll_entry', p_payroll_entry_id, p_payroll_entry_id,
          jsonb_build_object('status', v_entry.status),
          jsonb_build_object('status', p_target_status), p_reason);
  return p_target_status;
end;
$function$;
revoke all on function public.transition_payroll_entry(uuid,text,text) from public, anon, authenticated, service_role;
grant execute on function public.transition_payroll_entry(uuid,text,text) to authenticated;
grant execute on function public.transition_payroll_entry(uuid,text,text) to service_role;
grant execute on function public.transition_payroll_entry(uuid,text,text) to soma;
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
revoke all on function public.run_payroll_batch(uuid,text,uuid[]) from public, anon, authenticated, service_role;
grant execute on function public.run_payroll_batch(uuid,text,uuid[]) to authenticated;
grant execute on function public.run_payroll_batch(uuid,text,uuid[]) to service_role;
grant execute on function public.run_payroll_batch(uuid,text,uuid[]) to soma;
CREATE OR REPLACE FUNCTION public.phone_access_open(p_phone text, p_second date, p_ip_hash text, p_token_hash text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_phone text := public.phone_normalize(p_phone);
  s       public.phone_access_settings;
  r       public.phone_access_requests;
  e       public.employees;
  v_fails integer;
begin
  perform public.phone_access_expire();
  select * into s from public.phone_access_settings;
  if v_phone is null then return false; end if;
  -- 30 ouvertures par adresse et par heure
  if (select count(*) from public.phone_access_attempts
       where kind = 'open' and ip_hash = p_ip_hash and occurred_at > now() - interval '1 hour') >= 30 then
    return false;
  end if;
  insert into public.phone_access_attempts (kind, phone_e164, ip_hash) values ('open', v_phone, p_ip_hash);
  -- Verrou du numéro : 5 mauvaises secondes informations, 30 minutes
  select count(*) into v_fails from public.phone_access_attempts
   where kind = 'second_factor_fail' and phone_e164 = v_phone and occurred_at > now() - interval '30 minutes';
  if v_fails >= 5 then return false; end if;

  select * into r from public.phone_access_requests
   where phone_e164 = v_phone and status = 'authorized' and expires_at > now() and employee_id is not null;
  if not found then return false; end if;
  select * into e from public.employees where id = r.employee_id;
  if e.status <> 'Active' or public.phone_normalize(e.phone_personal) is distinct from v_phone then return false; end if;

  if s.second_factor and (p_second is null or e.date_of_birth is distinct from p_second) then
    insert into public.phone_access_attempts (kind, phone_e164, ip_hash) values ('second_factor_fail', v_phone, p_ip_hash);
    perform public.phone_access_audit('seconde information incorrecte', e.id, '{}');
    if v_fails + 1 >= 5 then
      perform public.phone_access_audit('verrouillage du numéro (30 min)', e.id, '{}');
    end if;
    return false;
  end if;

  delete from public.phone_access_attempts where kind = 'second_factor_fail' and phone_e164 = v_phone;
  insert into public.phone_access_tokens (token_hash, request_id, expires_at)
  values (p_token_hash, r.id, now() + interval '15 minutes');
  perform public.phone_access_audit('activation ouverte', e.id, '{}');
  return true;
end;
$function$;
revoke all on function public.phone_access_open(text,date,text,text) from public, anon, authenticated, service_role;
grant execute on function public.phone_access_open(text,date,text,text) to service_role;
grant execute on function public.phone_access_open(text,date,text,text) to soma;
CREATE OR REPLACE FUNCTION public.next_employee_number()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v text; s public.employee_number_settings;
begin
  select * into s from public.employee_number_settings where id;
  loop
    v := coalesce(s.prefix, 'S') || lpad(nextval('public.employee_number_seq')::text, coalesce(s.width, 4), '0');
    exit when not exists (select 1 from public.employees where upper(employee_number) = v);
  end loop;
  return v;
end;
$function$;
revoke all on function public.next_employee_number() from public, anon, authenticated, service_role;
grant execute on function public.next_employee_number() to authenticated;
grant execute on function public.next_employee_number() to service_role;
grant execute on function public.next_employee_number() to soma;
CREATE OR REPLACE FUNCTION public.preview_employee_number()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n bigint; called boolean; v text; s public.employee_number_settings;
begin
  select * into s from public.employee_number_settings where id;
  select last_value, is_called into n, called from public.employee_number_seq;
  if called then n := n + 1; end if;
  loop
    v := coalesce(s.prefix, 'S') || lpad(n::text, coalesce(s.width, 4), '0');
    exit when not exists (select 1 from public.employees where upper(employee_number) = v);
    n := n + 1;
  end loop;
  return v;
end;
$function$;
revoke all on function public.preview_employee_number() from public, anon, authenticated, service_role;
grant execute on function public.preview_employee_number() to authenticated;
grant execute on function public.preview_employee_number() to service_role;
grant execute on function public.preview_employee_number() to soma;
