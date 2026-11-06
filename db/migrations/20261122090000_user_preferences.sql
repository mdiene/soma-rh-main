-- =============================================================================
-- Préférences utilisateur : une ligne par compte, contenu extensible en jsonb.
-- Aujourd'hui : { "favorites": ["/paie/variables", ...] } (vues épinglées en haut du menu).
-- Demain : thème, mode d'affichage, couleurs, etc. : nouvelles clés, sans nouvelle migration.
-- Chaque utilisateur ne lit et n'écrit que sa propre ligne (même la RH : ce sont des préférences personnelles).
-- Pas de trigger d'audit : donnée d'interface, sans effet métier.
-- Retour : db/rollback/20261122090000_user_preferences_down.sql
-- =============================================================================
create table public.user_preferences (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  preferences jsonb not null default '{}'::jsonb
              check (jsonb_typeof(preferences) = 'object' and pg_column_size(preferences) <= 16384),
  updated_at  timestamptz not null default now()
);

alter table public.user_preferences enable row level security;

create policy user_preferences_select on public.user_preferences for select to authenticated
  using (user_id = (select auth.uid()));
create policy user_preferences_insert on public.user_preferences for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy user_preferences_update on public.user_preferences for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy user_preferences_delete on public.user_preferences for delete to authenticated
  using (user_id = (select auth.uid()));

notify pgrst, 'reload schema';
