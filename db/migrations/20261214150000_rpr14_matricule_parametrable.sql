-- RPR-14 : séquence de matricule paramétrable (préfixe, nombre de chiffres, prochain numéro), par l'administrateur, avec journal.
-- Par défaut : « S » et 4 chiffres (S0001), comme avant. Aucun matricule existant n'est modifié.
-- Retour : db/rollback/20261214150000_rpr14_matricule_parametrable_down.sql

create table if not exists public.employee_number_settings (
  id boolean primary key default true check (id),
  prefix text not null default 'S' check (prefix ~ '^[A-Z]{1,6}$'),
  width smallint not null default 4 check (width between 3 and 8),
  updated_by uuid,
  updated_at timestamptz not null default now()
);
comment on table public.employee_number_settings is 'Paramétrage unique de la numérotation des matricules (préfixe, nombre de chiffres). Modifiable par set_employee_number_settings.';
insert into public.employee_number_settings (id) values (true) on conflict (id) do nothing;
alter table public.employee_number_settings enable row level security;
drop policy if exists employee_number_settings_select on public.employee_number_settings;
create policy employee_number_settings_select on public.employee_number_settings for select to authenticated
  using ((select public.has_role(array['rh', 'paie'])));

create or replace function public.next_employee_number()
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
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

create or replace function public.preview_employee_number()
 returns text
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
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

create or replace function public.get_employee_number_settings()
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare s public.employee_number_settings; n bigint; called boolean;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : administrateur, RH ou paie requis';
  end if;
  select * into s from public.employee_number_settings where id;
  select last_value, is_called into n, called from public.employee_number_seq;
  return jsonb_build_object('prefix', s.prefix, 'width', s.width, 'next', case when called then n + 1 else n end, 'example', public.preview_employee_number());
end;
$function$;

-- p_next : prochain numéro de la séquence (null = inchangé) ; un numéro déjà attribué est toujours sauté
create or replace function public.set_employee_number_settings(p_prefix text, p_width integer, p_next bigint default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old jsonb;
begin
  if not public.has_role(array['admin']) then
    raise exception 'Seul un administrateur peut modifier la numérotation des matricules';
  end if;
  p_prefix := upper(trim(coalesce(p_prefix, '')));
  if p_prefix !~ '^[A-Z]{1,6}$' then raise exception 'Le préfixe doit comporter de 1 à 6 lettres majuscules (ex. S, SOMA)'; end if;
  if p_width is null or p_width < 3 or p_width > 8 then raise exception 'Le nombre de chiffres doit être compris entre 3 et 8'; end if;
  if p_next is not null and p_next < 1 then raise exception 'Le prochain numéro doit être supérieur ou égal à 1'; end if;
  v_old := public.get_employee_number_settings();
  update public.employee_number_settings set prefix = p_prefix, width = p_width, updated_by = auth.uid(), updated_at = now() where id;
  if p_next is not null then perform setval('public.employee_number_seq', p_next, false); end if;
  insert into public.audit_events (actor_id, action, resource_type, before_data, after_data)
  values (auth.uid(), 'parametrage_matricule', 'employee_number_settings', v_old,
          jsonb_build_object('prefix', p_prefix, 'width', p_width, 'next', p_next));
  return public.get_employee_number_settings();
end;
$function$;

-- le changement manuel de matricule accepte le préfixe courant (lettres + au moins 3 chiffres)
create or replace function public.admin_change_employee_number(p_employee_id uuid, p_new_number text, p_reason text)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old text; v_new text := upper(trim(p_new_number));
begin
  if not public.has_role(array['admin']) then
    raise exception 'Seul un administrateur peut changer un matricule';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Le motif du changement est obligatoire';
  end if;
  if v_new !~ '^[A-Z]{1,6}[0-9]{3,}$' then
    raise exception 'Format attendu : de 1 à 6 lettres suivies d''au moins 3 chiffres (ex. S0027)';
  end if;
  select employee_number into v_old from public.employees where id = p_employee_id for update;
  if v_old is null then raise exception 'Salarié introuvable'; end if;
  if exists (select 1 from public.employees where upper(employee_number) = v_new and id <> p_employee_id) then
    raise exception 'Le matricule % est déjà attribué', v_new;
  end if;
  perform set_config('soma.allow_matricule_change', 'on', true);
  update public.employees set employee_number = v_new where id = p_employee_id;
  perform set_config('soma.allow_matricule_change', '', true);
  insert into public.audit_log(table_name, record_id, action, old_data, new_data, reason)
  values ('employees', p_employee_id, 'changement de matricule',
          jsonb_build_object('employee_number', v_old), jsonb_build_object('employee_number', v_new), trim(p_reason));
  return v_new;
end;
$function$;

revoke execute on function public.next_employee_number(), public.preview_employee_number(), public.get_employee_number_settings(),
  public.set_employee_number_settings(text, integer, bigint), public.admin_change_employee_number(uuid, text, text) from public, anon;
grant execute on function public.next_employee_number(), public.preview_employee_number(), public.get_employee_number_settings(),
  public.set_employee_number_settings(text, integer, bigint), public.admin_change_employee_number(uuid, text, text) to authenticated, service_role;
notify pgrst, 'reload schema';
