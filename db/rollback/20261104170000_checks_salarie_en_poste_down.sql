-- Rollback de D-011 : restaure payroll_entry_checks avant correction.
CREATE OR REPLACE FUNCTION public.payroll_entry_checks(p_payroll_entry_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  pe public.payroll_entries;
  v_prev uuid;
  v_out jsonb := '[]'::jsonb;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis pour consulter les contrôles';
  end if;
  select * into pe from public.payroll_entries where id = p_payroll_entry_id;
  if not found then return v_out; end if;

  select id into v_prev from public.payroll_entries
   where period_start < pe.period_start and status = 'Validée'
   order by period_start desc limit 1;

  -- salariés actifs sans bulletin (avec la cause probable : pas de structure salariale)
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('niveau', 'erreur', 'code', 'sans_bulletin',
             'salarie', e.employee_number || ' ' || e.last_name || ' ' || e.first_name,
             'message', case when not exists (select 1 from public.salary_structure_assignments a
                                               where a.employee_id = e.id and a.from_date <= pe.period_end)
                             then 'Salarié actif sans structure salariale : aucun bulletin possible'
                             else 'Salarié actif sans bulletin dans ce traitement' end))
      from public.employees e
     where e.status = 'Active'
       and not exists (select 1 from public.salary_slips s
                        where s.payroll_entry_id = pe.id and s.employee_id = e.id and s.status <> 'Annulé')), '[]'::jsonb);

  -- plusieurs bulletins actifs pour un même salarié
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('niveau', 'erreur', 'code', 'doublon_bulletin',
             'salarie', e.employee_number || ' ' || e.last_name || ' ' || e.first_name,
             'message', 'Plusieurs bulletins actifs pour ce salarié dans le traitement'))
      from public.employees e
     where (select count(*) from public.salary_slips s
             where s.payroll_entry_id = pe.id and s.employee_id = e.id and s.status <> 'Annulé') > 1), '[]'::jsonb);

  -- net nul ou négatif
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('niveau', 'erreur', 'code', 'net_negatif',
             'salarie', e.employee_number || ' ' || e.last_name || ' ' || e.first_name,
             'message', 'Net à payer nul ou négatif'))
      from public.salary_slips s join public.employees e on e.id = s.employee_id
     where s.payroll_entry_id = pe.id and s.status <> 'Annulé' and s.net_pay <= 0), '[]'::jsonb);

  -- variation du net supérieure à 30 % par rapport au dernier mois validé
  if v_prev is not null then
    v_out := v_out || coalesce((
      select jsonb_agg(jsonb_build_object('niveau', 'alerte', 'code', 'variation',
               'salarie', e.employee_number || ' ' || e.last_name || ' ' || e.first_name,
               'message', 'Net ' || round(p.net_pay) || ' → ' || round(s.net_pay) || ' F ('
                          || round(((s.net_pay - p.net_pay) / p.net_pay) * 100) || ' %)'))
        from public.salary_slips s
        join public.salary_slips p on p.employee_id = s.employee_id and p.payroll_entry_id = v_prev and p.status <> 'Annulé'
        join public.employees e on e.id = s.employee_id
       where s.payroll_entry_id = pe.id and s.status <> 'Annulé' and p.net_pay > 0
         and abs((s.net_pay - p.net_pay) / p.net_pay) > 0.30), '[]'::jsonb);
  end if;

  -- aucune variable du mois saisie pour un salarié payé
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('niveau', 'alerte', 'code', 'sans_variables',
             'salarie', e.employee_number || ' ' || e.last_name || ' ' || e.first_name,
             'message', 'Aucune variable du mois saisie (absences, heures supplémentaires)'))
      from public.salary_slips s join public.employees e on e.id = s.employee_id
     where s.payroll_entry_id = pe.id and s.status <> 'Annulé'
       and not exists (select 1 from public.payroll_inputs i where i.employee_id = s.employee_id and i.period = pe.period_start)), '[]'::jsonb);

  -- variables corrigées à la main (écart avec les présences)
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('niveau', 'info', 'code', 'variable_corrigee',
             'salarie', e.employee_number || ' ' || e.last_name || ' ' || e.first_name,
             'message', 'Variables du mois corrigées manuellement (différent des présences)'))
      from public.payroll_inputs i join public.employees e on e.id = i.employee_id
     where i.period = pe.period_start and i.attendance_override), '[]'::jsonb);

  -- demandes de congé encore ouvertes sur la période
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('niveau', 'alerte', 'code', 'conge_en_attente',
             'salarie', e.employee_number || ' ' || e.last_name || ' ' || e.first_name,
             'message', 'Demande de congé du ' || l.from_date || ' au ' || l.to_date || ' non traitée'))
      from public.leave_applications l join public.employees e on e.id = l.employee_id
     where l.status = 'Ouverte' and l.from_date <= pe.period_end and l.to_date >= pe.period_start), '[]'::jsonb);

  return v_out;
end;
$function$

;
