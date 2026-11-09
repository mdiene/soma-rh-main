-- Retour de 20261209090000_l3_fermeture_ecritures_directes.sql : rétablit les droits d'écriture d'avant (paie pour les taux et l'impôt, rh pour les barèmes).
do $$
declare t text; r text;
begin
  foreach t in array array['payroll_settings', 'tax_slabs', 'tax_slab_brackets', 'ir_family_reductions', 'trimf_brackets',
                           'overtime_rates', 'notice_scales', 'garnishment_scale', 'severance_scales'] loop
    r := case when t in ('overtime_rates', 'notice_scales', 'garnishment_scale', 'severance_scales') then 'rh' else 'paie' end;
    execute format('drop policy if exists %I on public.%I', t || '_ins', t);
    execute format('drop policy if exists %I on public.%I', t || '_upd', t);
    execute format('drop policy if exists %I on public.%I', t || '_del', t);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select public.has_role(array[%L])))', t || '_ins', t, r);
    execute format('create policy %I on public.%I for update to authenticated using ((select public.has_role(array[%L]))) with check ((select public.has_role(array[%L])))', t || '_upd', t, r, r);
    execute format('create policy %I on public.%I for delete to authenticated using ((select public.has_role(array[%L])))', t || '_del', t, r);
  end loop;
end $$;

create or replace function public.set_loan_max_rate(p_rate numeric)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['admin', 'rh', 'paie']) then
    raise exception 'Droits insuffisants : administrateur, RH ou paie requis pour modifier le plafond de retenue';
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
notify pgrst, 'reload schema';
