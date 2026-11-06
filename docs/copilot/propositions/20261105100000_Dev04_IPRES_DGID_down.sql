-- Retour proposé : états IPRES/CSS et DGID (2 fonctions). Aucune table créée.
drop function if exists public.etat_dgid(uuid, date, text);
drop function if exists public.export_ipres_css(uuid, date);
notify pgrst, 'reload schema';
