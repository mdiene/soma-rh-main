-- D-017 (QA, S1) : la passerelle d'authentification écrit dans public.refresh_tokens, qui n'existait pas
-- (le DDL à l'exécution était invalide) : toute connexion échouait en 500 dès que l'image était reconstruite.
-- Table réservée à la passerelle (propriétaire soma) : RLS activée sans politique, donc inaccessible via l'API REST.
-- Retour : db/rollback/20261105120000_refresh_tokens_down.sql
create table if not exists public.refresh_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token_hash text not null,
  expires_at timestamptz not null,
  is_revoked boolean not null default false,
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);
alter table public.refresh_tokens enable row level security;
revoke all on public.refresh_tokens from public, anon, authenticated;
create index if not exists refresh_tokens_user_idx on public.refresh_tokens (user_id);
create index if not exists refresh_tokens_hash_idx on public.refresh_tokens (token_hash);
notify pgrst, 'reload schema';
