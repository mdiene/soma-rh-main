-- =============================================================================
-- Retrait du planning des postes (gardiens 24 h/24) de la version de base
-- Décision du propriétaire (2026-11-06) : la gestion des gardiens sera un module métier, activé seulement
-- par les entreprises qui en ont besoin. Supprime les 3 tables (work_posts, shift_types, shift_assignments),
-- la fonction generate_rotation et, avec elles, leurs politiques RLS, déclencheurs d'audit et index.
-- Données supprimées : 1 037 affectations de test (26 salariés), 6 types de poste. Sauvegarde :
--   backups/soma_rh_avant_retrait_gardiens_<horodatage>.sql (ignoré par Git).
-- Retour : db/rollback/20261120090000_retrait_planning_gardiens_down.sql (structure) puis rechargement des données depuis la sauvegarde.
-- =============================================================================
drop function if exists public.generate_rotation(uuid[], date, date, text[], integer, uuid);
drop table if exists public.shift_assignments;
drop table if exists public.shift_types;
drop table if exists public.work_posts;
notify pgrst, 'reload schema';
