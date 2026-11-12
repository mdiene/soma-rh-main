-- RPR-01 : l'envoi en revue est refusé tant que des salariés attendus n'ont pas de bulletin (liste dans le message).
-- Retour : db/rollback/20261214110000_rpr01_revue_bloquee_si_incomplet_down.sql

CREATE OR REPLACE FUNCTION public.transition_payroll_entry(p_payroll_entry_id uuid, p_target_status text, p_reason text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_entry public.payroll_entries;
  v_allowed boolean := false;
  v_actor uuid := auth.uid();
  v_missing_n integer;
  v_missing_list text;
begin
  select * into v_entry from public.payroll_entries
  where id = p_payroll_entry_id for update;
  if v_entry.id is null then raise exception 'Traitement de paie introuvable'; end if;
  if p_target_status not in ('En revue','Approuvée','Validée','Payée','Clôturée','Réouverte','Annulée') then
    raise exception 'Statut de transition invalide : « % »', p_target_status;
  end if;
  if p_target_status in ('Annulée','Réouverte') and not public.has_role(array['admin']) then
    raise exception 'Seul un administrateur peut annuler ou rouvrir une paie';
  end if;
  if p_target_status in ('Payée','Clôturée') and not public.has_role(array['paie']) then
    raise exception 'Droits insuffisants : rôle « paie » requis pour passer la paie à « % »', p_target_status;
  end if;
  if p_target_status in ('En revue','Validée') and not public.has_role(array['rh','paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis pour passer la paie à « % »', p_target_status;
  end if;
  if p_target_status = 'Approuvée' and not public.has_role(array['rh']) then
    raise exception 'Droits insuffisants : rôle « rh » requis pour approuver une paie';
  end if;

  if p_target_status = 'En revue' and v_entry.status = 'Calculée' then v_allowed := true; end if;
  if p_target_status = 'Approuvée' and v_entry.status = 'En revue' then v_allowed := true; end if;
  if p_target_status = 'Validée' and v_entry.status in ('Calculée','Approuvée') then v_allowed := true; end if;
  if p_target_status = 'Payée' and v_entry.status = 'Validée' then v_allowed := true; end if;
  if p_target_status = 'Clôturée' and v_entry.status in ('Validée','Payée') then v_allowed := true; end if;
  if p_target_status = 'Réouverte' and v_entry.status = 'Clôturée' and nullif(trim(p_reason), '') is not null then v_allowed := true; end if;
  if p_target_status = 'Annulée' and v_entry.status <> 'Clôturée' then v_allowed := true; end if;
  if not v_allowed then
    if p_target_status = 'Réouverte' and v_entry.status = 'Clôturée' then
      raise exception 'Un motif est obligatoire pour rouvrir une paie clôturée';
    end if;
    raise exception 'Transition interdite : la paie est « % » et ne peut pas passer à « % »', v_entry.status, p_target_status;
  end if;

  -- RPR-01 : pas d'envoi en revue tant que des salariés attendus n'ont pas de bulletin (structure salariale manquante, erreur de calcul)
  -- Mêmes salariés que ceux retenus par run_payroll_batch.
  if p_target_status = 'En revue' then
    select count(*), string_agg(x.employee_number || ' ' || x.last_name, ', ' order by x.employee_number) filter (where x.rn <= 10)
      into v_missing_n, v_missing_list
      from (select e.employee_number, e.last_name, row_number() over (order by e.employee_number) as rn
              from public.employees e
             where e.company_id = v_entry.company_id
               and e.status in ('Active', 'Left')
               and e.date_of_joining <= v_entry.period_end
               and (e.relieving_date is null or e.relieving_date >= v_entry.period_start)
               and not exists (select 1 from public.salary_slips s
                                where s.payroll_entry_id = v_entry.id and s.employee_id = e.id and s.status <> 'Annulé')) x;
    if v_missing_n > 0 then
      raise exception 'Envoi en revue refusé : % salarié(s) sans bulletin (%). Affectez-leur une structure salariale puis recalculez.',
        v_missing_n, v_missing_list || case when v_missing_n > 10 then ', …' else '' end;
    end if;
  end if;

  -- D-43 : la validation directe d'une paie « Calculée » (sans revue ni approbation) est une dérogation réservée à l'administrateur, motivée
  if p_target_status = 'Validée' and v_entry.status = 'Calculée' then
    if not public.has_role(array['admin']) then
      raise exception 'La paie doit être approuvée (En revue puis Approuvée) avant d''être validée';
    end if;
    if nullif(trim(p_reason), '') is null then
      raise exception 'Validation sans approbation : un motif de dérogation est obligatoire';
    end if;
  end if;

  -- Lot D (C26-09) : à la 1re paie d'un salarié, la déclaration d'embauche doit être référencée
  if p_target_status = 'Validée' then
    perform public.assert_declaration_embauche(p_payroll_entry_id);
  end if;

  -- I4 : le préparateur ne contrôle pas son propre travail (dérogation admin motivée)
  if p_target_status = 'Approuvée' then
    perform public.payroll_assert_separation(v_entry, 'approuver', p_reason);
  elsif p_target_status = 'Validée' and v_entry.status = 'Calculée' then
    perform public.payroll_assert_separation(v_entry, 'valider', p_reason);
  end if;

  perform set_config('soma.payroll_transition', 'on', true);
  if p_target_status = 'Clôturée' then
    perform public.create_payroll_snapshot(p_payroll_entry_id);
    update public.payroll_entries
       set status = p_target_status, closed_by = v_actor, closed_at = now()
     where id = p_payroll_entry_id;
  elsif p_target_status = 'Réouverte' then
    update public.payroll_entries
       set status = p_target_status, reopened_by = v_actor, reopened_at = now(), reopen_reason = p_reason
     where id = p_payroll_entry_id;
  elsif p_target_status = 'Approuvée' then
    update public.payroll_entries
       set status = p_target_status, approved_by = v_actor, approved_at = now()
     where id = p_payroll_entry_id;
  elsif p_target_status = 'Payée' then
    update public.payroll_entries
       set status = p_target_status, paid_by = v_actor, paid_at = now()
     where id = p_payroll_entry_id;
  elsif p_target_status = 'En revue' then
    update public.payroll_entries
       set status = p_target_status, submitted_by = coalesce(submitted_by, v_actor)
     where id = p_payroll_entry_id;
  elsif p_target_status = 'Validée' then
    update public.payroll_entries
       set status = p_target_status, submitted_at = coalesce(submitted_at, now())
     where id = p_payroll_entry_id;
    update public.salary_slips set status = 'Validé'
     where payroll_entry_id = p_payroll_entry_id and status = 'Brouillon';
  else
    update public.payroll_entries set status = p_target_status where id = p_payroll_entry_id;
  end if;
  update public.payroll_periods set status = p_target_status where id = v_entry.period_id;
  if p_target_status = 'Validée' and v_entry.status = 'Calculée' then
    insert into public.audit_events(actor_id, action, resource_type, resource_id, payroll_entry_id, before_data, after_data, reason)
    values (v_actor, 'validation_derogatoire', 'payroll_entry', p_payroll_entry_id, p_payroll_entry_id,
            jsonb_build_object('status', v_entry.status), jsonb_build_object('status', p_target_status), p_reason);
  end if;
  insert into public.audit_events(actor_id, action, resource_type, resource_id, payroll_entry_id, before_data, after_data, reason)
  values (v_actor, 'transition', 'payroll_entry', p_payroll_entry_id, p_payroll_entry_id,
          jsonb_build_object('status', v_entry.status),
          jsonb_build_object('status', p_target_status), p_reason);
  return p_target_status;
end;
$function$;

revoke execute on function public.transition_payroll_entry(uuid, text, text) from public, anon;
grant execute on function public.transition_payroll_entry(uuid, text, text) to authenticated, service_role;
notify pgrst, 'reload schema';
