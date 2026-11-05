-- D-021 (QA, S3) : prevent_closed_period_data_mutation (migration D-49) était exécutable par PUBLIC/anon, comme D-013 et D-014.
-- Même correctif, rejouable. Toute migration qui crée une fonction doit se terminer par ces deux lignes.
-- Retour : db/rollback/20261107120000_revoke_execute_anon_d49_down.sql
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;
notify pgrst, 'reload schema';
