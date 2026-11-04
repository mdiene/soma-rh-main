-- Rollback de D-010 : restaure la garde antérieure (5 statuts, mises à jour seulement).
create or replace function public.guard_payroll_status_transition()
 returns trigger language plpgsql set search_path to ''
as $function$
begin
  if new.status is distinct from old.status
     and new.status in ('En revue','Approuvée','Payée','Clôturée','Réouverte')
     and coalesce(current_setting('soma.payroll_transition', true), '') <> 'on' then
    raise exception 'Transition de paie interdite par UPDATE direct; utiliser transition_payroll_entry';
  end if;
  return new;
end;
$function$;
drop trigger if exists payroll_entries_transition_guard on public.payroll_entries;
create trigger payroll_entries_transition_guard before update on public.payroll_entries
  for each row execute function public.guard_payroll_status_transition();
create or replace function public.cancel_payroll_entry(p_payroll_entry_id uuid)
 returns void language plpgsql security definer set search_path to ''
as $function$
begin
  if not public.has_role(array['admin']) then
    raise exception 'Seul un administrateur peut annuler un traitement';
  end if;
  update public.salary_slips set status = 'Annulé' where payroll_entry_id = p_payroll_entry_id;
  update public.payroll_entries set status = 'Annulée' where id = p_payroll_entry_id;
end;
$function$;
