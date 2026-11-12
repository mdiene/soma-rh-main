-- retour arrière de l'alerte « structure salariale à affecter »
drop function if exists public.structure_pending_alerts();
notify pgrst, 'reload schema';
