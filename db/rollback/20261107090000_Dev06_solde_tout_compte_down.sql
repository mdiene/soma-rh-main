-- Retour DEV-06 : supprime les trois fonctions. Les sorties déjà enregistrées (relieving_date, exit_reason) ne sont pas annulées.
drop function if exists public.sortie_salarie(uuid, date, text);
drop function if exists public.solde_tout_compte(uuid);
drop function if exists public.certificat_travail(uuid);
notify pgrst, 'reload schema';
