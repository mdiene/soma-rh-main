-- =============================================================================
-- D-013 (QA, S3) : le rôle anonyme (et PUBLIC) pouvait exécuter 58 fonctions du schéma public :
-- outils pgcrypto (crypt, digest, pgp_*), payroll_settings_at, tax_slab_at, severance_coefficient,
-- can_see_leave, excel_datedif, et des fonctions de déclencheur. Aucune n'expose de donnée personnelle,
-- mais une surface d'attaque anonyme inutile : aucune page publique n'appelle de fonction.
-- Après : seuls les utilisateurs connectés (authenticated) et service_role exécutent ces fonctions.
-- Les futures fonctions héritent déjà de pg_default_acl (authenticated seulement).
-- Retour : db/rollback/20261104180000_revoke_execute_anon_down.sql
-- =============================================================================
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;

alter default privileges in schema public revoke execute on functions from public, anon;

notify pgrst, 'reload schema';
