-- Retour proposé : journal comptable (3 fonctions). Aucune table créée.
-- ATTENTION : 20261107100000_mois_valides_payes_clotures redéfinit export_payroll_journal ; défaire cette migration d'abord.
drop function if exists public.check_journal_imputation(uuid);
drop function if exists public.validate_journal_balance(uuid);
drop function if exists public.export_payroll_journal(uuid);
notify pgrst, 'reload schema';
