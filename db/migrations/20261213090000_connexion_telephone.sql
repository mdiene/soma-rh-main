-- =============================================================================
-- Connexion des salariés par numéro de téléphone, autorisation par l'administrateur (SMS plus tard).
-- Décision : docs/DECISION_CONNEXION_TELEPHONE.md. Retour : db/rollback/20261213090000_connexion_telephone_down.sql
--
--  * Un salarié demande l'accès avec son numéro ; l'administrateur l'autorise (48 h, usage unique) ;
--    le salarié rouvre l'activation (numéro + date de naissance) puis crée son mot de passe (5 à 8 lettres/chiffres).
--  * Les fonctions « phone_access_* » sont appelées par la passerelle (local) ou la fonction Edge (en ligne),
--    jamais par le navigateur : exécutables par service_role / postgres seulement.
--  * Les tables ne sont lisibles par aucun rôle applicatif (RLS activée, aucune politique) :
--    l'administrateur passe par les fonctions admin_phone_access_*.
--  * Verrou de rôle : un compte téléphone ne peut avoir que le rôle « salarie » (déclencheur sur user_roles).
-- =============================================================================

-- ---------------------------------------------------------------- paramètres
create table public.phone_access_settings (
  id                  boolean primary key default true check (id),
  validation          text    not null default 'admin' check (validation in ('admin', 'sms')),  -- 'sms' : non implémenté
  second_factor       boolean not null default true,
  authorization_hours integer not null default 48 check (authorization_hours between 1 and 168),
  updated_at          timestamptz not null default now()
);
insert into public.phone_access_settings default values;
alter table public.phone_access_settings enable row level security;
create policy phone_access_settings_admin on public.phone_access_settings for all to authenticated
  using ((select public.has_role(array['admin']))) with check ((select public.has_role(array['admin'])));

-- ------------------------------------------------------------------ demandes
create table public.phone_access_requests (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid references public.employees(id) on delete cascade,   -- vide pour un « numéro partagé »
  phone_e164     text not null,
  purpose        text not null check (purpose in ('signup', 'reset', 'shared')),
  status         text not null default 'pending'
                 check (status in ('pending', 'authorized', 'refused', 'used', 'revoked', 'expired')),
  requested_at   timestamptz not null default now(),
  repeat_count   integer not null default 0,
  decided_by     uuid references auth.users(id) on delete set null,
  decided_at     timestamptz,
  decision_note  text,
  expires_at     timestamptz,
  used_at        timestamptz
);
create index phone_access_requests_employee_idx on public.phone_access_requests (employee_id);
create index phone_access_requests_decided_by_idx on public.phone_access_requests (decided_by);
create index phone_access_requests_status_idx on public.phone_access_requests (status, requested_at desc);
create unique index phone_access_requests_open_uidx on public.phone_access_requests (employee_id)
  where status in ('pending', 'authorized');

-- Jetons d'installation (15 min, usage unique, stockés hachés)
create table public.phone_access_tokens (
  token_hash  text primary key,
  request_id  uuid not null references public.phone_access_requests(id) on delete cascade,
  expires_at  timestamptz not null,
  used_at     timestamptz
);
create index phone_access_tokens_request_idx on public.phone_access_tokens (request_id);

-- Comptes téléphone (un salarié = un compte = un numéro)
create table public.phone_access_accounts (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  employee_id  uuid not null unique references public.employees(id) on delete cascade,
  phone_e164   text not null unique,
  status       text not null default 'active' check (status in ('active', 'disabled', 'revoked')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Tentatives (limites par numéro et par adresse, hachée)
create table public.phone_access_attempts (
  id           bigint generated always as identity primary key,
  kind         text not null check (kind in ('request', 'open', 'second_factor_fail')),
  phone_e164   text,
  ip_hash      text,
  occurred_at  timestamptz not null default now()
);
create index phone_access_attempts_phone_idx on public.phone_access_attempts (kind, phone_e164, occurred_at);
create index phone_access_attempts_ip_idx on public.phone_access_attempts (kind, ip_hash, occurred_at);

alter table public.phone_access_requests enable row level security;
alter table public.phone_access_tokens   enable row level security;
alter table public.phone_access_accounts enable row level security;
alter table public.phone_access_attempts enable row level security;
revoke all on public.phone_access_requests, public.phone_access_tokens,
              public.phone_access_accounts, public.phone_access_attempts from public, anon, authenticated;
revoke all on public.phone_access_settings from public, anon;
grant select, update on public.phone_access_settings to authenticated;

-- ---------------------------------------------------------------- utilitaires
-- Forme normalisée +221XXXXXXXXX (mobiles 70, 75, 76, 77, 78) ; null si le numéro n'est pas valide.
create or replace function public.phone_normalize(p_phone text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when n ~ '^(70|75|76|77|78)[0-9]{7}$' then '+221' || n end
  from (select case
          when v ~ '^(\+|00)?221[0-9]{9}$' then right(v, 9)
          when v ~ '^[0-9]{9}$' then v
        end as n
        from (select regexp_replace(coalesce(p_phone, ''), '[\s.\-()]', '', 'g') as v) s) t;
$$;

create index employees_phone_normalized_idx on public.employees (public.phone_normalize(phone_personal));

create or replace function public.phone_mask(p_phone text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_phone ~ '^\+221[0-9]{9}$'
              then '+221 ' || substr(p_phone, 5, 2) || ' ••• •• ' || right(p_phone, 2) end;
$$;

create or replace function public.phone_access_audit(p_action text, p_employee_id uuid, p_data jsonb default '{}')
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.audit_log (table_name, record_id, record_key, action, new_data)
  values ('phone_access', p_employee_id, (select employee_number from public.employees where id = p_employee_id), p_action, p_data);
$$;

-- Les autorisations non utilisées au bout de 48 h passent à « expirée » (journalisé).
create or replace function public.phone_access_expire()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare r record;
begin
  for r in update public.phone_access_requests
              set status = 'expired'
            where status = 'authorized' and expires_at < now()
        returning employee_id, phone_e164 loop
    perform public.phone_access_audit('autorisation expirée', r.employee_id, '{}');
  end loop;
  delete from public.phone_access_attempts where occurred_at < now() - interval '2 days';
  delete from public.phone_access_tokens where expires_at < now() - interval '1 day';
end;
$$;

-- ---------------------------------------------------- 1. demande (réponse neutre)
create or replace function public.phone_access_request(p_phone text, p_ip_hash text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := public.phone_normalize(p_phone);
  v_ids   uuid[];
  e       public.employees;
  a       public.phone_access_accounts;
  o       public.phone_access_requests;
begin
  perform public.phone_access_expire();
  -- Limites : 10 demandes par adresse et par heure, 3 par numéro et par 24 h (réponse identique au salarié)
  if (select count(*) from public.phone_access_attempts
       where kind = 'request' and ip_hash = p_ip_hash and occurred_at > now() - interval '1 hour') >= 10 then
    return;
  end if;
  if v_phone is not null and (select count(*) from public.phone_access_attempts
       where kind = 'request' and phone_e164 = v_phone and occurred_at > now() - interval '24 hours') >= 3 then
    return;
  end if;
  insert into public.phone_access_attempts (kind, phone_e164, ip_hash) values ('request', v_phone, p_ip_hash);
  if v_phone is null then return; end if;

  select array_agg(id) into v_ids from public.employees
   where status = 'Active' and public.phone_normalize(phone_personal) = v_phone;
  if v_ids is null then return; end if;   -- aucune fiche : rien n'est créé

  -- Numéro partagé, ou déjà détenu par le compte d'un autre salarié : alerte discrète
  if array_length(v_ids, 1) > 1
     or exists (select 1 from public.phone_access_accounts x
                 where x.phone_e164 = v_phone and x.status = 'active' and x.employee_id <> v_ids[1]) then
    if not exists (select 1 from public.phone_access_requests
                    where purpose = 'shared' and phone_e164 = v_phone and status = 'pending') then
      insert into public.phone_access_requests (phone_e164, purpose) values (v_phone, 'shared');
      perform public.phone_access_audit('demande : numéro partagé', null,
                                        jsonb_build_object('phone', public.phone_mask(v_phone)));
    end if;
    return;
  end if;

  select * into e from public.employees where id = v_ids[1];
  select * into a from public.phone_access_accounts where employee_id = e.id;
  -- Fiche déjà reliée à un compte e-mail : pas de second accès
  if e.user_id is not null and (a.user_id is null or a.user_id <> e.user_id) then
    perform public.phone_access_audit('demande ignorée : compte e-mail déjà relié', e.id, '{}');
    return;
  end if;

  select * into o from public.phone_access_requests
   where employee_id = e.id and status in ('pending', 'authorized');
  if found then
    -- Redemande alors qu'une demande est ouverte : l'administrateur est alerté (compteur)
    update public.phone_access_requests set repeat_count = repeat_count + 1 where id = o.id;
    perform public.phone_access_audit('demande répétée', e.id, jsonb_build_object('statut', o.status));
    return;
  end if;

  insert into public.phone_access_requests (employee_id, phone_e164, purpose)
  values (e.id, v_phone, case when a.user_id is null then 'signup' else 'reset' end);
  perform public.phone_access_audit('demande d''accès', e.id,
                                    jsonb_build_object('phone', public.phone_mask(v_phone), 'objet', case when a.user_id is null then 'création' else 'réinitialisation' end));
end;
$$;

-- ----------------------------- 2. ouverture de l'activation (numéro + seconde information)
-- Renvoie vrai si le jeton fourni (haché par l'appelant) a été enregistré ; faux sinon, sans dire pourquoi.
create or replace function public.phone_access_open(p_phone text, p_second date, p_ip_hash text, p_token_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

-- --------------------------------------------------- 3. mot de passe : lecture puis finalisation
create or replace function public.phone_access_peek(p_token_hash text)
returns table (request_id uuid, employee_id uuid, purpose text, phone_e164 text, user_id uuid,
               first_name text, last_name text, employee_number text, date_of_birth date)
language sql
security definer
set search_path = ''
as $$
  select r.id, e.id, r.purpose, r.phone_e164, a.user_id, e.first_name, e.last_name, e.employee_number, e.date_of_birth
  from public.phone_access_tokens t
  join public.phone_access_requests r on r.id = t.request_id and r.status = 'authorized' and r.expires_at > now()
  join public.employees e on e.id = r.employee_id and e.status = 'Active'
  left join public.phone_access_accounts a on a.employee_id = e.id
  where t.token_hash = p_token_hash and t.used_at is null and t.expires_at > now()
    and public.phone_normalize(e.phone_personal) = r.phone_e164;
$$;

-- L'appelant a déjà créé (ou retrouvé) l'utilisateur d'authentification et défini son mot de passe, dans la même transaction.
create or replace function public.phone_access_complete(p_token_hash text, p_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  p record;
begin
  select * into p from public.phone_access_peek(p_token_hash);
  if not found then raise exception 'Activation invalide ou expirée'; end if;
  perform 1 from public.phone_access_tokens where token_hash = p_token_hash and used_at is null for update;
  if not found then raise exception 'Activation invalide ou expirée'; end if;
  if p.user_id is not null and p.user_id <> p_user_id then raise exception 'Compte inattendu pour cette fiche'; end if;
  if p.user_id is null and exists (select 1 from public.user_roles where user_id = p_user_id and role <> 'salarie') then
    raise exception 'Ce mode de connexion ne peut pas être associé à un compte disposant d''un autre rôle';
  end if;
  if exists (select 1 from public.employees where user_id is not null and user_id <> p_user_id and id = p.employee_id) then
    raise exception 'La fiche est déjà reliée à un autre compte';
  end if;

  update public.phone_access_tokens set used_at = now() where token_hash = p_token_hash;
  update public.phone_access_requests set status = 'used', used_at = now() where id = p.request_id;
  insert into public.phone_access_accounts (user_id, employee_id, phone_e164, status)
  values (p_user_id, p.employee_id, p.phone_e164, 'active')
  on conflict (employee_id) do update set phone_e164 = excluded.phone_e164, status = 'active', updated_at = now();
  update public.employees set user_id = p_user_id where id = p.employee_id;
  insert into public.user_roles (user_id, role) values (p_user_id, 'salarie') on conflict do nothing;
  if exists (select 1 from information_schema.columns
              where table_schema = 'auth' and table_name = 'users' and column_name = 'banned_until') then
    execute 'update auth.users set banned_until = null where id = $1' using p_user_id;
  end if;
  perform public.phone_access_audit(case when p.purpose = 'reset' then 'mot de passe changé' else 'mot de passe créé' end,
                                    p.employee_id, '{}');
  return p.employee_id;
end;
$$;

-- Journal des connexions réussies / échouées / verrouillages (appelé par la passerelle ; jamais de mot de passe)
create or replace function public.phone_access_log_login(p_phone text, p_event text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_emp uuid;
begin
  select employee_id into v_emp from public.phone_access_accounts where phone_e164 = public.phone_normalize(p_phone);
  if v_emp is not null and p_event in ('connexion réussie', 'connexion échouée', 'verrouillage de connexion') then
    perform public.phone_access_audit(p_event, v_emp, '{}');
  end if;
end;
$$;

-- Le compte peut-il se connecter ? (état de la ligne phone_access_accounts)
create or replace function public.phone_access_account_status(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select status from public.phone_access_accounts where user_id = p_user_id;
$$;

-- --------------------------------------------------------------- désactivation
create or replace function public.phone_access_disable(p_employee_id uuid, p_status text, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare a public.phone_access_accounts;
begin
  update public.phone_access_requests set status = 'revoked'
   where employee_id = p_employee_id and status in ('pending', 'authorized');
  select * into a from public.phone_access_accounts where employee_id = p_employee_id;
  if not found then return; end if;
  update public.phone_access_accounts set status = p_status, updated_at = now() where employee_id = p_employee_id;
  -- Coupure immédiate de l'accès aux données : plus de rôle ni de fiche reliée
  delete from public.user_roles where user_id = a.user_id;
  update public.employees set user_id = null where id = p_employee_id and user_id = a.user_id;
  if to_regclass('public.refresh_tokens') is not null then
    execute 'update public.refresh_tokens set is_revoked = true where user_id = $1' using a.user_id;
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'auth' and table_name = 'users' and column_name = 'banned_until') then
    execute 'update auth.users set banned_until = ''infinity'' where id = $1' using a.user_id;
  end if;
  perform public.phone_access_audit(p_reason, p_employee_id, '{}');
end;
$$;

-- Changement du numéro sur la fiche : le compte téléphone est désactivé jusqu'à une nouvelle autorisation.
create or replace function public.phone_access_on_phone_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.phone_normalize(new.phone_personal) is distinct from public.phone_normalize(old.phone_personal) then
    perform public.phone_access_disable(new.id, 'disabled', 'compte désactivé : numéro modifié sur la fiche');
  end if;
  return new;
end;
$$;
create trigger employees_phone_access_phone_change
  after update of phone_personal on public.employees
  for each row execute function public.phone_access_on_phone_change();

-- ------------------------------------------------------------- verrou de rôle
create or replace function public.phone_access_role_lock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role <> 'salarie' and exists (select 1 from public.phone_access_accounts where user_id = new.user_id) then
    raise exception 'Un compte connecté par téléphone ne peut avoir que le rôle salarié (créez un compte e-mail distinct pour un autre rôle)'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger user_roles_phone_access_lock
  before insert or update on public.user_roles
  for each row execute function public.phone_access_role_lock();

create or replace function public.phone_access_account_role_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.user_roles where user_id = new.user_id and role <> 'salarie') then
    raise exception 'Ce compte dispose déjà d''un autre rôle : il ne peut pas être un compte téléphone' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger phone_access_accounts_role_check
  before insert on public.phone_access_accounts
  for each row execute function public.phone_access_account_role_check();

-- Aucune fonction d'administration ne délie ni ne relie un compte téléphone
create or replace function public.admin_link_employee(p_user_id uuid, p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['admin']) then
    raise exception 'Réservé aux administrateurs';
  end if;
  if exists (select 1 from public.phone_access_accounts where user_id = p_user_id or employee_id = p_employee_id) then
    raise exception 'Compte connecté par téléphone : son rattachement à la fiche est géré par la procédure d''accès par téléphone';
  end if;
  update public.employees set user_id = null where user_id = p_user_id;
  if p_employee_id is not null then
    update public.employees set user_id = p_user_id where id = p_employee_id;
    insert into public.user_roles(user_id, role) values (p_user_id, 'salarie') on conflict do nothing;
  end if;
end;
$$;

create or replace function public.claim_first_admin()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentification requise';
  end if;
  if exists (select 1 from public.phone_access_accounts where user_id = (select auth.uid())) then
    raise exception 'Un compte connecté par téléphone ne peut pas devenir administrateur';
  end if;
  if exists (select 1 from public.user_roles where role = 'admin') then
    return false;
  end if;
  insert into public.user_roles(user_id, role) values ((select auth.uid()), 'admin');
  return true;
end;
$$;

-- --------------------------------------------------------- écrans de l'administrateur
create or replace function public.admin_phone_access_requests()
returns table (id uuid, employee_id uuid, employee_number text, employee_name text, department text,
               phone_masked text, purpose text, status text, requested_at timestamptz, decided_at timestamptz,
               expires_at timestamptz, repeat_count integer, has_birth_date boolean)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['admin']) then
    raise exception 'Réservé aux administrateurs';
  end if;
  perform public.phone_access_expire();
  return query
    select r.id, r.employee_id, e.employee_number, coalesce(e.last_name || ' ' || e.first_name, 'Numéro partagé'),
           d.name, public.phone_mask(r.phone_e164), r.purpose, r.status, r.requested_at, r.decided_at,
           r.expires_at, r.repeat_count, e.date_of_birth is not null
    from public.phone_access_requests r
    left join public.employees e on e.id = r.employee_id
    left join public.departments d on d.id = e.department_id
    order by (r.status = 'pending') desc, r.requested_at desc
    limit 200;
end;
$$;

create or replace function public.admin_phone_access_accounts()
returns table (employee_id uuid, employee_number text, employee_name text, phone_masked text, status text, created_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['admin']) then
    raise exception 'Réservé aux administrateurs';
  end if;
  return query
    select a.employee_id, e.employee_number, e.last_name || ' ' || e.first_name, public.phone_mask(a.phone_e164), a.status, a.created_at
    from public.phone_access_accounts a join public.employees e on e.id = a.employee_id
    order by e.last_name, e.first_name;
end;
$$;

create or replace function public.admin_phone_access_decide(p_request_id uuid, p_authorize boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.phone_access_requests;
  e public.employees;
  s public.phone_access_settings;
begin
  if not public.has_role(array['admin']) then
    raise exception 'Réservé aux administrateurs';
  end if;
  perform public.phone_access_expire();
  select * into r from public.phone_access_requests where id = p_request_id for update;
  if not found or r.status <> 'pending' then
    raise exception 'Demande introuvable ou déjà traitée';
  end if;
  select * into s from public.phone_access_settings;
  if p_authorize then
    if s.validation <> 'admin' then raise exception 'Mode de validation non pris en charge'; end if;
    if r.purpose = 'shared' then raise exception 'Numéro partagé : corrigez les fiches avant toute autorisation'; end if;
    select * into e from public.employees where id = r.employee_id;
    if e.status <> 'Active' or public.phone_normalize(e.phone_personal) is distinct from r.phone_e164 then
      raise exception 'Le numéro de la fiche ne correspond plus à la demande';
    end if;
    if s.second_factor and e.date_of_birth is null then
      raise exception 'Date de naissance absente de la fiche : impossible de contrôler l''identité du salarié';
    end if;
    update public.phone_access_requests
       set status = 'authorized', decided_by = (select auth.uid()), decided_at = now(), decision_note = p_note,
           expires_at = now() + make_interval(hours => s.authorization_hours)
     where id = r.id;
    perform public.phone_access_audit('autorisation accordée', r.employee_id,
                                      jsonb_build_object('expire_le', now() + make_interval(hours => s.authorization_hours)));
  else
    update public.phone_access_requests
       set status = 'refused', decided_by = (select auth.uid()), decided_at = now(), decision_note = p_note
     where id = r.id;
    perform public.phone_access_audit('demande refusée', r.employee_id, '{}');
  end if;
end;
$$;

create or replace function public.admin_phone_access_revoke(p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['admin']) then
    raise exception 'Réservé aux administrateurs';
  end if;
  perform public.phone_access_disable(p_employee_id, 'revoked', 'accès par téléphone révoqué');
end;
$$;

-- Statut affiché sur la fiche salarié
create or replace function public.employee_phone_access_status(p_employee_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_acc text; v_req text;
begin
  if not public.has_role(array['rh']) then
    raise exception 'Droits insuffisants';
  end if;
  select status into v_acc from public.phone_access_accounts where employee_id = p_employee_id;
  if v_acc = 'active' then return 'actif'; end if;
  select case when status = 'authorized' and expires_at > now() then 'autorisé' else 'en attente' end into v_req
    from public.phone_access_requests
   where employee_id = p_employee_id and status in ('pending', 'authorized')
     and (status = 'pending' or expires_at > now());
  if v_req is not null then return v_req; end if;
  if v_acc is not null then return 'révoqué'; end if;
  return 'non demandé';
end;
$$;

-- ----------------------------------------------- alertes de l'administrateur
-- Fonction à part (legal_alerts reste inchangée : detecter_conformite() la lit et ne doit pas voir ces alertes).
-- Même forme de retour que legal_alerts ; l'écran LegalAlerts affiche les deux listes ensemble.
create or replace function public.phone_access_alerts()
returns table (
  code text, severity text, employee_id uuid, employee_number text, employee_name text,
  due_date date, message text
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not public.has_role(array['admin']) then
    raise exception 'Réservé aux administrateurs';
  end if;
  perform public.phone_access_expire();
  return query
  select case when r.purpose = 'shared' then 'phone_access_shared' else 'phone_access_request' end,
         case when r.purpose = 'shared' or r.repeat_count > 0 then 'erreur' else 'alerte' end,
         r.employee_id, e.employee_number, coalesce(e.last_name || ' ' || e.first_name, 'Numéro partagé'), r.requested_at::date,
         case when r.purpose = 'shared'
              then 'Numéro partagé par plusieurs fiches (' || public.phone_mask(r.phone_e164) || ') : corriger les fiches'
              else 'Demande d''accès par téléphone (' || case r.purpose when 'reset' then 'réinitialisation' else 'création' end
                   || ') du ' || to_char(r.requested_at, 'DD/MM/YYYY') || ' : contacter le salarié puis autoriser ou refuser'
                   || case when r.repeat_count > 0 then ' — redemandée ' || r.repeat_count || ' fois' else '' end end
  from public.phone_access_requests r
  left join public.employees e on e.id = r.employee_id
  where r.status = 'pending' or (r.status = 'authorized' and r.repeat_count > 0);
end;
$function$;

-- ------------------------------------------------------------------- droits
revoke execute on function public.phone_access_audit(text, uuid, jsonb), public.phone_access_expire(),
  public.phone_access_request(text, text), public.phone_access_open(text, date, text, text),
  public.phone_access_peek(text), public.phone_access_complete(text, uuid),
  public.phone_access_log_login(text, text), public.phone_access_account_status(uuid),
  public.phone_access_disable(uuid, text, text) from public, anon, authenticated;
grant execute on function public.phone_access_request(text, text), public.phone_access_open(text, date, text, text),
  public.phone_access_peek(text), public.phone_access_complete(text, uuid),
  public.phone_access_log_login(text, text), public.phone_access_account_status(uuid) to service_role;

revoke execute on function public.admin_phone_access_requests(), public.admin_phone_access_accounts(),
  public.admin_phone_access_decide(uuid, boolean, text), public.admin_phone_access_revoke(uuid),
  public.employee_phone_access_status(uuid), public.phone_access_alerts(),
  public.admin_link_employee(uuid, uuid), public.claim_first_admin() from public, anon;
grant execute on function public.admin_phone_access_requests(), public.admin_phone_access_accounts(),
  public.admin_phone_access_decide(uuid, boolean, text), public.admin_phone_access_revoke(uuid),
  public.employee_phone_access_status(uuid), public.phone_access_alerts(),
  public.admin_link_employee(uuid, uuid), public.claim_first_admin() to authenticated;

-- Fonctions de déclencheur et utilitaires : jamais exécutables par le rôle anonyme (le déclencheur s'exécute sans ce droit)
revoke execute on function public.phone_normalize(text), public.phone_mask(text), public.phone_access_on_phone_change(),
  public.phone_access_role_lock(), public.phone_access_account_role_check() from public, anon;
grant execute on function public.phone_normalize(text), public.phone_mask(text) to authenticated, service_role;

notify pgrst, 'reload schema';
