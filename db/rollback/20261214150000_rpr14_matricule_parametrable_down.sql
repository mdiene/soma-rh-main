-- Retour de RPR-14 : numérotation « S » + 4 chiffres codée en dur, suppression du paramétrage.
create or replace function public.next_employee_number() returns text language plpgsql security definer set search_path to '' as $function$
declare v text;
begin
  loop
    v := 'S' || lpad(nextval('public.employee_number_seq')::text, 4, '0');
    exit when not exists (select 1 from public.employees where upper(employee_number) = v);
  end loop;
  return v;
end;
$function$;
create or replace function public.preview_employee_number() returns text language plpgsql stable security definer set search_path to '' as $function$
declare n bigint; called boolean; v text;
begin
  select last_value, is_called into n, called from public.employee_number_seq;
  if called then n := n + 1; end if;
  loop
    v := 'S' || lpad(n::text, 4, '0');
    exit when not exists (select 1 from public.employees where upper(employee_number) = v);
    n := n + 1;
  end loop;
  return v;
end;
$function$;
create or replace function public.admin_change_employee_number(p_employee_id uuid, p_new_number text, p_reason text) returns text language plpgsql security definer set search_path to '' as $function$
declare v_old text; v_new text := upper(trim(p_new_number));
begin
  if not public.has_role(array['admin']) then raise exception 'Seul un administrateur peut changer un matricule'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Le motif du changement est obligatoire'; end if;
  if v_new !~ '^S[0-9]{4,}$' then raise exception 'Format attendu : S suivi d''au moins 4 chiffres (ex. S0027)'; end if;
  select employee_number into v_old from public.employees where id = p_employee_id for update;
  if v_old is null then raise exception 'Salarié introuvable'; end if;
  if exists (select 1 from public.employees where upper(employee_number) = v_new and id <> p_employee_id) then raise exception 'Le matricule % est déjà attribué', v_new; end if;
  perform set_config('soma.allow_matricule_change', 'on', true);
  update public.employees set employee_number = v_new where id = p_employee_id;
  perform set_config('soma.allow_matricule_change', '', true);
  insert into public.audit_log(table_name, record_id, action, old_data, new_data, reason)
  values ('employees', p_employee_id, 'changement de matricule', jsonb_build_object('employee_number', v_old), jsonb_build_object('employee_number', v_new), trim(p_reason));
  return v_new;
end;
$function$;
drop function if exists public.set_employee_number_settings(text, integer, bigint);
drop function if exists public.get_employee_number_settings();
drop table if exists public.employee_number_settings;
revoke execute on function public.next_employee_number(), public.preview_employee_number(), public.admin_change_employee_number(uuid, text, text) from public, anon;
grant execute on function public.next_employee_number(), public.preview_employee_number(), public.admin_change_employee_number(uuid, text, text) to authenticated, service_role;
notify pgrst, 'reload schema';
