-- L7 : ajustement manuel d'un solde de congés, réservé à la RH, motif obligatoire, posé comme écriture du registre
-- (source « manual »). Jamais de modification d'une écriture existante : une erreur se corrige par un ajustement inverse.
-- Retour : db/rollback/20261208090000_leave_manual_adjustment_down.sql
create or replace function public.adjust_leave_balance(p_employee_id uuid, p_leave_type text, p_days numeric, p_effective_date date, p_reason text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.has_role(array['rh']) then
    raise exception 'Droits insuffisants : rôle « rh » requis pour ajuster un solde de congés';
  end if;
  if p_days is null or p_days = 0 or abs(p_days) > 365 then
    raise exception 'Nombre de jours invalide : non nul et au plus 365 en valeur absolue';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'Un motif d''au moins 5 caractères est obligatoire pour ajuster un solde';
  end if;
  if p_effective_date is null then
    raise exception 'La date d''effet est obligatoire';
  end if;
  if not exists (select 1 from public.employees where id = p_employee_id) then
    raise exception 'Salarié introuvable';
  end if;
  if not exists (select 1 from public.leave_types where code = p_leave_type) then
    raise exception 'Type de congé inconnu';
  end if;
  insert into public.leave_ledger(employee_id, leave_type, effective_date, days, kind, source_table, source_id, note)
  values (p_employee_id, p_leave_type, p_effective_date, p_days, 'adjustment', 'manual', null, btrim(p_reason))
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.adjust_leave_balance(uuid, text, numeric, date, text) from public, anon;
grant execute on function public.adjust_leave_balance(uuid, text, numeric, date, text) to authenticated;
notify pgrst, 'reload schema';
