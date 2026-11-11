-- 1. Verrou de connexion persistant : compteur par clé hachée (compte + adresse), en base et non plus en mémoire de la passerelle
--    (le verrou survit au redémarrage et se partage entre instances). 5 échecs -> 1 min, puis 2, 4, 8, 16, 30 min (plafond).
-- 2. Message explicite quand on veut donner un rôle autre que salarié à un compte connecté par téléphone (organigramme : manager).

create table if not exists public.login_attempts (
  key_hash     text primary key,
  failures     integer     not null default 0,
  lock_level   integer     not null default 0,
  locked_until timestamptz not null default 'epoch',
  updated_at   timestamptz not null default now()
);
create index if not exists login_attempts_updated_idx on public.login_attempts (updated_at);
alter table public.login_attempts enable row level security; -- aucune politique : accessible à la seule passerelle (propriétaire / service_role)
revoke all on public.login_attempts from public, anon, authenticated;

-- Secondes restantes avant la fin du verrou, 0 si libre.
create or replace function public.login_lock_retry_after(p_key text)
returns integer language sql stable security definer set search_path = '' as $$
  select coalesce((select greatest(0, ceil(extract(epoch from locked_until - now()))::integer)
                     from public.login_attempts where key_hash = p_key), 0)
$$;

-- Enregistre un échec ; renvoie true si cet échec déclenche un verrou.
create or replace function public.login_lock_fail(p_key text, p_max integer default 5, p_base_seconds integer default 60, p_cap_seconds integer default 1800)
returns boolean language plpgsql security definer set search_path = '' as $$
declare r public.login_attempts; v_locked boolean := false;
begin
  delete from public.login_attempts where updated_at < now() - interval '1 day' and locked_until < now(); -- purge
  insert into public.login_attempts (key_hash, failures) values (p_key, 0) on conflict (key_hash) do nothing;
  select * into r from public.login_attempts where key_hash = p_key for update;
  r.failures := r.failures + 1;
  if r.failures >= p_max then
    r.locked_until := now() + make_interval(secs => least(p_base_seconds * power(2, r.lock_level), p_cap_seconds));
    r.lock_level := r.lock_level + 1;
    r.failures := 0;
    v_locked := true;
  end if;
  update public.login_attempts set failures = r.failures, lock_level = r.lock_level, locked_until = r.locked_until, updated_at = now() where key_hash = p_key;
  return v_locked;
end $$;

create or replace function public.login_lock_success(p_key text)
returns void language sql security definer set search_path = '' as $$
  delete from public.login_attempts where key_hash = p_key
$$;

revoke all on function public.login_lock_retry_after(text) from public, anon, authenticated;
revoke all on function public.login_lock_fail(text, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.login_lock_success(text) from public, anon, authenticated;
grant execute on function public.login_lock_retry_after(text), public.login_lock_fail(text, integer, integer, integer), public.login_lock_success(text) to service_role;

create or replace function public.phone_access_role_lock()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.role <> 'salarie' and exists (select 1 from public.phone_access_accounts where user_id = new.user_id) then
    raise exception 'Ce salarié se connecte par téléphone : il ne peut pas recevoir le rôle « % » (manager, rh, paie…). Créez-lui un compte e-mail (Paramètres > Accès) puis recommencez.', new.role
      using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke all on function public.phone_access_role_lock() from public, anon, authenticated;
notify pgrst, 'reload schema';
