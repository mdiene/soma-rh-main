-- Retour : supprime la fonction d'ajustement. Les écritures déjà posées restent dans le registre (ajout seul).
drop function if exists public.adjust_leave_balance(uuid, text, numeric, date, text);
notify pgrst, 'reload schema';
