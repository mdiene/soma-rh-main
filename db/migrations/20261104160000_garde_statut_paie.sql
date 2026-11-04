-- =============================================================================
-- D-010 (QA, S1) : contournement du workflow de paie par UPDATE ou INSERT direct.
-- Avant : la garde ne couvrait que 5 statuts et seulement les mises à jour ; un rôle rh ou paie pouvait
-- passer une paie en « Validée » (ou l'insérer ainsi) sans séparation des tâches ni machine d'états.
-- Après : tout changement de statut passe par transition_payroll_entry (ou revert/cancel), sauf
--   * la création en « Brouillon » ;
--   * le recalcul (vers « Calculée » depuis Brouillon, Calculée, Réouverte, En revue, Approuvée).
-- Retour : db/rollback/20261104160000_garde_statut_paie_down.sql
-- =============================================================================
create or replace function public.guard_payroll_status_transition()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if coalesce(current_setting('soma.payroll_transition', true), '') = 'on' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.status is distinct from 'Brouillon' then
      raise exception 'Une paie se crée à l''état « Brouillon » ; utiliser transition_payroll_entry pour la suite';
    end if;
    return new;
  end if;
  if new.status is distinct from old.status
     and not (new.status = 'Calculée'
              and old.status in ('Brouillon', 'Calculée', 'Réouverte', 'En revue', 'Approuvée')) then
    raise exception 'Transition de paie interdite par UPDATE direct; utiliser transition_payroll_entry';
  end if;
  return new;
end;
$function$;

drop trigger if exists payroll_entries_transition_guard on public.payroll_entries;
create trigger payroll_entries_transition_guard
  before insert or update on public.payroll_entries
  for each row execute function public.guard_payroll_status_transition();

-- L'annulation par l'administrateur déclare sa propre transition.
create or replace function public.cancel_payroll_entry(p_payroll_entry_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if not public.has_role(array['admin']) then
    raise exception 'Seul un administrateur peut annuler un traitement';
  end if;
  perform set_config('soma.payroll_transition', 'on', true);
  update public.salary_slips set status = 'Annulé' where payroll_entry_id = p_payroll_entry_id;
  update public.payroll_entries set status = 'Annulée' where id = p_payroll_entry_id;
end;
$function$;

notify pgrst, 'reload schema';
