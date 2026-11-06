-- Retour M0 modules métiers : supprime les 4 tables (et leurs données), le chargeur et le trigger d'activation.
-- Les lignes d'audit_log déjà écrites sont conservées (journal inaltérable). L'extension btree_gist est laissée en place.
drop function if exists public.load_module_manifest(jsonb, text);
drop table if exists public.employee_module_data;
drop table if exists public.module_parameter_value;
drop table if exists public.module_activation;
drop function if exists public.module_activation_stamp();
drop table if exists public.module_manifest;
notify pgrst, 'reload schema';
