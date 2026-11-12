-- les versements créés par la synchronisation disparaissent avec le suivi (les saisies manuelles restent)
delete from public.contribution_payments where notes = 'Suivi des versements par caisse';
drop view if exists public.v_contribution_follow;
drop table if exists public.contribution_payment_lines;
drop function if exists public.contribution_payment_lines_touch(), public.contribution_payment_lines_audit(), public.contribution_payment_lines_sync(), public.contribution_caisse(text);
notify pgrst, 'reload schema';
