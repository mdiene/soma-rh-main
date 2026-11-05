-- =============================================================================
-- DEV-06 : sortie d'un salarié, solde de tout compte, certificat de travail
-- Corrige la première version : délimiteurs `$$` invalides (échec à l'application), salaire et taux inventés dans le solde,
-- colonne employees.designation inexistante dans le certificat, sortie sans effet réel.
--   sortie_salarie(salarié, date, motif)  RH seulement : enregistre la sortie (relieving_date, exit_reason, statut « Left »),
--                                         clôt le rattachement à son manager et ses liens hors hiérarchie, retire ses accès.
--   solde_tout_compte(salarié)            RH ou paie : bulletin du mois de sortie calculé par compute_salary_slip (indemnités de
--                                         licenciement, de retraite, de précarité incluses) + indemnité de congés non pris.
--   certificat_travail(salarié)           texte du certificat : dates d'entrée et de sortie, emploi (art. L.55 du Code du travail).
-- Application : docker exec -i soma-rh-local-postgres-1 psql -U soma -d soma_rh -v ON_ERROR_STOP=1 < ce fichier
-- Retour : db/rollback/20261107090000_Dev06_solde_tout_compte_down.sql
-- =============================================================================
drop function if exists public.solde_tout_compte(uuid, date);
drop function if exists public.certificat_travail(uuid, date);

-- ------------------------------------------------------------ sortie
create or replace function public.sortie_salarie(p_employee_id uuid, p_exit_date date, p_exit_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  e public.employees;
  v_managers integer := 0;
  v_liens integer := 0;
  v_acces integer := 0;
  v_effective boolean := p_exit_date <= current_date;
begin
  if not public.has_role(array['rh']) then raise exception 'Réservé au service RH'; end if;
  if p_exit_date is null then raise exception 'La date de sortie est obligatoire'; end if;
  if p_exit_reason is null or p_exit_reason not in ('DEMISSION', 'LICENCIEMENT', 'RETRAITE', 'DECES', 'FIN DE CONTRAT') then
    raise exception 'Motif de sortie invalide : DEMISSION, LICENCIEMENT, RETRAITE, DECES ou FIN DE CONTRAT';
  end if;
  select * into e from public.employees where id = p_employee_id for update;
  if not found then raise exception 'Salarié introuvable'; end if;
  if e.relieving_date is not null then
    raise exception 'La sortie de ce salarié est déjà enregistrée (le %)', to_char(e.relieving_date, 'DD/MM/YYYY');
  end if;
  if p_exit_date < e.date_of_joining then raise exception 'La date de sortie est antérieure à la date d''entrée'; end if;

  update public.employees
     set relieving_date = p_exit_date, exit_reason = p_exit_reason,
         status = case when v_effective then 'Left' else status end
   where id = p_employee_id;

  -- le salarié n'a plus de manager à partir de la sortie
  update public.employee_manager_assignments set valid_to = p_exit_date
   where employee_id = p_employee_id and valid_from <= p_exit_date and (valid_to is null or valid_to > p_exit_date);
  get diagnostics v_managers = row_count;
  -- ses liens hors hiérarchie (pointillé, intérim, fonctionnel) prennent fin le jour de la sortie
  update public.org_relations set end_date = p_exit_date
   where (employee_id = p_employee_id or related_employee_id = p_employee_id)
     and start_date <= p_exit_date and (end_date is null or end_date > p_exit_date);
  get diagnostics v_liens = row_count;
  -- accès : retirés tout de suite si la sortie est effective, sinon à traiter à la date de sortie
  if v_effective and e.user_id is not null then
    delete from public.user_roles where user_id = e.user_id;
    get diagnostics v_acces = row_count;
  end if;

  return jsonb_build_object(
    'employee_id', p_employee_id, 'employee_number', e.employee_number,
    'exit_date', p_exit_date, 'exit_reason', p_exit_reason, 'sortie_effective', v_effective,
    'rattachements_manager_clos', v_managers, 'liens_clos', v_liens, 'roles_retires', v_acces,
    'acces_a_retirer_a_la_date', case when v_effective then null else p_exit_date end);
end;
$$;

-- ------------------------------------------------------------ solde de tout compte
create or replace function public.solde_tout_compte(p_employee_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  e public.employees;
  v_start date;
  v_slip jsonb;
  v_t jsonb;
  v_jours numeric := 0;
  v_taux numeric := 0;
  v_conges numeric := 0;
  v_deja_paye boolean;
begin
  if not public.has_role(array['rh', 'paie']) then raise exception 'Réservé à la RH et à la paie'; end if;
  select * into e from public.employees where id = p_employee_id;
  if not found then raise exception 'Salarié introuvable'; end if;
  if e.relieving_date is null then
    raise exception 'La sortie de ce salarié n''est pas enregistrée : utilisez d''abord sortie_salarie';
  end if;
  v_start := date_trunc('month', e.relieving_date)::date;
  -- bulletin du mois de sortie : le moteur applique lui-même les indemnités liées à la sortie
  v_slip := public.compute_salary_slip(p_employee_id, v_start, (v_start + interval '1 month - 1 day')::date);
  v_t := v_slip->'totals';
  v_deja_paye := coalesce((v_slip->'inputs'->>'leave_paid_monthly')::boolean, false);

  select coalesce(sum(b.balance), 0) into v_jours
    from public.v_leave_balances b where b.employee_id = p_employee_id and b.leave_type = 'CONGE_ANNUEL';
  v_jours := greatest(v_jours, 0);
  v_taux := coalesce((v_t->>'gross_pay')::numeric, 0) / 30;
  v_conges := case when v_deja_paye then 0 else round(v_jours * v_taux, 2) end;

  return jsonb_build_object(
    'employee_id', p_employee_id,
    'employee_number', e.employee_number,
    'exit_date', e.relieving_date,
    'exit_reason', e.exit_reason,
    'period', v_slip->'period',
    'gross_pay', v_t->'gross_pay',
    'net_pay', v_t->'net_pay',
    'severance_pay', v_t->'severance_pay',
    'retirement_pay', v_t->'retirement_pay',
    'precarity_allowance', v_t->'precarity_allowance',
    'leave_days_unused', v_jours,
    'leave_daily_rate', round(v_taux, 2),
    'leave_compensation', v_conges,
    'total_due', coalesce((v_t->>'net_pay')::numeric, 0) + v_conges,
    'slip', v_slip,
    'assumptions', jsonb_build_array(
      'Bulletin du mois de sortie calculé par le moteur de paie (compute_salary_slip), indemnités de sortie comprises.',
      case when v_deja_paye then 'Congés payés réglés chaque mois sur le bulletin : aucune indemnité compensatrice due.'
           else 'Indemnité compensatrice de congés = jours de congé annuel non pris × salaire brut du mois / 30 (formule à valider par la RH).' end,
      'Solde de congé annuel de l''année en cours uniquement ; les reliquats des années précédentes ne sont pas repris.'),
    'generated_at', now());
end;
$$;

-- ------------------------------------------------------------ certificat de travail
create or replace function public.certificat_travail(p_employee_id uuid)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  e public.employees;
  v_company text;
  v_poste text;
  v_civ text;
begin
  select * into e from public.employees where id = p_employee_id;
  if not found then raise exception 'Salarié introuvable'; end if;
  if e.relieving_date is null then
    raise exception 'La sortie de ce salarié n''est pas enregistrée : utilisez d''abord sortie_salarie';
  end if;
  select c.name into v_company from public.companies c where c.id = e.company_id;
  select d.name into v_poste from public.designations d where d.id = e.designation_id;
  v_civ := case e.gender when 'F' then 'Madame' else 'Monsieur' end;

  return 'CERTIFICAT DE TRAVAIL' || chr(10) || chr(10) ||
    'Je soussigné(e), représentant(e) de la société ' || coalesce(v_company, 'SOMA') || ', certifie que ' || chr(10) ||
    v_civ || ' ' || e.first_name || ' ' || upper(e.last_name) || ' (matricule ' || e.employee_number || ')' || chr(10) ||
    'a été employé(e) dans notre société du ' || to_char(e.date_of_joining, 'DD/MM/YYYY') ||
    ' au ' || to_char(e.relieving_date, 'DD/MM/YYYY') || ' inclus,' || chr(10) ||
    'en qualité de ' || coalesce(v_poste, 'non renseigné') || ' (contrat : ' || coalesce(e.employment_type, 'non renseigné') || ').' || chr(10) || chr(10) ||
    'Fait à ______________________, le ____ / ____ / ________' || chr(10) || chr(10) ||
    'Signature et cachet de l''employeur : ____________________';
end;
$$;

revoke execute on function public.sortie_salarie(uuid, date, text) from public, anon;
revoke execute on function public.solde_tout_compte(uuid) from public, anon;
revoke execute on function public.certificat_travail(uuid) from public, anon;
grant execute on function public.sortie_salarie(uuid, date, text) to authenticated;
grant execute on function public.solde_tout_compte(uuid) to authenticated;
grant execute on function public.certificat_travail(uuid) to authenticated;

notify pgrst, 'reload schema';
