-- Retour user_preferences : supprime la table (et les préférences enregistrées : favoris, thème…).
drop table if exists public.user_preferences;
notify pgrst, 'reload schema';
