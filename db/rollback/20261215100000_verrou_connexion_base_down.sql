drop function if exists public.login_lock_retry_after(text), public.login_lock_fail(text, integer, integer, integer), public.login_lock_success(text);
drop table if exists public.login_attempts;
create or replace function public.phone_access_role_lock()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.role <> 'salarie' and exists (select 1 from public.phone_access_accounts where user_id = new.user_id) then
    raise exception 'Un compte connecté par téléphone ne peut avoir que le rôle salarié (créez un compte e-mail distinct pour un autre rôle)'
      using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke all on function public.phone_access_role_lock() from public, anon, authenticated;
notify pgrst, 'reload schema';
