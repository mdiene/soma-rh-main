-- =============================================================================
-- Centre de conformité, lot L3 : fermeture des écritures directes sur les constantes et barèmes.
-- Décision du 2026-11-09 : le RH et la paie saisissent, l'administrateur valide. Depuis L2b ils passent par des demandes
-- (request_parameter_change, request_scale_change ...) ; ce lot retire l'ancien accès direct qui contournait la validation.
--   payroll_settings, tax_slabs, tax_slab_brackets, ir_family_reductions, trimf_brackets,
--   overtime_rates, notice_scales, garnishment_scale, severance_scales : insertion / modification / suppression réservées à l'administrateur
--   set_loan_max_rate : administrateur seul (le plafond de prêt est une constante du catalogue)
-- La lecture ne change pas. Les gardes de verrou (paies calculées) continuent de s'appliquer à tous, administrateur compris.
-- Retour : db/rollback/20261209090000_l3_fermeture_ecritures_directes_down.sql
-- =============================================================================
do $$
declare t text;
begin
  foreach t in array array['payroll_settings', 'tax_slabs', 'tax_slab_brackets', 'ir_family_reductions', 'trimf_brackets',
                           'overtime_rates', 'notice_scales', 'garnishment_scale', 'severance_scales'] loop
    execute format('drop policy if exists %I on public.%I', t || '_ins', t);
    execute format('drop policy if exists %I on public.%I', t || '_upd', t);
    execute format('drop policy if exists %I on public.%I', t || '_del', t);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select public.has_role(array[''admin''])))', t || '_ins', t);
    execute format('create policy %I on public.%I for update to authenticated using ((select public.has_role(array[''admin'']))) with check ((select public.has_role(array[''admin''])))', t || '_upd', t);
    execute format('create policy %I on public.%I for delete to authenticated using ((select public.has_role(array[''admin''])))', t || '_del', t);
  end loop;
end $$;

create or replace function public.set_loan_max_rate(p_rate numeric)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['admin']) then
    raise exception 'Droits insuffisants : rôle « admin » requis pour modifier le plafond de retenue (les autres rôles passent par une demande de modification de constante)';
  end if;
  if p_rate is null or p_rate <= 0 or p_rate > 1 then
    raise exception 'Le plafond doit être compris entre 0 et 1 (0,33 = 33 %% du brut)';
  end if;
  insert into public.app_parameters (code, label, value, updated_by)
  values ('loan_max_rate', 'Plafond de la retenue mensuelle de prêt (part du brut)', p_rate, auth.uid())
  on conflict (code) do update set value = excluded.value, updated_by = auth.uid(), updated_at = now();
  return p_rate;
end;
$$;
revoke all on function public.set_loan_max_rate(numeric) from public, anon;
grant execute on function public.set_loan_max_rate(numeric) to authenticated;

notify pgrst, 'reload schema';
