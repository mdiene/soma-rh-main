-- =============================================================================
-- M0 Modules métiers : socle (catalogue, activation, valeurs de paramètres, données par salarié)
-- Un module désactivé ne change rien à l'application : aucune fonction de paie n'est touchée ici.
-- Règles : RH écrit, paie lit, salarié lit seulement ses propres données de module.
-- Audit : trigger business_audit existant (activation, paramètres, données, manifestes).
-- Écart avec PROJET §4 : module_manifest n'a pas activated_at/activated_by (portés par module_activation,
-- avec version et hash du manifeste au moment de l'activation) ; une ligne par module (historique = audit_log).
-- Retour : db/rollback/20261118090000_m0_modules_metiers_socle_down.sql
-- =============================================================================
create extension if not exists btree_gist;

-- ------------------------------------------------------------ catalogue
create table public.module_manifest (
  module_id  text primary key check (module_id ~ '^[a-z][a-z0-9-]*$'),
  name       text not null,
  version    text not null,
  status     text not null default 'draft',
  hash       text not null,
  manifest   jsonb not null,
  loaded_at  timestamptz not null default now()
);

-- ------------------------------------------------------------ activation (état courant ; historique dans audit_log)
create table public.module_activation (
  id               uuid primary key default gen_random_uuid(),
  module_id        text not null unique references public.module_manifest(module_id) on delete restrict,
  enabled          boolean not null default false,
  manifest_version text,
  manifest_hash    text,
  enabled_at       timestamptz,
  enabled_by       uuid references auth.users(id) on delete set null,
  disabled_at      timestamptz
);
create index module_activation_enabled_by_idx on public.module_activation(enabled_by);

-- ------------------------------------------------------------ valeurs de paramètres, versions datées sans chevauchement
-- valid_from null = date d'effet non précisée (jamais inventée). Absence de ligne = paramètre manquant.
create table public.module_parameter_value (
  id           uuid primary key default gen_random_uuid(),
  module_id    text not null references public.module_manifest(module_id) on delete cascade,
  param_key    text not null,
  value        jsonb not null,
  legal_status text not null check (legal_status in ('verified','secondary','to_provide')),
  source       text,
  valid_from   date,
  valid_to     date,
  entered_by   uuid default auth.uid() references auth.users(id) on delete set null,
  entered_at   timestamptz not null default now(),
  check (valid_to is null or valid_from is null or valid_to > valid_from),
  exclude using gist (module_id with =, param_key with =, daterange(valid_from, valid_to, '[)') with &&)
);
create index module_parameter_value_entered_by_idx on public.module_parameter_value(entered_by);

-- ------------------------------------------------------------ champs complémentaires par salarié
create table public.employee_module_data (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  module_id   text not null references public.module_manifest(module_id) on delete cascade,
  data        jsonb not null default '{}'::jsonb,
  valid_from  date,
  valid_to    date,
  check (valid_to is null or valid_from is null or valid_to > valid_from),
  exclude using gist (employee_id with =, module_id with =, daterange(valid_from, valid_to, '[)') with &&)
);
create index employee_module_data_module_idx on public.employee_module_data(module_id);

-- ------------------------------------------------------------ RLS
alter table public.module_manifest        enable row level security;
alter table public.module_activation      enable row level security;
alter table public.module_parameter_value enable row level security;
alter table public.employee_module_data   enable row level security;

create policy module_manifest_read on public.module_manifest for select to authenticated
  using ((select public.has_role(array['rh','paie'])));
create policy module_manifest_write on public.module_manifest for all to authenticated
  using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));

create policy module_activation_read on public.module_activation for select to authenticated
  using ((select public.has_role(array['rh','paie'])));
create policy module_activation_write on public.module_activation for all to authenticated
  using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));

create policy module_parameter_value_read on public.module_parameter_value for select to authenticated
  using ((select public.has_role(array['rh','paie'])));
create policy module_parameter_value_write on public.module_parameter_value for all to authenticated
  using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));

create policy employee_module_data_read on public.employee_module_data for select to authenticated
  using (employee_id = (select public.my_employee_id()) or (select public.has_role(array['rh','paie'])));
create policy employee_module_data_write on public.employee_module_data for all to authenticated
  using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));

-- ------------------------------------------------------------ estampillage de l'activation (qui, quand, quelle version)
create or replace function public.module_activation_stamp() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.enabled and (tg_op = 'INSERT' or not old.enabled) then
    select m.version, m.hash into new.manifest_version, new.manifest_hash
      from public.module_manifest m where m.module_id = new.module_id;
    new.enabled_at := now(); new.enabled_by := (select auth.uid()); new.disabled_at := null;
  elsif not new.enabled and tg_op = 'UPDATE' and old.enabled then
    new.disabled_at := now();
  end if;
  return new;
end $$;
create trigger module_activation_stamp before insert or update on public.module_activation
  for each row execute function public.module_activation_stamp();

-- ------------------------------------------------------------ audit (même mécanisme que les autres tables métier)
create trigger module_manifest_audit        after insert or update or delete on public.module_manifest        for each row execute function public.business_audit();
create trigger module_activation_audit      after insert or update or delete on public.module_activation      for each row execute function public.business_audit();
create trigger module_parameter_value_audit after insert or update or delete on public.module_parameter_value for each row execute function public.business_audit();
create trigger employee_module_data_audit   after insert or update or delete on public.employee_module_data   for each row execute function public.business_audit();

-- ------------------------------------------------------------ chargeur : enregistre un manifeste déjà validé (schéma vérifié côté script)
-- Pré-remplit seulement les paramètres ✔ verified et ◐ secondary ayant une valeur. Un paramètre to_provide
-- (même avec valeur provisoire) reste vide : pas de valeur, donc alerte « paramètre manquant » au calcul.
create or replace function public.load_module_manifest(p_manifest jsonb, p_hash text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id text := p_manifest->>'module_id'; v_old text; v_seeded int;
begin
  if not (select public.has_role(array['rh'])) then
    raise exception 'droits insuffisants' using errcode = '42501';
  end if;
  if v_id is null or p_manifest->>'version' is null or p_manifest->>'module_name' is null then
    raise exception 'manifeste invalide : module_id, module_name et version obligatoires';
  end if;
  select hash into v_old from public.module_manifest where module_id = v_id;
  insert into public.module_manifest(module_id, name, version, status, hash, manifest)
  values (v_id, p_manifest->>'module_name', p_manifest->>'version', coalesce(p_manifest->>'status', 'draft'), p_hash, p_manifest)
  on conflict (module_id) do update
    set name = excluded.name, version = excluded.version, status = excluded.status,
        hash = excluded.hash, manifest = excluded.manifest, loaded_at = now()
    where public.module_manifest.hash is distinct from excluded.hash;
  insert into public.module_parameter_value(module_id, param_key, value, legal_status, source)
  select v_id, p.key, p.value->'value', p.value->>'legal_status', p.value->>'source'
  from jsonb_each(coalesce(p_manifest->'parameters', '{}'::jsonb)) p
  where p.value->>'legal_status' in ('verified','secondary')
    and jsonb_typeof(p.value->'value') is not null and jsonb_typeof(p.value->'value') <> 'null'
    and not exists (select 1 from public.module_parameter_value v where v.module_id = v_id and v.param_key = p.key);
  get diagnostics v_seeded = row_count;
  return jsonb_build_object('module_id', v_id, 'changed', v_old is distinct from p_hash, 'seeded', v_seeded);
end $$;
revoke execute on function public.load_module_manifest(jsonb, text) from public, anon;
grant execute on function public.load_module_manifest(jsonb, text) to authenticated;
revoke execute on function public.module_activation_stamp() from public, anon, authenticated;

notify pgrst, 'reload schema';
