-- D-013/D-021 (3e récidive) : la migration 20261118090000_m0_modules_metiers_socle crée l'extension btree_gist dans le schéma public ;
-- ses fonctions d'index (gbt_*, *_dist) sont exécutables par PUBLIC et donc par le rôle anonyme. Même correctif que D-013.
-- Retour : db/rollback/20261121090000_revoke_execute_anon_btree_gist_down.sql
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;
notify pgrst, 'reload schema';
