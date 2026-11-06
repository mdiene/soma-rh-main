-- D-021 (suite) : salary_slip_non_negative_net (migration D30/D53) était exécutable par PUBLIC/anon.
-- Même correctif que D49, rejouable. Retour : db/rollback/20261107140000_revoke_execute_anon_d30_d53_down.sql
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;
notify pgrst, 'reload schema';
