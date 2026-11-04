-- D-014 (QA, S3) : les fonctions Dev03/Dev04 (journal comptable, IPRES, DGID) étaient exécutables par PUBLIC/anon.
-- Même correctif que 20261104180000 ; à rejouer si une migration recrée ces fonctions avec un autre droit.
-- Retour : db/rollback/20261105110000_revoke_execute_anon_dev03_dev04_down.sql
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;
notify pgrst, 'reload schema';
