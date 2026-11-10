-- Retour de 20261213090000_connexion_telephone.sql : retire les tables, fonctions et déclencheurs de l'accès par téléphone.
-- Les comptes déjà créés restent dans auth.users (rôle salarie) ; admin_link_employee et claim_first_admin
-- reprennent leur définition d'avant (sans refus des comptes téléphone) .
drop trigger if exists employees_phone_access_phone_change on public.employees;
drop trigger if exists user_roles_phone_access_lock on public.user_roles;
drop table if exists public.phone_access_tokens, public.phone_access_requests, public.phone_access_attempts,
                     public.phone_access_accounts, public.phone_access_settings cascade;
drop function if exists public.phone_access_request(text, text), public.phone_access_open(text, date, text, text),
  public.phone_access_peek(text), public.phone_access_complete(text, uuid), public.phone_access_log_login(text, text),
  public.phone_access_account_status(uuid), public.phone_access_disable(uuid, text, text), public.phone_access_expire(),
  public.phone_access_audit(text, uuid, jsonb), public.phone_access_on_phone_change(), public.phone_access_role_lock(),
  public.phone_access_account_role_check(), public.admin_phone_access_requests(), public.admin_phone_access_accounts(),
  public.admin_phone_access_decide(uuid, boolean, text), public.admin_phone_access_revoke(uuid),
  public.employee_phone_access_status(uuid), public.phone_normalize(text), public.phone_mask(text);

create or replace function public.admin_link_employee(p_user_id uuid, p_employee_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_role(array['admin']) then raise exception 'Réservé aux administrateurs'; end if;
  update public.employees set user_id = null where user_id = p_user_id;
  if p_employee_id is not null then
    update public.employees set user_id = p_user_id where id = p_employee_id;
    insert into public.user_roles(user_id, role) values (p_user_id, 'salarie') on conflict do nothing;
  end if;
end; $$;

create or replace function public.claim_first_admin()
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Authentification requise'; end if;
  if exists (select 1 from public.user_roles where role = 'admin') then return false; end if;
  insert into public.user_roles(user_id, role) values ((select auth.uid()), 'admin');
  return true;
end; $$;

drop function if exists public.phone_access_alerts();
notify pgrst, 'reload schema';
