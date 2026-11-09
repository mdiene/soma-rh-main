-- Retour de 20261208090000_l2b_validation_admin.sql.
-- deroger_constat doit être rétabli à sa définition d'origine (20261113090000_lote_ecran_conformite.sql : « create or replace function public.deroger_constat »).
drop function if exists public.approval_pending_count();
drop function if exists public.approval_requests_overview(text);
drop function if exists public.cancel_request(uuid);
drop function if exists public.decide_request(uuid, boolean, text);
drop function if exists public.request_scale_reset(text, date);
drop function if exists public.request_scale_change(text, date, jsonb);
drop function if exists public.scale_check_request(text, date);
drop function if exists public.request_parameter_reset(text, date);
drop function if exists public.request_parameter_change(text, numeric, date);
drop function if exists public.request_waiver(text, uuid, text, text);
drop function if exists public.create_request(text, text, text, jsonb);
drop function if exists public.apply_request(uuid);
drop function if exists public.parameter_check(text, numeric, date);
drop table if exists public.approval_requests;
drop index if exists public.compliance_waivers_requested_by_idx;
alter table public.compliance_waivers drop column if exists requested_by;
notify pgrst, 'reload schema';
