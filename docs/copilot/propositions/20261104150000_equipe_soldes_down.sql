-- Retour proposé : Mon équipe, soldes de congés visibles du manager.
drop policy if exists leave_alloc_select_team on public.leave_allocations;
notify pgrst, 'reload schema';
