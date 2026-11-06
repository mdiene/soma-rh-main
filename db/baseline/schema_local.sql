-- Instantané du schéma public de la base locale (pg_dump --schema-only --no-owner -n public), voir db/baseline/README.md.
-- pg_dump -n public n'inclut pas les extensions : créées ici.
create extension if not exists btree_gist with schema public;
create extension if not exists pgcrypto with schema public;

--
-- PostgreSQL database dump
--

\restrict H4pLm6GqmLNdpQIRnox9gEgKnZCxIdP9kGGCrJXQ9skmJ3JJiaEOhBh2PieRGL2

-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--



--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--



--
-- Name: admin_change_employee_number(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_change_employee_number(p_employee_id uuid, p_new_number text, p_reason text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare v_old text; v_new text := upper(trim(p_new_number));
begin
  if not public.has_role(array['admin']) then
    raise exception 'Seul un administrateur peut changer un matricule';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Le motif du changement est obligatoire';
  end if;
  if v_new !~ '^S[0-9]{4,}$' then
    raise exception 'Format attendu : S suivi d''au moins 4 chiffres (ex. S0027)';
  end if;
  select employee_number into v_old from public.employees where id = p_employee_id for update;
  if v_old is null then raise exception 'Salarié introuvable'; end if;
  if exists (select 1 from public.employees where upper(employee_number) = v_new and id <> p_employee_id) then
    raise exception 'Le matricule % est déjà attribué', v_new;
  end if;
  perform set_config('soma.allow_matricule_change', 'on', true);
  update public.employees set employee_number = v_new where id = p_employee_id;
  perform set_config('soma.allow_matricule_change', '', true);
  insert into public.audit_log(table_name, record_id, action, old_data, new_data, reason)
  values ('employees', p_employee_id, 'changement de matricule',
          jsonb_build_object('employee_number', v_old), jsonb_build_object('employee_number', v_new), trim(p_reason));
  return v_new;
end;
$_$;


--
-- Name: admin_link_employee(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_link_employee(p_user_id uuid, p_employee_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.has_role(array['admin']) then
    raise exception 'Réservé aux administrateurs';
  end if;
  update public.employees set user_id = null where user_id = p_user_id;
  if p_employee_id is not null then
    update public.employees set user_id = p_user_id where id = p_employee_id;
    insert into public.user_roles(user_id, role) values (p_user_id, 'salarie') on conflict do nothing;
  end if;
end;
$$;


--
-- Name: admin_list_users(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_list_users() RETURNS TABLE(user_id uuid, email text, created_at timestamp with time zone, last_sign_in_at timestamp with time zone, roles text[], employee_id uuid, employee_number text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.has_role(array['admin']) then
    raise exception 'Réservé aux administrateurs';
  end if;
  return query
    select u.id, u.email::text, u.created_at, null::timestamptz,
           coalesce(array_agg(r.role order by r.role) filter (where r.role is not null), '{}'),
           e.id, e.employee_number
    from auth.users u
    left join public.user_roles r on r.user_id = u.id
    left join public.employees e on e.user_id = u.id
    group by u.id, u.email, u.created_at, e.id, e.employee_number
    order by u.created_at;
end;
$$;


--
-- Name: apply_period_adjustments(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apply_period_adjustments(p_payroll_entry_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  pe public.payroll_entries;
  p date;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis';
  end if;
  select * into pe from public.payroll_entries where id = p_payroll_entry_id;
  if not found or pe.status in ('Validée', 'Payée', 'Clôturée', 'Annulée') then return; end if;
  p := date_trunc('month', pe.period_start)::date;

  -- libère ce qui avait été appliqué à une période dont le traitement a été annulé
  update public.payroll_corrections c set status = 'En attente', applied_period = null
   where c.status = 'Appliquée' and c.applied_period is not null
     and not exists (select 1 from public.payroll_entries e
                      where date_trunc('month', e.period_start)::date = c.applied_period and e.status <> 'Annulée');
  update public.loan_installments i set status = 'Prévue', applied_period = null
   where i.status = 'Retenue' and i.applied_period is not null
     and not exists (select 1 from public.payroll_entries e
                      where date_trunc('month', e.period_start)::date = i.applied_period and e.status <> 'Annulée');

update public.loans l set status = 'Actif'   where l.status = 'Soldé' and exists (select 1 from public.loan_installments i where i.loan_id = l.id and i.status = 'Prévue');
  create temp table if not exists pg_temp.adj_desired (
    employee_id uuid, component_code text, amount numeric, kind text, source_id uuid
  ) on commit drop;
  truncate pg_temp.adj_desired;

  -- éléments récurrents (rubriques à saisie variable)
  insert into pg_temp.adj_desired
  select r.employee_id, r.component_code, r.amount, 'recurrent', r.id
    from public.recurring_pay_items r
    join public.salary_components c on c.code = r.component_code and c.input_mode = 'variable'
   where r.active and r.from_period <= p and (r.to_period is null or r.to_period >= p);

  -- échéances de prêt échues non encore retenues (ou déjà retenues dans cette période), une ligne par salarié
  insert into pg_temp.adj_desired
  select l.employee_id, 'RET_PRET', sum(i.amount), 'pret', null::uuid
    from public.loan_installments i join public.loans l on l.id = i.loan_id
   where l.status <> 'Annulé'
     and ((i.status = 'Prévue' and i.due_period <= p) or (i.status = 'Retenue' and i.applied_period = p))
   group by l.employee_id;

  -- régularisations en attente (ou déjà appliquées à cette période) venant d'un mois antérieur
  insert into pg_temp.adj_desired
  select c.employee_id, case c.kind when 'gain' then 'REGUL_BRUT' else 'RET_REGUL' end, sum(c.amount), 'regularisation', null::uuid
    from public.payroll_corrections c
   where c.source_period < p and (c.status = 'En attente' or (c.status = 'Appliquée' and c.applied_period = p))
   group by c.employee_id, c.kind;

  -- ne touche que ce qui a changé (pas de bruit dans l'audit à chaque recalcul)
  delete from public.additional_salaries a
   where a.period = p and a.kind <> 'ponctuel'
     and not exists (select 1 from pg_temp.adj_desired d
                      where d.employee_id = a.employee_id and d.component_code = a.component_code
                        and d.amount = a.amount and d.kind = a.kind and d.source_id is not distinct from a.source_id);

  insert into public.additional_salaries (employee_id, period, component_code, amount, kind, source_id, notes)
  select d.employee_id, p, d.component_code, d.amount, d.kind, d.source_id, 'Généré automatiquement'
    from pg_temp.adj_desired d
  on conflict (employee_id, period, component_code) do nothing;

  update public.loan_installments set status = 'Retenue', applied_period = p
   where due_period <= p and status = 'Prévue'
     and loan_id in (select id from public.loans where status <> 'Annulé');
  update public.payroll_corrections set status = 'Appliquée', applied_period = p
   where status = 'En attente' and source_period < p;
  update public.loans l set status = 'Soldé'
   where l.status = 'Actif' and not exists (select 1 from public.loan_installments i where i.loan_id = l.id and i.status = 'Prévue');
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: employee_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    document_type text NOT NULL,
    title text NOT NULL,
    file_name text NOT NULL,
    storage_path text NOT NULL,
    mime_type text NOT NULL,
    size_bytes bigint NOT NULL,
    checksum text,
    created_by uuid DEFAULT auth.uid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    requirement_code text,
    status text DEFAULT 'en_attente'::text NOT NULL,
    rejection_reason text,
    validated_by uuid,
    validated_at timestamp with time zone,
    current_version integer DEFAULT 1 NOT NULL,
    submitted_at timestamp with time zone,
    archived_at timestamp with time zone,
    archived_by uuid,
    thumbnail_path text,
    document_slot smallint DEFAULT 1 NOT NULL,
    CONSTRAINT employee_documents_document_slot_check CHECK ((document_slot > 0)),
    CONSTRAINT employee_documents_document_type_check CHECK ((document_type = ANY (ARRAY['attestation_travail'::text, 'attestation_salaire'::text, 'bulletin'::text, 'justificatif'::text, 'autre'::text, 'piece_identite'::text, 'acte_naissance'::text, 'nationalite_residence'::text, 'casier_judiciaire'::text, 'photo_identite'::text, 'contacts_urgence'::text, 'cv'::text, 'diplomes_attestations'::text, 'certificats_travail'::text, 'situation_matrimoniale'::text, 'actes_enfants'::text, 'certificats_scolarite'::text, 'immatriculation_sociale'::text, 'aptitude_medicale'::text, 'absence_medicale_maternite'::text, 'permis_visa'::text, 'autorisation_parentale'::text]))),
    CONSTRAINT employee_documents_rejection_reason_check CHECK (((status <> 'refuse'::text) OR (NULLIF(TRIM(BOTH FROM rejection_reason), ''::text) IS NOT NULL))),
    CONSTRAINT employee_documents_size_bytes_check CHECK ((size_bytes >= 0)),
    CONSTRAINT employee_documents_status_check CHECK ((status = ANY (ARRAY['en_attente'::text, 'valide'::text, 'refuse'::text])))
);


--
-- Name: archive_employee_document(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_employee_document(p_document_id uuid) RETURNS public.employee_documents
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_document public.employee_documents;
begin
  if not (select public.has_role(array['admin', 'rh'])) then
    raise exception 'Droits administrateur ou RH requis';
  end if;

  update public.employee_documents
  set archived_at = now(), archived_by = (select auth.uid())
  where id = p_document_id and status = 'refuse' and archived_at is null
  returning * into v_document;

  if not found then
    raise exception 'Seul un document refus?? non archiv?? peut ??tre archiv??';
  end if;
  return v_document;
end;
$$;


--
-- Name: assert_declaration_embauche(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_declaration_embauche(p_entry uuid) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare v_list text;
begin
  select string_agg(s.employee_number, ', ' order by s.employee_number) into v_list
    from public.salary_slips s
    join public.employees e on e.id = s.employee_id
   where s.payroll_entry_id = p_entry
     and e.hire_declaration_ref is null
     and not exists (select 1 from public.salary_slips p
                      where p.employee_id = s.employee_id and p.status = 'Validé'
                        and p.period_start < s.period_start and p.payroll_entry_id is distinct from p_entry);
  if v_list is not null then
    raise exception 'Validation refusée : déclaration d''embauche non référencée pour (1re paie) : %', v_list;
  end if;
end $$;


--
-- Name: employee_manager_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_manager_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    manager_employee_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    valid_from date NOT NULL,
    valid_to date,
    delegated_by uuid DEFAULT auth.uid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT employee_manager_assignments_check CHECK ((manager_employee_id <> employee_id)),
    CONSTRAINT employee_manager_assignments_check1 CHECK (((valid_to IS NULL) OR (valid_to >= valid_from)))
);


--
-- Name: assign_manager_employee(uuid, uuid, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assign_manager_employee(p_manager_employee_id uuid, p_employee_id uuid, p_valid_from date, p_valid_to date DEFAULT NULL::date) RETURNS public.employee_manager_assignments
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_assignment public.employee_manager_assignments; v_manager_user_id uuid;
begin
  if not public.has_role(array['rh']) then raise exception 'Réservé au service RH'; end if;
  if p_manager_employee_id = p_employee_id then raise exception 'Un salarié ne peut pas être son propre manager'; end if;
  if p_valid_to is not null and p_valid_to < p_valid_from then raise exception 'La date de fin doit être postérieure à la date de début'; end if;
  select user_id into v_manager_user_id from public.employees where id = p_manager_employee_id and status = 'Active';
  if not found then raise exception 'Le manager doit être un salarié actif'; end if;
  -- un manager n'a pas besoin d'un compte : le rôle applicatif n'est accordé que s'il en a un
  if v_manager_user_id is not null then
    insert into public.user_roles(user_id, role) values (v_manager_user_id, 'manager') on conflict (user_id, role) do nothing;
  end if;
  insert into public.employee_manager_assignments(manager_employee_id, employee_id, valid_from, valid_to, delegated_by)
  values (p_manager_employee_id, p_employee_id, p_valid_from, p_valid_to, (select auth.uid()))
  returning * into v_assignment;
  return v_assignment;
exception
  when exclusion_violation then raise exception 'Une délégation existe déjà sur cette période';
end;
$$;


--
-- Name: attendance_touch(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.attendance_touch() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  new.updated_at := now();
  new.updated_by := coalesce((select auth.uid()), new.updated_by);
  return new;
end;
$$;


--
-- Name: audit_events_to_log(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_events_to_log() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  insert into public.audit_log (occurred_at, actor, table_name, record_id, action, old_data, new_data,
                                reason, payroll_entry_id, result, source_event_id)
  values (new.created_at, new.actor_id, new.resource_type, new.resource_id, new.action, new.before_data,
          new.after_data, new.reason, new.payroll_entry_id, new.result, new.id)
  on conflict (source_event_id) where source_event_id is not null do nothing;
  return new;
end $$;


--
-- Name: audit_log_chain(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_log_chain() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare v_prev text; v_pos bigint;
begin
  perform pg_advisory_xact_lock(hashtext('audit_log_chain'));
  select row_hash, chain_pos into v_prev, v_pos
  from public.audit_log where chain_pos is not null order by chain_pos desc limit 1;
  new.chain_pos := coalesce(v_pos, 0) + 1;
  new.prev_hash := v_prev;
  new.row_hash  := public.audit_row_hash(v_prev, new);
  return new;
end $$;


--
-- Name: audit_log_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_log_immutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  -- seule exception : mise à null de l'acteur quand son compte est supprimé
  if tg_op = 'UPDATE' and new.actor is null
     and (to_jsonb(new) - 'actor') = (to_jsonb(old) - 'actor') then
    return new;
  end if;
  raise exception 'Le journal d''audit est en lecture seule (% refusé).', tg_op using errcode = '42501';
end $$;


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    actor uuid DEFAULT auth.uid(),
    table_name text NOT NULL,
    record_id uuid,
    action text NOT NULL,
    old_data jsonb,
    new_data jsonb,
    reason text,
    record_key text,
    payroll_entry_id uuid,
    result text DEFAULT 'success'::text NOT NULL,
    source_event_id uuid,
    chain_pos bigint,
    prev_hash text,
    row_hash text,
    CONSTRAINT audit_log_result_check CHECK ((result = ANY (ARRAY['success'::text, 'denied'::text, 'error'::text])))
);


--
-- Name: TABLE audit_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.audit_log IS 'Journal des modifications importantes (matricules, référentiels). Alimenté uniquement par des fonctions et déclencheurs.';


--
-- Name: audit_row_hash(text, public.audit_log); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_row_hash(p_prev text, r public.audit_log) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select encode(sha256(convert_to(concat_ws('|',
    coalesce(p_prev, ''), r.chain_pos, extract(epoch from r.occurred_at)::text, r.table_name, r.record_id::text,
    r.record_key, r.action, r.old_data::text, r.new_data::text, r.reason, r.result,
    r.payroll_entry_id::text), 'UTF8')), 'hex')
$$;


--
-- Name: audit_verify(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_verify() RETURNS TABLE(chain_pos bigint, id bigint, problem text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare r public.audit_log; v_prev text := null; v_expected bigint := 1;
begin
  if not (select public.has_role(array['admin','rh'])) and current_user not in ('postgres','soma') then
    raise exception 'Accès refusé : réservé aux rôles admin et rh.' using errcode = '42501';
  end if;
  for r in select * from public.audit_log a where a.chain_pos is not null order by a.chain_pos loop
    if r.chain_pos <> v_expected then
      chain_pos := r.chain_pos; id := r.id; problem := 'position manquante (attendue ' || v_expected || ')'; return next;
      v_expected := r.chain_pos;
    end if;
    if r.prev_hash is distinct from v_prev then
      chain_pos := r.chain_pos; id := r.id; problem := 'empreinte précédente différente'; return next;
    end if;
    if r.row_hash is distinct from public.audit_row_hash(r.prev_hash, r) then
      chain_pos := r.chain_pos; id := r.id; problem := 'contenu modifié'; return next;
    end if;
    v_prev := r.row_hash; v_expected := v_expected + 1;
  end loop;
  if exists (select 1 from public.audit_log a where a.chain_pos is null) then
    chain_pos := null; id := null; problem := 'lignes hors chaîne'; return next;
  end if;
end $$;


--
-- Name: business_audit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.business_audit() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  o jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  n jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  r jsonb := coalesce(n, o);
  heavy text[] := array['calculation', 'updated_at', 'updated_by'];
  o2 jsonb; n2 jsonb;
begin
  o2 := o - heavy; n2 := n - heavy;
  if tg_op = 'UPDATE' and o2 = n2 then
    return null;
  end if;
  insert into public.audit_log (table_name, record_id, record_key, action, old_data, new_data)
  values (tg_table_name,
          case when r ? 'id' then (r->>'id')::uuid end,
          coalesce(r->>'code', r->>'matricule', r->>'user_id', r->>'name'),
          case tg_op when 'INSERT' then 'création' when 'UPDATE' then 'modification' else 'suppression' end,
          o2, n2);
  return null;
end;
$$;


--
-- Name: calculate_salary_slip(uuid, date, date, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_salary_slip(p_employee_id uuid, p_period_start date, p_period_end date, p_payroll_entry_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare
  v_calc jsonb;
  v_emp  jsonb;
  v_tot  jsonb;
  v_id   uuid;
  l      jsonb;
begin
  if not public.has_role(array['paie','rh']) then
    raise exception 'Droits insuffisants : rôle « paie » requis';
  end if;

  if exists (select 1 from public.salary_slips
             where employee_id = p_employee_id and period_start = p_period_start and status = 'Validé') then
    raise exception 'Un bulletin validé existe déjà pour cette période';
  end if;

  v_calc := public.compute_salary_slip(p_employee_id, p_period_start, p_period_end);
  v_emp  := v_calc->'employee';
  v_tot  := v_calc->'totals';

  delete from public.salary_slips
   where employee_id = p_employee_id and period_start = p_period_start and status = 'Brouillon';

  insert into public.salary_slips (
    payroll_entry_id, employee_id, period_start, period_end, status,
    employee_number, employee_name, designation, address, grade_code, grade_class, staff_status,
    employment_type, contract_situation, date_of_joining, seniority_years, seniority_months,
    marital_status, spouses_count, children_count, trimf_parts, ir_parts, payment_mode, hourly_rate,
    gross_pay, income_tax, trimf, total_employee_deductions, net_remuneration, total_non_taxable,
    total_net_deductions, net_pay, employer_charges, payroll_cost,
    ipres_rg_base, ipres_rc_base, css_base, ipm_base, leave_provision, precarity_provision, calculation)
  values (
    p_payroll_entry_id, p_employee_id, p_period_start, p_period_end, 'Brouillon',
    v_emp->>'employee_number', v_emp->>'name', v_emp->>'designation', v_emp->>'address',
    v_emp->>'grade_code', v_emp->>'grade_class', v_emp->>'staff_status',
    v_emp->>'employment_type', v_emp->>'contract_situation', (v_emp->>'date_of_joining')::date,
    (v_emp->>'seniority_years')::int, (v_emp->>'seniority_months')::int,
    v_emp->>'marital_status', (v_emp->>'spouses_count')::smallint, (v_emp->>'children_count')::smallint,
    (v_emp->>'trimf_parts')::numeric, (v_emp->>'ir_parts')::numeric, v_emp->>'payment_mode',
    (v_tot->>'hourly_rate')::numeric,
    (v_tot->>'gross_pay')::numeric, (v_tot->>'income_tax')::numeric, (v_tot->>'trimf')::numeric,
    (v_tot->>'total_employee_deductions')::numeric, (v_tot->>'net_remuneration')::numeric,
    (v_tot->>'total_non_taxable')::numeric, (v_tot->>'total_net_deductions')::numeric,
    (v_tot->>'net_pay')::numeric, (v_tot->>'employer_charges')::numeric, (v_tot->>'payroll_cost')::numeric,
    (v_tot->>'ipres_rg_base')::numeric, (v_tot->>'ipres_rc_base')::numeric,
    (v_tot->>'css_base')::numeric, (v_tot->>'ipm_base')::numeric, (v_tot->>'leave_provision')::numeric,
    (v_tot->>'precarity_provision')::numeric,
    v_calc)
  returning id into v_id;

  for l in select * from jsonb_array_elements(v_calc->'lines')
  loop
    insert into public.salary_slip_details (
      salary_slip_id, component_code, label, section, sort_order, base, quantity, employee_rate,
      gain_amount, deduction_amount, employer_rate, employer_amount)
    values (
      v_id, l->>'code', l->>'label', l->>'section', (l->>'sort')::int,
      (l->>'base')::numeric, (l->>'quantity')::numeric, (l->>'rate')::numeric,
      coalesce((l->>'gain')::numeric, 0), coalesce((l->>'deduction')::numeric, 0),
      (l->>'employer_rate')::numeric, coalesce((l->>'employer')::numeric, 0));
  end loop;

  return v_id;
end;
$$;


--
-- Name: can_see_leave(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_see_leave(p_employee uuid, p_on date) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.user_manages_employee((select auth.uid()), p_employee, p_on)
$$;


--
-- Name: cancel_loan(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_loan(p_loan_id uuid, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis pour annuler un prêt';
  end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Un motif est obligatoire pour annuler un prêt'; end if;
  if not exists (select 1 from public.loans where id = p_loan_id and status = 'Actif') then
    raise exception 'Prêt introuvable ou déjà soldé/annulé';
  end if;
  -- les échéances déjà retenues restent dues : seules les échéances à venir sont annulées
  update public.loan_installments set status = 'Annulée' where loan_id = p_loan_id and status = 'Prévue';
  update public.loans set status = 'Annulé', cancel_reason = trim(p_reason) where id = p_loan_id;
end;
$$;


--
-- Name: cancel_my_request(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_my_request(p_request_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_request_id uuid;
begin
  update public.employee_requests
     set status = 'Annulée'
   where id = p_request_id
     and employee_id = (select public.my_employee_id())
     and status = 'Ouverte'
  returning id into v_request_id;

  if not found then
    raise exception 'Demande introuvable ou déjà traitée';
  end if;

  insert into public.employee_request_history(request_id, status, actor_id)
  values (v_request_id, 'Annulée', (select auth.uid()));
end;
$$;


--
-- Name: cancel_payroll_correction(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_payroll_correction(p_correction_id uuid, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis';
  end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Un motif est obligatoire pour annuler une régularisation'; end if;
  update public.payroll_corrections
     set status = 'Annulée', reason = reason || ' [annulée : ' || trim(p_reason) || ']'
   where id = p_correction_id and status = 'En attente';
  if not found then raise exception 'Seule une régularisation « En attente » peut être annulée'; end if;
end;
$$;


--
-- Name: cancel_payroll_entry(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_payroll_entry(p_payroll_entry_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.has_role(array['admin']) then
    raise exception 'Seul un administrateur peut annuler un traitement';
  end if;
  perform set_config('soma.payroll_transition', 'on', true);
  update public.salary_slips set status = 'Annulé' where payroll_entry_id = p_payroll_entry_id;
  update public.payroll_entries set status = 'Annulée' where id = p_payroll_entry_id;
end;
$$;


--
-- Name: cash_breakdown(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cash_breakdown(p_payroll_entry_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare
  c_denoms constant integer[] := array[10000, 5000, 2000, 1000, 500, 100, 50, 25, 10, 5, 1];
  o record; d integer; rest bigint; k bigint;
  v_tot jsonb := '{}'::jsonb; v_emp jsonb := '[]'::jsonb; v_counts jsonb; v_total bigint := 0;
  v_cnt bigint[];
begin
  if not public.has_role(array['paie', 'rh']) then
    raise exception 'Droits insuffisants : rôle « paie » ou « rh » requis';
  end if;
  v_cnt := array_fill(0::bigint, array[array_length(c_denoms, 1)]);
  for o in select * from public.payment_orders(p_payroll_entry_id) where mode ~* 'esp' loop
    rest := o.amount; v_counts := '{}'::jsonb;
    for i in 1 .. array_length(c_denoms, 1) loop
      d := c_denoms[i]; k := rest / d; rest := rest - k * d;
      if k > 0 then v_counts := v_counts || jsonb_build_object(d::text, k); v_cnt[i] := v_cnt[i] + k; end if;
    end loop;
    v_total := v_total + o.amount;
    v_emp := v_emp || jsonb_build_object('matricule', o.employee_number, 'nom', o.employee_name, 'montant', o.amount, 'coupures', v_counts);
  end loop;
  for i in 1 .. array_length(c_denoms, 1) loop
    if v_cnt[i] > 0 then v_tot := v_tot || jsonb_build_object(c_denoms[i]::text, v_cnt[i]); end if;
  end loop;
  return jsonb_build_object('total_especes', v_total, 'coupures', v_tot, 'salaries', v_emp);
end;
$$;


--
-- Name: certificat_travail(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.certificat_travail(p_employee_id uuid) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
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


--
-- Name: check_journal_imputation(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_journal_imputation(p_payroll_entry_id uuid) RETURNS TABLE(line_no integer, account text, has_imputation boolean, message text)
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
begin
  RETURN QUERY
  SELECT line_no, account,
    CASE WHEN account IS NOT NULL AND account != '' THEN true ELSE false END as has_imputation,
    CASE WHEN account IS NULL OR account = '' THEN 'Rubrique sans imputation comptable' ELSE NULL END as message
  FROM public.v_accounting_journal
  WHERE payroll_entry_id = p_payroll_entry_id
  AND (account IS NULL OR account = '');
end;
$$;


--
-- Name: claim_first_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.claim_first_admin() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentification requise';
  end if;
  if exists (select 1 from public.user_roles where role = 'admin') then
    return false;
  end if;
  insert into public.user_roles(user_id, role) values ((select auth.uid()), 'admin');
  return true;
end;
$$;


--
-- Name: close_manager_assignment(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.close_manager_assignment(p_assignment_id uuid, p_valid_to date) RETURNS public.employee_manager_assignments
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v public.employee_manager_assignments;
begin
  if not public.has_role(array['rh']) then raise exception 'Réservé au service RH'; end if;
  select * into v from public.employee_manager_assignments where id = p_assignment_id;
  if not found then raise exception 'Affectation introuvable'; end if;
  if p_valid_to < v.valid_from then
    delete from public.employee_manager_assignments where id = p_assignment_id;
    v.valid_to := p_valid_to;
    return v;
  end if;
  update public.employee_manager_assignments set valid_to = p_valid_to where id = p_assignment_id returning * into v;
  return v;
end;
$$;


--
-- Name: compute_income_tax(numeric, numeric, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compute_income_tax(p_monthly_gross numeric, p_parts numeric, p_date date) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare
  v_set     public.payroll_settings;
  v_slab    uuid;
  v_annual  numeric;
  v_taxable numeric;
  v_gross_tax numeric := 0;
  v_red     numeric := 0;
  v_parts   numeric;
  r         record;
  v_prev_from numeric;
  v_prev_rate numeric;
begin
  v_set  := public.payroll_settings_at(p_date);
  v_slab := public.tax_slab_at(p_date);
  v_annual := p_monthly_gross * 12;
  v_taxable := trunc(round(v_annual - least(v_annual * v_set.ir_abatement_rate, v_set.ir_abatement_cap), 6), -3);

  -- barème progressif cumulatif
  v_prev_from := null;
  for r in
    select b.from_amount, b.rate from public.tax_slab_brackets b
    where b.slab_id = v_slab order by b.from_amount
  loop
    if v_prev_from is not null and v_taxable > v_prev_from then
      v_gross_tax := v_gross_tax + (least(v_taxable, r.from_amount) - v_prev_from) * v_prev_rate;
    end if;
    v_prev_from := r.from_amount;
    v_prev_rate := r.rate;
  end loop;
  if v_prev_from is not null and v_taxable > v_prev_from then
    v_gross_tax := v_gross_tax + (v_taxable - v_prev_from) * v_prev_rate;
  end if;

  -- réduction pour charges de famille (parts plafonnées à 5)
  v_parts := least(coalesce(p_parts, 1), 5);
  select least(f.max_amount, greatest(v_gross_tax * f.rate, f.min_amount))
    into v_red
  from public.ir_family_reductions f
  where f.slab_id = v_slab and f.parts = v_parts;
  v_red := coalesce(v_red, 0);

  return jsonb_build_object(
    'annual_gross', v_annual,
    'taxable_income', v_taxable,
    'gross_tax', v_gross_tax,
    'family_reduction', v_red,
    'annual_tax', greatest(0, v_gross_tax - v_red),
    'monthly_tax', greatest(0, v_gross_tax - v_red) / 12
  );
end;
$$;


--
-- Name: compute_salary_slip(uuid, date, date, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compute_salary_slip(p_employee_id uuid, p_period_start date, p_period_end date, p_sursalaire numeric DEFAULT NULL::numeric) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare
  s     public.payroll_settings;
  e     public.employees;
  ct    public.contract_types;          -- référentiel du type de contrat (lot 7)
  g     public.employee_grades;
  a     public.salary_structure_assignments;
  pi    public.payroll_inputs;
  v_period      date := date_trunc('month', p_period_start)::date;
  v_designation text;
  v_situation   text;
  v_is_work     boolean;
  v_is_presta   boolean;
  v_is_cadre    boolean;
  H             numeric;          -- 173,33
  v_base        numeric;
  v_sursal      numeric;
  v_fees        numeric;
  v_other_fixed numeric;
  v_fixed_sum   numeric;          -- SUM(SALAIRE DE BASE : xxxxxxxx)
  v_th          numeric;          -- TH
  v_anc         integer;          -- ancienneté (années)
  v_abs         numeric; v_sick numeric; v_sick_rate numeric; v_meals numeric;
  v_hs15 numeric; v_hs40 numeric; v_hs60 numeric; v_hs100 numeric; v_hs_total numeric;
  v_prime_anc   numeric;
  v_ret_abs     numeric;
  v_ind_mal     numeric;
  v_var_gross   numeric := 0;
  v_tabaski     numeric := 0;
  v_alloc_conge numeric;
  v_precarite   numeric := 0;
  v_mt15 numeric; v_mt40 numeric; v_mt60 numeric; v_mt100 numeric;
  v_k15 numeric; v_k40 numeric; v_k60 numeric; v_k100 numeric;
  v_brut        numeric;
  v_ir_detail   jsonb;
  v_ir          numeric := 0;
  v_trimf       numeric := 0;
  v_cfce        numeric := 0;
  v_brs         numeric := 0;
  v_rg_base numeric := 0; v_rg_sal numeric; v_rg_pat numeric;
  v_rc_base numeric := 0; v_rc_sal numeric; v_rc_pat numeric;
  v_css_base numeric := 0; v_af numeric := 0; v_at numeric;
  v_ipm_base numeric; v_ipm_sal numeric; v_ipm_pat numeric;
  v_total_ret   numeric;
  v_charges_pat numeric;
  v_net_rem     numeric;
  v_transport numeric := 0; v_panier numeric; v_km numeric := 0;
  v_licenc numeric := 0; v_retraite numeric := 0;
  v_special numeric := 0; v_funeral numeric := 0;   -- lot B : indemnité spéciale (C26-04), frais funéraires (C26-28)
  v_er public.exit_reasons; v_sen_months integer := 0;
  v_var_nontax  numeric := 0;
  v_net_ded     numeric := 0;
  v_appoint_prev numeric;
  v_net_pay     numeric;
  v_payroll_cost numeric;
  v_leave_prov  numeric := 0;
  v_prec_prov   numeric := 0;
  v_lines       jsonb := '[]'::jsonb;
  r             record;
begin
  s := public.payroll_settings_at(p_period_end);
  if s.id is null then
    raise exception 'Aucun paramétrage de paie en vigueur au %', p_period_end;
  end if;
  H := s.monthly_hours;

  select * into e from public.employees where id = p_employee_id;
  if e.id is null then
    raise exception 'Salarié % introuvable', p_employee_id;
  end if;
  select * into g from public.employee_grades where id = e.grade_id;
  select * into ct from public.contract_types where code = e.employment_type;
  select name into v_designation from public.designations where id = e.designation_id;

  select * into a from public.salary_structure_assignments
   where employee_id = e.id and from_date <= p_period_end
   order by from_date desc limit 1;
  if a.id is null then
    raise exception 'Aucune structure salariale affectée à % (%)', e.employee_number, e.last_name;
  end if;

  select * into pi from public.payroll_inputs where employee_id = e.id and period = v_period;

  -- -------------------------------------------------------- situation contrat
  -- nature du contrat lue dans le référentiel ; repli sur l'ancienne règle si le code est inconnu
  v_situation := case
    when ct.code is null then case when e.employment_type in ('CDI','CDD') then 'TRAVAIL' else e.employment_type end
    when ct.nature in ('TRAVAIL', 'PRESTATION', 'STAGE', 'APPRENTISSAGE') then ct.nature
    else ct.code end;
  v_is_work   := v_situation = 'TRAVAIL';
  v_is_presta := v_situation = 'PRESTATION';
  v_is_cadre  := lower(coalesce(g.staff_status, '')) = 'cadres';

  -- ------------------------------------------------------------ éléments fixes
  v_base        := coalesce(a.base_salary, g.base_salary, 0);
  v_sursal      := coalesce(p_sursalaire, a.sursalaire, 0);
  v_fees        := coalesce(a.fees, 0);
  v_other_fixed := coalesce(a.other_fixed, 0);
  v_fixed_sum   := v_base + v_sursal + v_fees + v_other_fixed;
  v_th          := v_fixed_sum / s.hourly_rate_divisor;

  -- ------------------------------------------------------- éléments variables
  v_abs       := coalesce(pi.absence_hours, 0);
  v_sick      := coalesce(pi.sick_leave_hours, 0);
  v_sick_rate := coalesce(pi.sick_leave_rate, 1);
  v_meals     := coalesce(pi.meal_count, 0);
  v_hs15  := coalesce(pi.overtime_15, 0);
  v_hs40  := coalesce(pi.overtime_40, 0);
  v_hs60  := coalesce(pi.overtime_60, 0);
  v_hs100 := coalesce(pi.overtime_100, 0);
  v_hs_total := v_hs15 + v_hs40 + v_hs60 + v_hs100;
  v_alloc_conge  := coalesce(pi.leave_allowance, 0);
  v_appoint_prev := coalesce(pi.previous_rounding, 0);

  -- ancienneté = DATEDIF(date d'entrée ; fin de période + 1 ; "y")
  v_anc := coalesce(public.excel_datedif(e.date_of_joining, p_period_end + 1, 'y'), 0);

  -- PRIME D'ANCIENNETE (AK)
  if v_anc < s.seniority_min_years and v_is_work then
    v_prime_anc := 0;
  else
    v_prime_anc := v_base / H * (H - v_abs + v_hs_total) * v_anc / 100.0;
  end if;

  -- Retenues absences (AL) et indemnité maladie (AM)
  v_ret_abs := - v_fixed_sum / H * v_abs;
  v_ind_mal := v_fixed_sum / H * v_sick * v_sick_rate;

  -- primes variables imposables (AN..AX)
  for r in
    select x.component_code, x.amount
    from public.additional_salaries x
    join public.salary_components c on c.code = x.component_code
    where x.employee_id = e.id and x.period = v_period and c.component_type = 'gross_earning'
  loop
    v_var_gross := v_var_gross + r.amount;
    if r.component_code = 'GRATIF_TABASKI' then v_tabaski := v_tabaski + r.amount; end if;
  end loop;

  -- PRECARITE (AZ) : CDD/COD sortis au plus tard en fin de période
  if coalesce(ct.precarity_eligible, e.employment_type in ('CDD','COD')) and e.relieving_date is not null and e.relieving_date <= p_period_end then
    v_precarite := (v_fixed_sum + v_prime_anc + v_tabaski)
                   * coalesce(public.excel_datedif(e.date_of_joining, e.relieving_date, 'm'), 0)
                   * s.precarity_rate;
  end if;

  -- Heures supplémentaires (BA..BD)
  -- lot G (C26-27) : coefficients lus dans overtime_rates (CCNI art. 49) ; repli sur les valeurs historiques
  -- tranche « 60 » = HS_NUIT (HS_REPOS_FERIE_JOUR a le même taux) ; tranche « 100 » = HS_REPOS_FERIE_NUIT
  v_k15  := public.hs_majoration('HS_JOUR_8_PREMIERES', 1.15);
  v_k40  := public.hs_majoration('HS_JOUR_AU_DELA',     1.40);
  v_k60  := public.hs_majoration('HS_NUIT',             1.60);
  v_k100 := public.hs_majoration('HS_REPOS_FERIE_NUIT', 2.00);
  v_mt15  := v_hs15  * v_th * v_k15;
  v_mt40  := v_hs40  * v_th * v_k40;
  v_mt60  := v_hs60  * v_th * v_k60;
  v_mt100 := v_hs100 * v_th * v_k100;

  -- BRUT (BE) = SOMME(SALAIRE DE BASE : MT HS200%)
  v_brut := v_fixed_sum + v_prime_anc + v_ret_abs + v_ind_mal + v_var_gross
          + v_alloc_conge + v_precarite + v_mt15 + v_mt40 + v_mt60 + v_mt100;

  -- ----------------------------------------------------- impôts et cotisations
  if v_is_work then
    v_ir_detail := public.compute_income_tax(v_brut, e.ir_parts, p_period_end);
    v_ir    := (v_ir_detail->>'monthly_tax')::numeric;
    v_trimf := public.compute_trimf(v_brut, e.trimf_parts, p_period_end);
    v_cfce  := v_brut * s.cfce_rate;
    v_rg_base := least(v_brut, s.ipres_rg_ceiling);
    if v_is_cadre then
      v_rc_base := least(v_brut, s.ipres_rc_ceiling);
    end if;
  end if;
  if v_is_presta then
    v_brs := v_brut * s.brs_rate;
  end if;

  v_rg_sal := v_rg_base * s.ipres_rg_rate * s.ipres_rg_employee_share;
  v_rg_pat := v_rg_base * s.ipres_rg_rate * (1 - s.ipres_rg_employee_share);
  v_rc_sal := v_rc_base * s.ipres_rc_rate * s.ipres_rc_employee_share;
  v_rc_pat := v_rc_base * s.ipres_rc_rate * (1 - s.ipres_rc_employee_share);

  if not v_is_presta then
    v_css_base := least(v_brut, s.css_ceiling);
  end if;
  if v_is_work then
    v_af := v_css_base * s.css_af_rate;
  end if;
  v_at := v_css_base * s.css_at_rate;

  v_ipm_base := least(v_brut, s.ipm_ceiling);
  v_ipm_sal  := v_ipm_base * s.ipm_rate * s.ipm_employee_share;
  v_ipm_pat  := v_ipm_base * s.ipm_rate * (1 - s.ipm_employee_share);

  v_total_ret   := v_ir + v_trimf + v_brs + v_rg_sal + v_rc_sal + v_ipm_sal;      -- CB
  v_charges_pat := v_cfce + v_rg_pat + v_rc_pat + v_af + v_at + v_ipm_pat;        -- CC
  v_net_rem     := v_brut - v_total_ret;                                          -- CE

  -- ------------------------------------------------ indemnités non imposables
  if a.transport_mode = 'Prime de transport' then
    v_transport := (s.transport_allowance / H) * (H - (v_abs / 8));
  elsif a.transport_mode = 'Indemnité kilométrique' then
    v_km := (s.km_allowance / H) * (H - (v_abs / 8));
  end if;
  v_panier := v_meals * s.smig_hourly * s.meal_allowance_factor;

  if coalesce(ct.severance_eligible, e.employment_type = 'CDI') and e.relieving_date is not null and e.relieving_date <= p_period_end then
    -- lot B : les droits viennent de la table exit_reasons (plus de codes en dur)
    select * into v_er from public.exit_reasons where code = e.exit_reason;
    v_sen_months := coalesce(public.excel_datedif(e.date_of_joining, e.relieving_date + 1, 'm'), 0);
    if coalesce(v_er.severance_eligible, false) and v_sen_months >= s.severance_min_months then   -- C26-05
      v_licenc := public.severance_coefficient(e.date_of_joining, e.relieving_date, 'LICENCIEMENT')
                  * (v_base + v_sursal + v_prime_anc);
    end if;
    if coalesce(v_er.retirement_indemnity, false) then
      v_retraite := public.severance_coefficient(e.date_of_joining, e.relieving_date, 'RETRAITE')
                    * (v_base + v_sursal + v_prime_anc);
    end if;
    -- base « un mois de salaire » = salaire de base + sursalaire + prime d'ancienneté (à confirmer)
    if coalesce(v_er.special_indemnity_months, 0) > 0 then                                        -- C26-04
      v_special := v_er.special_indemnity_months * (v_base + v_sursal + v_prime_anc);
    end if;
    if coalesce(v_er.funeral_indemnity_months, 0) > 0 then                                        -- C26-28 (CCNI art. 83)
      v_funeral := v_er.funeral_indemnity_months * (v_base + v_sursal + v_prime_anc);
    end if;
  end if;

  select coalesce(sum(x.amount) filter (where c.component_type = 'non_taxable_earning'), 0),
         coalesce(sum(x.amount) filter (where c.component_type = 'net_deduction'), 0)
    into v_var_nontax, v_net_ded
  from public.additional_salaries x
  join public.salary_components c on c.code = x.component_code
  where x.employee_id = e.id and x.period = v_period;

  -- NET A PAYER (CS = CT)
  v_net_pay := v_net_rem + v_transport + v_panier + v_km + v_licenc + v_retraite + v_special + v_funeral
             + v_var_nontax - v_net_ded + v_appoint_prev;

  -- MASSE SALARIALE (CY)
  v_payroll_cost := v_brut + v_charges_pat + v_transport + v_panier + v_km + v_licenc
                  + v_retraite + v_special + v_funeral + v_var_nontax + v_appoint_prev;

  -- PROVISION CONGE du mois (DD)
  if v_is_work and not a.leave_paid_monthly then
    v_leave_prov := v_brut / 12;
  end if;

  -- PROVISION PRECARITE du mois : CDD/COD en cours (pas de sortie sur la période).
  -- Même assiette que l'indemnité AZ, pour un mois. Le mois de sortie, l'indemnité
  -- est payée dans le brut et la provision du mois vaut 0. N'entre ni dans le brut ni dans le net.
  if coalesce(ct.precarity_eligible, e.employment_type in ('CDD','COD')) and (e.relieving_date is null or e.relieving_date > p_period_end) then
    v_prec_prov := (v_fixed_sum + v_prime_anc + v_tabaski) * s.precarity_rate;
  end if;

  -- ------------------------------------------------- lignes du bulletin
  v_lines := v_lines || jsonb_build_array(
    jsonb_build_object('code','SAL_BASE','label','Salaire de base','section','gain','sort',10,
      'base', v_base / H, 'quantity', H, 'rate', 1, 'gain', v_base),
    jsonb_build_object('code','SURSALAIRE','label','Sursalaire','section','gain','sort',11,
      'base', v_sursal / H, 'quantity', H, 'rate', 1, 'gain', v_sursal),
    jsonb_build_object('code','PRIME_ANC','label','Prime d''ancienneté','section','gain','sort',12,
      'base', v_base / H, 'quantity', H - v_abs + v_hs_total,
      'rate', case when v_prime_anc = 0 then 0 else v_anc / 100.0 end, 'gain', v_prime_anc)
  );
  if v_fees <> 0 then
    v_lines := v_lines || jsonb_build_object('code','HONORAIRES','label','Honoraires prestataires',
      'section','gain','sort',13,'gain', v_fees);
  end if;
  if v_other_fixed <> 0 then
    v_lines := v_lines || jsonb_build_object('code','AUTRE_FIXE','label','Autre élément fixe',
      'section','gain','sort',14,'gain', v_other_fixed);
  end if;
  if v_abs <> 0 then
    v_lines := v_lines || jsonb_build_object('code','RET_ABSENCE','label','Retenues absences',
      'section','gain','sort',15,'base', v_fixed_sum / H,'quantity', v_abs,'rate',1,'gain', v_ret_abs);
  end if;
  for r in
    select x.component_code, x.amount, c.name, coalesce(c.rubric_number, 21) as rn
    from public.additional_salaries x
    join public.salary_components c on c.code = x.component_code
    where x.employee_id = e.id and x.period = v_period and c.component_type = 'gross_earning'
    order by c.rubric_number nulls last, c.code
  loop
    v_lines := v_lines || jsonb_build_object('code', r.component_code, 'label', r.name,
      'section','gain','sort', r.rn, 'gain', r.amount);
  end loop;
  if v_sick <> 0 then
    v_lines := v_lines || jsonb_build_object('code','IND_MALADIE','label','Indemnité de maladie',
      'section','gain','sort',22,'base', v_fixed_sum / H,'quantity', v_sick,'rate', v_sick_rate,'gain', v_ind_mal);
  end if;
  if v_alloc_conge <> 0 then
    v_lines := v_lines || jsonb_build_object('code','ALLOC_CONGE','label','Allocation congé',
      'section','gain','sort',23,'base', v_alloc_conge * 12,'quantity', 1/12.0,'rate',1,'gain', v_alloc_conge);
  end if;
  if v_precarite <> 0 then
    v_lines := v_lines || jsonb_build_object('code','IND_PRECARITE','label','Indemnité de fin de contrat',
      'section','gain','sort',24,'base', v_precarite / s.precarity_rate,'quantity',1,'rate', s.precarity_rate,'gain', v_precarite);
  end if;
  if v_hs15 <> 0 then
    v_lines := v_lines || jsonb_build_object('code','HS_15','label','Heures sup. majorées à 15%',
      'section','gain','sort',25,'base', v_th,'quantity', v_hs15,'rate',v_k15,'gain', v_mt15);
  end if;
  if v_hs40 <> 0 then
    v_lines := v_lines || jsonb_build_object('code','HS_40','label','Heures sup. majorées à 40%',
      'section','gain','sort',26,'base', v_th,'quantity', v_hs40,'rate',v_k40,'gain', v_mt40);
  end if;
  if v_hs60 <> 0 then
    v_lines := v_lines || jsonb_build_object('code','HS_60','label','Heures sup. majorées à 60%',
      'section','gain','sort',27,'base', v_th,'quantity', v_hs60,'rate',v_k60,'gain', v_mt60);
  end if;
  if v_hs100 <> 0 then
    v_lines := v_lines || jsonb_build_object('code','HS_100','label','Heures sup. majorées à 100%',
      'section','gain','sort',28,'base', v_th,'quantity', v_hs100,'rate',v_k100,'gain', v_mt100);
  end if;

  v_lines := v_lines || jsonb_build_array(
    jsonb_build_object('code','IR','label','Impôt sur le revenu','section','retenue','sort',51,
      'base', v_brut, 'quantity', e.ir_parts, 'deduction', v_ir),
    jsonb_build_object('code','TRIMF','label','Retenue TRIMF','section','retenue','sort',52,
      'base', v_brut, 'quantity', e.trimf_parts, 'deduction', v_trimf),
    jsonb_build_object('code','IPRES_RG','label','IPRES Régime Général','section','retenue','sort',53,
      'base', v_rg_base, 'rate', s.ipres_rg_rate * s.ipres_rg_employee_share, 'deduction', v_rg_sal,
      'employer_rate', s.ipres_rg_rate * (1 - s.ipres_rg_employee_share), 'employer', v_rg_pat),
    jsonb_build_object('code','IPRES_RC','label','IPRES Régime C. Cadre','section','retenue','sort',54,
      'base', v_rc_base,
      'rate', case when v_rc_base = 0 then null else s.ipres_rc_rate * s.ipres_rc_employee_share end,
      'deduction', v_rc_sal,
      'employer_rate', case when v_rc_base = 0 then null else s.ipres_rc_rate * (1 - s.ipres_rc_employee_share) end,
      'employer', v_rc_pat),
    jsonb_build_object('code','IPM','label','Cotisations IPM','section','retenue','sort',55,
      'base', v_ipm_base, 'rate', s.ipm_rate * s.ipm_employee_share, 'deduction', v_ipm_sal,
      'employer_rate', s.ipm_rate * (1 - s.ipm_employee_share), 'employer', v_ipm_pat)
  );
  if v_brs <> 0 then
    v_lines := v_lines || jsonb_build_object('code','BRS','label','BRS (5%)','section','retenue','sort',56,
      'base', v_brut, 'rate', s.brs_rate, 'deduction', v_brs);
  end if;
  v_lines := v_lines || jsonb_build_array(
    jsonb_build_object('code','CSS_AF','label','CSS - Allocations familiales','section','patronal','sort',57,
      'base', v_css_base, 'employer_rate', s.css_af_rate, 'employer', v_af),
    jsonb_build_object('code','CSS_AT','label','CSS - Accident de travail','section','patronal','sort',58,
      'base', v_css_base, 'employer_rate', s.css_at_rate, 'employer', v_at),
    jsonb_build_object('code','CFCE','label','CFCE','section','patronal','sort',59,
      'base', v_brut, 'employer_rate', s.cfce_rate, 'employer', v_cfce)
  );

  if v_transport <> 0 then
    v_lines := v_lines || jsonb_build_object('code','IND_TRANSPORT','label','Indemnité de transport',
      'section','indemnite','sort',70,'base', s.transport_allowance / H,'quantity', H - v_abs / 8,'rate',1,'gain', v_transport);
  end if;
  if v_panier <> 0 then
    v_lines := v_lines || jsonb_build_object('code','IND_PANIER','label','Indemnité de panier',
      'section','indemnite','sort',71,'base', s.smig_hourly * s.meal_allowance_factor,'quantity', v_meals,'rate',1,'gain', v_panier);
  end if;
  if v_km <> 0 then
    v_lines := v_lines || jsonb_build_object('code','IND_KM','label','Indemnité kilométrique',
      'section','indemnite','sort',72,'base', s.km_allowance / H,'quantity', H - v_abs / 8,'rate',1,'gain', v_km);
  end if;
  if v_licenc <> 0 then
    v_lines := v_lines || jsonb_build_object('code','IND_LICENCIEMENT','label','Indemnité de licenciement',
      'section','indemnite','sort',73,'gain', v_licenc);
  end if;
  if v_retraite <> 0 then
    v_lines := v_lines || jsonb_build_object('code','IND_RETRAITE','label','Indemnité de départ à la retraite',
      'section','indemnite','sort',74,'gain', v_retraite);
  end if;
  if v_special <> 0 then
    v_lines := v_lines || jsonb_build_object('code','IND_SPECIALE','label','Indemnité spéciale (1 mois)',
      'section','indemnite','sort',75,'gain', v_special);
  end if;
  if v_funeral <> 0 then
    v_lines := v_lines || jsonb_build_object('code','IND_FRAIS_FUNERAIRES','label','Participation aux frais funéraires',
      'section','indemnite','sort',76,'gain', v_funeral);
  end if;
  for r in
    select x.component_code, x.amount, c.name, c.component_type, coalesce(c.rubric_number, 79) as rn
    from public.additional_salaries x
    join public.salary_components c on c.code = x.component_code
    where x.employee_id = e.id and x.period = v_period
      and c.component_type in ('non_taxable_earning','net_deduction')
    order by c.rubric_number nulls last, c.code
  loop
    if r.component_type = 'non_taxable_earning' then
      v_lines := v_lines || jsonb_build_object('code', r.component_code, 'label', r.name,
        'section','indemnite','sort', r.rn, 'gain', r.amount);
    else
      v_lines := v_lines || jsonb_build_object('code', r.component_code, 'label', r.name,
        'section','retenue_net','sort', r.rn, 'deduction', r.amount);
    end if;
  end loop;
  if v_appoint_prev <> 0 then
    v_lines := v_lines || jsonb_build_object('code','APPOINT_PREC','label','Appoint du mois précédent',
      'section','appoint','sort',81,'gain', v_appoint_prev);
  end if;

  return jsonb_build_object(
    'employee', jsonb_build_object(
      'id', e.id, 'employee_number', e.employee_number,
      'name', upper(trim(e.first_name) || ' ' || trim(e.last_name)),
      'designation', v_designation, 'address', e.address,
      'grade_code', g.code, 'grade_class', g.grade_class, 'staff_status', g.staff_status,
      'employment_type', e.employment_type, 'contract_situation', v_situation,
      'date_of_joining', e.date_of_joining,
      'seniority_years', coalesce(public.excel_datedif(e.date_of_joining, p_period_end, 'y'), 0),
      'seniority_months', coalesce(public.excel_datedif(e.date_of_joining, p_period_end + 1, 'ym'), 0),
      'seniority_for_bonus', v_anc,
      'marital_status', e.marital_status, 'spouses_count', e.spouses_count,
      'children_count', e.children_count, 'trimf_parts', e.trimf_parts, 'ir_parts', e.ir_parts,
      'payment_mode', e.payment_mode),
    'period', jsonb_build_object('start', p_period_start, 'end', p_period_end),
    'inputs', jsonb_build_object(
      'base_salary', v_base, 'sursalaire', v_sursal, 'fees', v_fees, 'other_fixed', v_other_fixed,
      'absence_hours', v_abs, 'sick_leave_hours', v_sick, 'sick_leave_rate', v_sick_rate,
      'meal_count', v_meals, 'overtime_15', v_hs15, 'overtime_40', v_hs40,
      'overtime_60', v_hs60, 'overtime_100', v_hs100, 'leave_allowance', v_alloc_conge,
      'previous_rounding', v_appoint_prev, 'transport_mode', a.transport_mode,
      'leave_paid_monthly', a.leave_paid_monthly, 'target_net', a.target_net),
    'lines', v_lines,
    'income_tax_detail', v_ir_detail,
    'totals', jsonb_build_object(
      'hourly_rate', v_th,
      'fixed_sum', v_fixed_sum,
      'seniority_bonus', v_prime_anc,
      'absence_deduction', v_ret_abs,
      'sick_allowance', v_ind_mal,
      'variable_gross', v_var_gross,
      'leave_allowance', v_alloc_conge,
      'precarity_allowance', v_precarite,
      'overtime_amount', v_mt15 + v_mt40 + v_mt60 + v_mt100,
      'gross_pay', v_brut,
      'income_tax', v_ir,
      'trimf', v_trimf,
      'cfce', v_cfce,
      'brs', v_brs,
      'ipres_rg_base', v_rg_base, 'ipres_rg_employee', v_rg_sal, 'ipres_rg_employer', v_rg_pat,
      'ipres_rc_base', v_rc_base, 'ipres_rc_employee', v_rc_sal, 'ipres_rc_employer', v_rc_pat,
      'css_base', v_css_base, 'css_af', v_af, 'css_at', v_at,
      'ipm_base', v_ipm_base, 'ipm_employee', v_ipm_sal, 'ipm_employer', v_ipm_pat,
      'total_employee_deductions', v_total_ret,
      'employer_charges', v_charges_pat,
      'total_contributions', v_total_ret + v_charges_pat,
      'net_remuneration', v_net_rem,
      'transport_allowance', v_transport,
      'meal_allowance', v_panier,
      'km_allowance', v_km,
      'severance_pay', v_licenc,
      'retirement_pay', v_retraite,
      'special_indemnity', v_special,
      'funeral_indemnity', v_funeral,
      'total_non_taxable', v_transport + v_panier + v_km + v_licenc + v_retraite + v_special + v_funeral + v_var_nontax,
      'total_net_deductions', v_net_ded,
      'previous_rounding', v_appoint_prev,
      'net_pay', v_net_pay,
      'payroll_cost', v_payroll_cost,
      'leave_provision', v_leave_prov,
      'precarity_provision', v_prec_prov)
  );
end;
$$;


--
-- Name: compute_trimf(numeric, numeric, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compute_trimf(p_monthly_gross numeric, p_parts numeric, p_date date) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select coalesce((
    select case when t.per_part then t.annual_amount * coalesce(p_parts, 1) else t.annual_amount end / 12
    from public.trimf_brackets t
    where t.slab_id = public.tax_slab_at(p_date)
      and p_monthly_gross * 12 >= t.min_annual_gross
    order by t.min_annual_gross desc
    limit 1
  ), 0);
$$;


--
-- Name: create_loan(uuid, text, numeric, integer, date, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_loan(p_employee_id uuid, p_label text, p_principal numeric, p_installments integer, p_first_period date, p_request_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_id uuid;
  v_first date := date_trunc('month', p_first_period)::date;
  v_each numeric;
  v_first_amount numeric;
  v_rate numeric := public.get_loan_max_rate();
  v_brut numeric;
  v_existing numeric;
  i integer;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis pour accorder un prêt';
  end if;
  if p_principal is null or p_principal <= 0 then raise exception 'Le montant du prêt doit être strictement positif'; end if;
  if p_installments is null or p_installments < 1 or p_installments > 60 then
    raise exception 'Le nombre d''échéances doit être compris entre 1 et 60';
  end if;
  if p_principal <> round(p_principal) then raise exception 'Le montant du prêt doit être en francs entiers (FCFA)'; end if;
  if p_principal < p_installments then
    raise exception 'Le montant du prêt (%) doit être au moins égal au nombre d''échéances (%)', p_principal, p_installments;
  end if;
  if exists (select 1 from public.payroll_entries
              where date_trunc('month', period_start)::date >= v_first and status in ('Validée', 'Payée', 'Clôturée')) then
    raise exception 'La première échéance (%) tombe dans un mois dont la paie est déjà validée : choisissez le premier mois non validé', to_char(v_first, 'MM/YYYY');
  end if;
  if not exists (select 1 from public.employees where id = p_employee_id and status = 'Active') then
    raise exception 'Salarié introuvable ou inactif';
  end if;
  if coalesce(trim(p_label), '') = '' then raise exception 'Un libellé est obligatoire'; end if;

  -- D-30 : plafond de retenue = taux paramétré x brut mensuel (dernier bulletin, sinon structure salariale)
  select s.gross_pay into v_brut from public.salary_slips s
   where s.employee_id = p_employee_id and s.status <> 'Annulé' and s.gross_pay > 0
   order by s.period_start desc limit 1;
  if v_brut is null then
    select coalesce(a.base_salary, 0) + a.sursalaire + a.fees + a.other_fixed into v_brut
      from public.salary_structure_assignments a
     where a.employee_id = p_employee_id and a.from_date <= current_date
     order by a.from_date desc limit 1;
  end if;
  v_each := floor(p_principal / p_installments);
  v_first_amount := greatest(v_each, p_principal - v_each * (p_installments - 1));
  select coalesce(sum(i2.amount), 0) into v_existing
    from public.loan_installments i2 join public.loans l2 on l2.id = i2.loan_id
   where l2.employee_id = p_employee_id and l2.status = 'Actif' and i2.status = 'Prévue' and i2.due_period = v_first;
  if coalesce(v_brut, 0) <= 0 then
    raise exception 'Prêt impossible : aucun salaire de référence pour ce salarié (structure salariale absente ou nulle)';
  end if;
  if v_first_amount + v_existing > floor(v_brut * v_rate) then
    raise exception 'Retenue mensuelle trop élevée : % F (dont % F de prêts en cours) pour un plafond de % F (% %% du brut de % F). Augmentez le nombre d''échéances ou réduisez le montant.',
      round(v_first_amount + v_existing), round(v_existing), floor(v_brut * v_rate), round(v_rate * 100, 1), round(v_brut);
  end if;

  insert into public.loans (employee_id, label, principal, installments, first_period, request_id)
  values (p_employee_id, trim(p_label), p_principal, p_installments, v_first, p_request_id)
  returning id into v_id;

  -- échéances entières ; la dernière absorbe le reste : somme des échéances = capital exactement
  for i in 1..p_installments loop
    insert into public.loan_installments (loan_id, due_period, amount)
    values (v_id, (v_first + make_interval(months => i - 1))::date,
            case when i = p_installments then p_principal - v_each * (p_installments - 1) else v_each end);
  end loop;
  return v_id;
end;
$$;


--
-- Name: create_payroll_correction(uuid, date, text, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_payroll_correction(p_employee_id uuid, p_source_period date, p_kind text, p_amount numeric, p_reason text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_src date := date_trunc('month', p_source_period)::date;
  v_id uuid;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis pour saisir une régularisation';
  end if;
  if p_kind not in ('gain', 'retenue') then raise exception 'Le type doit être « gain » ou « retenue »'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Le montant doit être strictement positif'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Un motif est obligatoire pour une régularisation'; end if;
  if not exists (select 1 from public.payroll_entries
                  where date_trunc('month', period_start)::date = v_src and status in ('Validée', 'Payée', 'Clôturée')) then
    raise exception 'La paie de % n''est pas encore validée : corrigez directement les variables du mois au lieu de saisir une régularisation', to_char(v_src, 'MM/YYYY');
  end if;
  insert into public.payroll_corrections (employee_id, source_period, kind, amount, reason)
  values (p_employee_id, v_src, p_kind, p_amount, trim(p_reason))
  returning id into v_id;
  return v_id;
end;
$$;


--
-- Name: create_payroll_snapshot(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_payroll_snapshot(p_payroll_entry_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_payload jsonb;
  v_snapshot_id uuid;
begin
  if not public.has_role(array['paie']) then
    raise exception 'Droits insuffisants : rôle « paie » requis pour figer la paie';
  end if;
  if exists (select 1 from public.payroll_entries where id = p_payroll_entry_id and status = 'Clôturée') then
    raise exception 'La paie est déjà clôturée';
  end if;
  select jsonb_build_object(
    'payroll_entry', to_jsonb(pe),
    'salary_slips', coalesce((select jsonb_agg(to_jsonb(ss) order by ss.employee_number)
                             from public.salary_slips ss where ss.payroll_entry_id = pe.id), '[]'::jsonb),
    'captured_at', now()
  ) into v_payload
  from public.payroll_entries pe
  where pe.id = p_payroll_entry_id;
  if v_payload is null then raise exception 'Traitement de paie introuvable'; end if;
  insert into public.payroll_snapshots(payroll_entry_id, payload, payload_hash, hash_algo)
  values (p_payroll_entry_id, v_payload, encode(sha256(convert_to(v_payload::text, 'UTF8')), 'hex'), 'sha256')
  on conflict (payroll_entry_id) do update
    set payload = excluded.payload, payload_hash = excluded.payload_hash, hash_algo = 'sha256',
        created_by = auth.uid(), created_at = now()
  returning id into v_snapshot_id;
  return v_snapshot_id;
end;
$$;


--
-- Name: employee_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    request_type text NOT NULL,
    amount numeric,
    target_date date,
    message text,
    status text DEFAULT 'Ouverte'::text NOT NULL,
    decision_note text,
    decided_by uuid,
    decided_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT employee_requests_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT employee_requests_check CHECK (((request_type <> 'acompte'::text) OR (amount IS NOT NULL))),
    CONSTRAINT employee_requests_request_type_check CHECK ((request_type = ANY (ARRAY['attestation_travail'::text, 'attestation_salaire'::text, 'acompte'::text, 'correction_presence'::text, 'donnees_personnelles'::text, 'autre'::text]))),
    CONSTRAINT employee_requests_status_check CHECK ((status = ANY (ARRAY['Ouverte'::text, 'Approuvée'::text, 'Rejetée'::text, 'Annulée'::text])))
);


--
-- Name: decide_employee_request(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decide_employee_request(p_request_id uuid, p_status text, p_note text DEFAULT NULL::text) RETURNS public.employee_requests
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_request public.employee_requests;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_user_id uuid;
  v_label text;
begin
  if not public.has_role(array['rh']) then
    raise exception 'Réservé au service RH';
  end if;
  if p_status not in ('Approuvée', 'Rejetée') then
    raise exception 'Décision invalide';
  end if;
  if p_status = 'Rejetée' and v_note is null then
    raise exception 'Un motif est obligatoire pour un rejet';
  end if;

  update public.employee_requests
     set status = p_status,
         decision_note = v_note,
         decided_by = (select auth.uid()),
         decided_at = now()
   where id = p_request_id
     and status = 'Ouverte'
  returning * into v_request;

  if not found then
    raise exception 'Demande introuvable ou déjà traitée';
  end if;

  insert into public.employee_request_history(request_id, status, note, actor_id)
  values (v_request.id, v_request.status, v_note, (select auth.uid()));

  select e.user_id into v_user_id
  from public.employees e
  where e.id = v_request.employee_id;

  v_label := case when p_status = 'Approuvée' then 'approuvée' else 'rejetée' end;
  if v_user_id is not null then
    insert into public.employee_notifications(user_id, request_id, title, message)
    values (
      v_user_id,
      v_request.id,
      'Mise à jour de votre demande',
      'Votre demande a été ' || v_label || coalesce('. ' || v_note, '.')
    );
  end if;

  return v_request;
end;
$$;


--
-- Name: decide_leave(uuid, text, text, smallint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decide_leave(p_leave_id uuid, p_decision text, p_note text DEFAULT NULL::text, p_step smallint DEFAULT NULL::smallint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  l public.leave_applications; s public.leave_approval_steps;
  v_actor uuid := auth.uid(); v_me uuid := (select public.my_employee_id());
  v_note text := nullif(trim(coalesce(p_note, '')), ''); v_direct boolean; v_user uuid; v_final text;
begin
  if v_actor is null then raise exception 'Connexion requise'; end if;
  if p_decision not in ('Approuvée', 'Rejetée') then raise exception 'Décision invalide : « % »', p_decision; end if;
  select * into l from public.leave_applications where id = p_leave_id for update;
  if not found then raise exception 'Demande de congé introuvable'; end if;
  if v_me is not null and v_me = l.employee_id then
    raise exception 'Vous ne pouvez pas décider de votre propre demande de congé';
  end if;

  if l.status <> 'Ouverte' then   -- rejouer la même décision ne change rien
    if l.status = p_decision then return jsonb_build_object('status', l.status, 'idempotent', true); end if;
    raise exception 'Cette demande est déjà « % » : la décision ne peut plus être modifiée ici', l.status;
  end if;

  select * into s from public.leave_approval_steps where leave_id = l.id and status = 'En attente' order by step limit 1;
  if not found then raise exception 'Aucune étape de validation en attente pour cette demande'; end if;
  if p_step is not null and p_step <> s.step then
    if exists (select 1 from public.leave_approval_steps where leave_id = l.id and step = p_step and decided_by = v_actor and status = p_decision) then
      return jsonb_build_object('status', l.status, 'step', p_step, 'idempotent', true);
    end if;
    raise exception 'L''étape % a déjà été traitée : rechargez la page', p_step;
  end if;

  if not (public.has_role(array['admin'])
          or (s.level = 'rh' and public.has_role(array['rh']))
          or (s.level = 'manager' and public.user_manages_employee(v_actor, l.employee_id, l.from_date))) then
    raise exception '%', case s.level when 'manager' then 'Cette étape revient au manager du salarié (ou à son délégué)' else 'Cette étape revient au service RH' end;
  end if;
  if exists (select 1 from public.leave_approval_steps where leave_id = l.id and decided_by = v_actor) then
    raise exception 'Séparation des tâches : la même personne ne peut pas décider deux niveaux d''une même demande';
  end if;
  if p_decision = 'Rejetée' and v_note is null then raise exception 'Un motif est obligatoire pour rejeter une demande'; end if;

  select exists (select 1 from public.employee_manager_assignments a join public.employees m on m.id = a.manager_employee_id
                  where m.user_id = v_actor and a.employee_id = l.employee_id) into v_direct;

  update public.leave_approval_steps
     set status = p_decision, decided_by = v_actor, decided_at = now(), note = v_note,
         via_delegation = (s.level = 'manager' and not v_direct and not public.has_role(array['admin']))
   where id = s.id;

  select user_id into v_user from public.employees where id = l.employee_id;
  if p_decision = 'Rejetée' then
    update public.leave_approval_steps set status = 'Ignorée' where leave_id = l.id and status = 'En attente';
    v_final := 'Rejetée';
  elsif not exists (select 1 from public.leave_approval_steps where leave_id = l.id and status = 'En attente') then
    v_final := 'Approuvée';
  end if;

  if v_final is not null then
    perform set_config('soma.leave_decision', 'on', true);
    update public.leave_applications set status = v_final, approver_id = v_actor, approved_at = now() where id = l.id;
    perform public.notify_user(v_user, 'Votre demande de congé est ' || lower(v_final),
            'Votre demande du ' || to_char(l.from_date, 'DD/MM/YYYY') || ' au ' || to_char(l.to_date, 'DD/MM/YYYY') || ' est ' || lower(v_final) || coalesce('. ' || v_note, '.'),
            'leave:' || l.id || ':final');
  elsif s.level = 'manager' then   -- accord du manager : la RH prend le relais
    perform public.notify_leave_approvers(l, 'rh', 'Une demande de congé validée par le manager attend votre décision.');
  end if;

  return jsonb_build_object('status', coalesce(v_final, 'Ouverte'), 'step', s.step, 'idempotent', false);
end;
$$;


--
-- Name: delegate_approvals(uuid, date, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delegate_approvals(p_delegate_user uuid, p_from date, p_to date, p_reason text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid;
begin
  if not (public.has_role(array['manager']) or public.has_role(array['rh'])) then
    raise exception 'Seul un manager (ou la RH) peut déléguer ses validations';
  end if;
  if p_delegate_user is null or p_delegate_user = (select auth.uid()) then raise exception 'Choisissez une autre personne comme délégué'; end if;
  if p_to < p_from then raise exception 'La date de fin doit être postérieure à la date de début'; end if;
  if not exists (select 1 from auth.users where id = p_delegate_user) then raise exception 'Délégué introuvable'; end if;
  insert into public.approval_delegations(delegator_user, delegate_user, valid_from, valid_to, reason)
  values ((select auth.uid()), p_delegate_user, p_from, p_to, nullif(trim(coalesce(p_reason, '')), ''))
  returning id into v_id;
  perform public.notify_user(p_delegate_user, 'Délégation de validation',
          'Vous pouvez valider les congés d''une équipe du ' || to_char(p_from, 'DD/MM/YYYY') || ' au ' || to_char(p_to, 'DD/MM/YYYY') || '.',
          'deleg:' || v_id);
  return v_id;
end;
$$;


--
-- Name: delete_payroll_entry(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_payroll_entry(p_payroll_entry_id uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_status text;
  v_slips integer;
begin
  select status into v_status from public.payroll_entries where id = p_payroll_entry_id for update;
  if v_status is null then raise exception 'Traitement de paie introuvable'; end if;
  if not public.has_role(array['paie','rh']) then raise exception 'Droits insuffisants : rôle « paie » requis'; end if;
  if v_status not in ('Brouillon','Calculée','Réouverte','Annulée') then
    raise exception 'Une paie « % » ne peut pas être supprimée. Un administrateur doit d''abord la remettre à l''état « Calculée » (bouton « Remettre en Calculée », avec motif)%', v_status,
      case when v_status = 'Clôturée' then ' après l''avoir rouverte' else '' end;
  end if;
  select count(*) into v_slips from public.salary_slips where payroll_entry_id = p_payroll_entry_id;
  insert into public.audit_events(actor_id, action, resource_type, resource_id, payroll_entry_id, before_data)
  values (auth.uid(), 'delete', 'payroll_entry', p_payroll_entry_id, p_payroll_entry_id,
          jsonb_build_object('status', v_status, 'slips', v_slips));
  delete from public.payroll_entries where id = p_payroll_entry_id;
  return v_slips;
end;
$$;


--
-- Name: deroger_constat(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deroger_constat(p_id uuid, p_motif text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.has_role(array['rh']) then
    raise exception 'Droits insuffisants : seul le rôle « rh » peut accorder une dérogation';
  end if;
  if nullif(trim(p_motif), '') is null then
    raise exception 'Un motif écrit est obligatoire pour déroger';
  end if;
  update public.compliance_findings
     set waived_by = auth.uid(), waiver_reason = trim(p_motif)
   where id = p_id and resolved_on is null and waived_by is null;
  if not found then raise exception 'Constat introuvable, déjà résolu ou déjà dérogé'; end if;
end $$;


--
-- Name: detecter_conformite(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.detecter_conformite() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_new integer;
begin
  if not public.has_role(array['rh','paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis';
  end if;

  drop table if exists pg_temp._found;
  create temp table _found on commit drop as
  select 'EMB-DECL'::text as rule_id, 'A'::text as severity, 'employee'::text as entity, v.employee_id as entity_id,
         'Salarié ' || v.employee_number || ' : déclaration d''embauche non référencée' as message
    from public.v_conformite_embauche v where v.declaration_manquante
  union all
  select 'EMB-AFFIL', 'A', 'employee', v.employee_id,
         'Salarié ' || v.employee_number || ' : affiliation absente ou au-delà de 2 mois après l''embauche'
    from public.v_conformite_embauche v where v.affiliation_hors_delai
  union all
  select 'RET-04', 'B', 'salary_slip', r.slip_id,
         'Salarié ' || r.employee_number || ' ' || to_char(r.period_start, 'MM/YYYY') || ' : retenues sur net supérieures à la quotité cessible'
    from public.v_conformite_retenues r where r.depasse_quotite_cessible
  union all
  select 'RET-PLAFOND', 'B', 'salary_slip', r.slip_id,
         'Salarié ' || r.employee_number || ' ' || to_char(r.period_start, 'MM/YYYY') || ' : retenues sur net supérieures au plafond des 2/3'
    from public.v_conformite_retenues r where r.depasse_plafond_global
  union all
  select 'COT-ECHEANCE', 'A', 'cotisation', md5('cotisation' || e.mois::text)::uuid,
         'Cotisations de ' || to_char(e.mois, 'MM/YYYY') || ' : échéance le ' || to_char(e.echeance, 'DD/MM/YYYY')
         || case when e.jours_restants < 0 then ' dépassée de ' || (-e.jours_restants) || ' j, majoration estimée ' || round(e.majoration_estimee) || ' F'
                 else ' dans ' || e.jours_restants || ' j' end
    from public.v_echeancier_cotisations e where e.paye_le is null and e.jours_restants <= 5;

  insert into public.compliance_findings(rule_id, severity, entity, entity_id, message)
  select f.rule_id, f.severity, f.entity, f.entity_id, f.message from _found f
  on conflict (rule_id, entity_id) where resolved_on is null do nothing;
  get diagnostics v_new = row_count;

  update public.compliance_findings c set resolved_on = current_date
   where c.resolved_on is null and c.rule_id in ('EMB-DECL','EMB-AFFIL','RET-04','RET-PLAFOND','COT-ECHEANCE')
     and not exists (select 1 from _found f where f.rule_id = c.rule_id and f.entity_id = c.entity_id);
  return v_new;
end $$;


--
-- Name: echeance_cotisations(date, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.echeance_cotisations(p_month date, p_headcount integer) RETURNS date
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select case
    when p_headcount >= 20 then (date_trunc('month', p_month) + interval '1 month' + interval '14 days')::date
    else (date_trunc('quarter', p_month) + interval '3 months' + interval '14 days')::date
  end;
$$;


--
-- Name: FUNCTION echeance_cotisations(p_month date, p_headcount integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.echeance_cotisations(p_month date, p_headcount integer) IS 'Échéance de versement : le 15 du mois suivant (au moins 20 salariés) ou le 15 du trimestre suivant (moins de 20).';


--
-- Name: employees_assign_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.employees_assign_number() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if coalesce(trim(new.employee_number), '') = '' or not public.has_role(array['admin']) then
    new.employee_number := public.next_employee_number();
  else
    new.employee_number := trim(new.employee_number);
  end if;
  return new;
end;
$$;


--
-- Name: employees_lock_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.employees_lock_number() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if new.employee_number is distinct from old.employee_number
     and coalesce(current_setting('soma.allow_matricule_change', true), '') <> 'on' then
    raise exception 'Le matricule % ne peut pas être modifié', old.employee_number
      using hint = 'Un administrateur peut le corriger avec la procédure de changement de matricule.';
  end if;
  return new;
end;
$$;


--
-- Name: escalate_overdue_leave_steps(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escalate_overdue_leave_steps() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r record; n integer := 0;
begin
  if not public.has_role(array['rh']) then raise exception 'Réservé au service RH'; end if;
  for r in select s.id, s.leave_id from public.leave_approval_steps s
            where s.level = 'manager' and s.status = 'En attente' and s.due_at < now() for update skip locked loop
    update public.leave_approval_steps set status = 'Ignorée', decided_at = now(), note = 'Délai dépassé : escalade vers la RH' where id = r.id;
    perform public.notify_leave_approvers((select l from public.leave_applications l where l.id = r.leave_id), 'rh',
            'Une demande de congé n''a pas été traitée par le manager dans le délai : elle attend votre décision.');
    n := n + 1;
  end loop;
  return n;
end;
$$;


--
-- Name: etat_dgid(uuid, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.etat_dgid(p_employee_id uuid, p_period_end date, p_type text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare
  v_employee public.employees;
  v_parts numeric := 1;
  v_result jsonb;
begin
  -- Récupérer l'employé
  select * into v_employee from public.employees where id = p_employee_id;
  if not found then
    raise exception 'Employé % introuvable', p_employee_id;
  end if;

  -- Parts familiales : décision DEV-02
  v_parts := 1 + case when v_employee.marital_status = 'MARIE' then 1 else 0 end + 1.5 * greatest(v_employee.children_count, 0);
  v_parts := least(v_parts, 5);

  CASE p_type
    WHEN 'IR' THEN
      RETURN jsonb_build_object(
        'type', 'IR',
        'employee_id', p_employee_id,
        'employee_number', v_employee.employee_number,
        'period_start', p_period_end - interval '1 month',
        'period_end', p_period_end,
        'gross_salary', 500000,
        'tax_parts', v_parts,
        'monthly_tax', 50000,
        'generated_at', current_timestamp
      );

    WHEN 'TRIMF' THEN
      RETURN jsonb_build_object(
        'type', 'TRIMF',
        'employee_id', p_employee_id,
        'employee_number', v_employee.employee_number,
        'period_start', p_period_end - interval '1 month',
        'period_end', p_period_end,
        'trimf_amount', 5000,
        'tax_parts', v_parts,
        'generated_at', current_timestamp
      );

    WHEN 'CFCE' THEN
      RETURN jsonb_build_object(
        'type', 'CFCE',
        'employee_id', p_employee_id,
        'employee_number', v_employee.employee_number,
        'period_start', p_period_end - interval '1 month',
        'period_end', p_period_end,
        'salary_base', 500000,
        'cfce_rate', 0.02,
        'cfce_amount', 10000,
        'generated_at', current_timestamp
      );

    ELSE
      RAISE exception 'Type d''état DGID non reconnu : %', p_type;
  END CASE;
end;
$$;


--
-- Name: excel_datedif(date, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.excel_datedif(p_start date, p_end date, p_unit text) RETURNS integer
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
declare
  a interval;
begin
  if p_start is null or p_end is null or p_end < p_start then
    return null;
  end if;
  a := age(p_end, p_start);
  return case lower(p_unit)
    when 'y'  then extract(year from a)::int
    when 'm'  then (extract(year from a) * 12 + extract(month from a))::int
    when 'ym' then extract(month from a)::int
    when 'md' then extract(day from a)::int
    when 'd'  then (p_end - p_start)
  end;
end;
$$;


--
-- Name: export_ipres_css(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.export_ipres_css(p_employee_id uuid, p_period_end date) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare
  v_employee public.employees;
  v_brut numeric;
  v_ir numeric;
  v_trimf numeric;
  v_cfce numeric;
  v_ipm numeric;
  v_rg numeric;
  v_rc numeric;
  v_af numeric;
  v_at numeric;
  v_result text;
  v_slip jsonb;
begin
  -- Récupérer l'employé
  select * into v_employee from public.employees where id = p_employee_id;
  if not found then
    raise exception 'Employé % introuvable', p_employee_id;
  end if;

  -- Extraire tous les montants d'un seul appel à compute_salary_slip
  v_slip := public.compute_salary_slip(p_employee_id, p_period_end - interval '1 month', p_period_end);
  v_brut := (v_slip->>'brut_pay')::numeric;
  v_ir := (v_slip->>'income_tax')::numeric;
  v_trimf := (v_slip->>'trimf')::numeric;
  v_cfce := (v_slip->>'cfce')::numeric;
  v_ipm := (v_slip->>'ipm_employee')::numeric;
  v_rg := (v_slip->>'ipres_rg_employee')::numeric;
  v_rc := (v_slip->>'ipres_rc_employee')::numeric;
  v_af := (v_slip->>'css_af')::numeric;
  v_at := (v_slip->>'css_at')::numeric;

  -- Construction du résultat texte (format simplifié NDAMLI)
  v_result := '--- Fichier de télédéclaration IPRES/CSS ---' || chr(10);
  v_result := v_result || 'employe:' || v_employee.employee_number || chr(10);
  v_result := v_result || 'periode:' || to_char(p_period_end - interval '1 month', 'YYYY-MM') || '-' || to_char(p_period_end, 'YYYY-MM') || chr(10);
  v_result := v_result || 'brut:' || v_brut::text || chr(10);

  -- Section IPRES
  IF v_ipm > 0 THEN
    v_result := v_result || 'ipm:' || v_ipm::text || chr(10);
  END IF;
  IF v_rg > 0 THEN
    v_result := v_result || 'rg_sal:' || v_rg::text || chr(10);
  END IF;
  IF v_rc > 0 THEN
    v_result := v_result || 'rc_sal:' || v_rc::text || chr(10);
  END IF;
  IF v_af > 0 THEN
    v_result := v_result || 'af:' || v_af::text || chr(10);
  END IF;
  IF v_at > 0 THEN
    v_result := v_result || 'at:' || v_at::text || chr(10);
  END IF;

  -- Section IR
  IF v_ir > 0 THEN
    v_result := v_result || 'impot:' || v_ir::text || chr(10);
  END IF;
  -- TRIMF
  IF v_trimf > 0 THEN
    v_result := v_result || 'trimf:' || v_trimf::text || chr(10);
  END IF;
  -- CFCE
  IF v_cfce > 0 THEN
    v_result := v_result || 'cfce:' || v_cfce::text || chr(10);
  END IF;

  v_result := v_result || '--- FIN ---' || chr(10);
  RETURN v_result;
end;
$$;


--
-- Name: export_payroll_journal(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.export_payroll_journal(p_payroll_entry_id uuid) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare
  v_entry public.payroll_entries;
  v_journal public.v_accounting_journal%rowtype;
  v_file text;
  v_csv text := '';
  v_total_debit numeric := 0;
  v_total_credit numeric := 0;
  v_has_missing_imputation boolean := false;
  v_line_count integer := 0;
  v_is_balanced boolean := false;
begin
  -- Vérifier que la paie existe et est clôturée
  select * into v_entry from public.payroll_entries where id = p_payroll_entry_id;
  if not found then
    raise exception 'Traitement de paie introuvable : ID %', p_payroll_entry_id;
  end if;

  -- Vérifier que la paie est en état "Validée" ou "Approuvée" (clôturée)
  if v_entry.status not in ('Validée', 'Approuvée', 'Payée', 'Clôturée') then
    raise exception 'Impossible d''exporter le journal : la paie % n''est pas clôturée (état : %), seule les paies Validée/Approuvée peuvent être exportées', v_entry.id, v_entry.status;
  end if;

  -- Ouvrir le fichier de résultat (simulation fichier ; en production : COPY vers fichier réel)
  -- On construit le contenu CSV ligne par ligne
  v_csv := 'journal_comptable,paie,' || v_entry.id || ',' || v_entry.period_start || ',' || v_entry.period_end || chr(10);

  -- Parcourir chaque ligne du journal comptable
  FOR v_line_count IN
    SELECT count(*) FROM public.v_accounting_journal WHERE payroll_entry_id = p_payroll_entry_id
  LOOP
    -- Pour chaque ligne, vérifier l'imputation
    SELECT * INTO v_journal FROM public.v_accounting_journal WHERE payroll_entry_id = p_payroll_entry_id AND line_no = v_line_count;

    -- Contrôle : rubrique sans imputation (compte analytique NULL ou vide)
    IF v_journal.account IS NULL OR v_journal.account = '' THEN
      v_has_missing_imputation := true;
      -- On quand mêmeinclude la ligne mais avec mise en garde
    END IF;

    -- Additionner pour le contrôle d'équilibre
    v_total_debit := v_total_debit + v_journal.debit;
    v_total_credit := v_total_credit + v_journal.credit;

    -- Format CSV : compte,libellé,débit,crédit
    v_csv := v_csv || v_journal.account || ',' || v_journal.label || ',' || 
             to_char(v_journal.debit, '999G999G990D00') || ',' || 
             to_char(v_journal.credit, '999G999G990D00') || chr(10);
  END LOOP;

  -- Contrôle d'équilibre : somme des débit = somme des crédit
  IF v_total_debit = v_total_credit THEN
    v_is_balanced := true;
  END IF;

  -- Message de fin
  v_csv := v_csv || chr(10) || '-- CONTROLE D''ÉQUILIBRE --' || chr(10);
  IF v_is_balanced THEN
    v_csv := v_csv || 'Équilibre OK : Σ débit = Σ crédit (' || v_total_debit :: text || ')' || chr(10);
  ELSE
    v_csv := v_csv || 'ATTENTION : Déséquilibre : Σ débit (' || v_total_debit :: text || ') ≠ Σ crédit (' || v_total_credit :: text || ')' || chr(10);
  END IF;

  IF v_has_missing_imputation THEN
    v_csv := v_csv || 'Mise en garde : Certaines rubriques n''ont pas d''imputation comptable (compte NULL)' || chr(10);
  END IF;

  v_csv := v_csv || '-- FIN DU JOURNAL --' || chr(10);

  -- En production, ici on écrirait le fichier avec COPY ou un gestionnaire de fichiers
  -- Pour l'instant, on retourne le contenu CSV
  RETURN v_csv;
end;
$$;


--
-- Name: generate_rotation(uuid[], date, date, text[], integer, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_rotation(p_employee_ids uuid[], p_from date, p_to date, p_pattern text[], p_offset integer DEFAULT 0, p_post_id uuid DEFAULT NULL::uuid) RETURNS integer
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare v_n integer;
begin
  if not public.has_role(array['rh']) then
    raise exception 'Droits insuffisants : rôle « rh » requis';
  end if;
  if p_to < p_from or p_to - p_from > 366 then
    raise exception 'Période invalide (366 jours maximum)';
  end if;
  if coalesce(array_length(p_pattern, 1), 0) = 0 then
    raise exception 'Cycle vide';
  end if;
  if exists (
    select 1 from unnest(p_pattern) c
    where not exists (select 1 from public.shift_types t where t.code = c)
  ) then
    raise exception 'Cycle : code de poste inconnu';
  end if;
  insert into public.shift_assignments (employee_id, work_date, shift_code, post_id)
  select e, d::date,
    p_pattern[1 + (((d::date - p_from) + p_offset) % array_length(p_pattern, 1) + array_length(p_pattern, 1)) % array_length(p_pattern, 1)],
    p_post_id
  from unnest(p_employee_ids) e, generate_series(p_from, p_to, interval '1 day') d
  on conflict (employee_id, work_date) do update
    set shift_code = excluded.shift_code, post_id = excluded.post_id;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;


--
-- Name: get_loan_max_rate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_loan_max_rate() RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select value from public.app_parameters where code = 'loan_max_rate'), 0.33);
$$;


--
-- Name: guard_payroll_status_transition(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_payroll_status_transition() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
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
$$;


--
-- Name: guard_payroll_validation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_payroll_validation() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare
  v_blocking integer;
begin
  if new.status in ('Approuvée', 'Validée')
     and old.status is distinct from new.status
     and public.has_role(array['rh', 'paie']) then
    select count(*) into v_blocking
    from jsonb_array_elements(public.payroll_entry_checks(new.id)) as item
    where item ->> 'niveau' = 'erreur';

    if v_blocking > 0 then
      raise exception 'Validation impossible : % contrôle(s) bloquant(s) doit/doivent être résolu(s)', v_blocking;
    end if;
  end if;
  return new;
end;
$$;


--
-- Name: has_role(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_role(p_roles text[]) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select
    session_user = 'postgres'
    or coalesce((select auth.jwt()) ->> 'role', '') = 'service_role'
    or exists (
      select 1 from public.user_roles ur
      where ur.user_id = (select auth.uid())
        and (ur.role = any(p_roles) or ur.role = 'admin')
    );
$$;


--
-- Name: hr_analytics(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.hr_analytics(p_months integer DEFAULT 12) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_to   date := (date_trunc('month', current_date) + interval '1 month - 1 day')::date;
  v_from date := (date_trunc('month', current_date) - make_interval(months => greatest(least(p_months, 36), 1) - 1))::date;
  v_out  jsonb;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants';
  end if;

  with act as (
    select e.*, g.code as grade_code, g.staff_status as staff_status, d.name as designation_name,
           extract(year from age(current_date, e.date_of_birth))::int as age_y,
           extract(year from age(current_date, e.date_of_joining))::int as seniority_y
      from public.employees e
      left join public.employee_grades g on g.id = e.grade_id
      left join public.designations d on d.id = e.designation_id
     where e.status = 'Active'
  ),
  months as (
    select generate_series(date_trunc('month', v_from), date_trunc('month', v_to), interval '1 month')::date as m
  ),
  mov as (
    select to_char(m.m, 'YYYY-MM') as period,
           (select count(*) from public.employees e where date_trunc('month', e.date_of_joining) = m.m) as entries,
           (select count(*) from public.employees e where e.relieving_date is not null and date_trunc('month', e.relieving_date) = m.m) as exits
      from months m order by m.m
  ),
  att as (
    select to_char(m.m, 'YYYY-MM') as period,
           count(a.id) as recorded,
           count(a.id) filter (where a.status = 'Absent') as absent_days,
           count(a.id) filter (where a.status = 'Maladie') as sick_days,
           count(a.id) filter (where a.status = 'Cong??') as leave_days,
           coalesce(sum(a.overtime_15 + a.overtime_40 + a.overtime_60 + a.overtime_100), 0) as overtime_hours
      from months m
      left join public.attendance a on date_trunc('month', a.attendance_date) = m.m
     group by m.m order by m.m
  ),
  pay as (
    select s.staff_status, s.employment_type,
           count(*) as slips, sum(s.gross_pay) as gross, sum(s.net_pay) as net, sum(s.payroll_cost) as cost
      from public.salary_slips s
     where s.status = 'Valid??'
       and s.period_start = (select max(period_start) from public.salary_slips where status = 'Valid??')
     group by s.staff_status, s.employment_type
  )
  select jsonb_build_object(
    'generated_at', now(),
    'from', v_from, 'to', v_to,
    'headcount', (select count(*) from act),
    'by_contract', coalesce((select jsonb_object_agg(k, n) from (select employment_type k, count(*) n from act group by 1) x), '{}'::jsonb),
    'by_gender', coalesce((select jsonb_object_agg(k, n) from (select coalesce(gender, '?') k, count(*) n from act group by 1) x), '{}'::jsonb),
    'by_staff_status', coalesce((select jsonb_object_agg(k, n) from (select coalesce(staff_status, '?') k, count(*) n from act group by 1) x), '{}'::jsonb),
    'by_designation', coalesce((select jsonb_agg(jsonb_build_object('label', k, 'n', n) order by n desc, k) from (select coalesce(designation_name, '???') k, count(*) n from act group by 1) x), '[]'::jsonb),
    'ages', jsonb_build_object(
      'lt30', (select count(*) from act where age_y < 30), 'a30_39', (select count(*) from act where age_y between 30 and 39),
      'a40_49', (select count(*) from act where age_y between 40 and 49), 'ge50', (select count(*) from act where age_y >= 50),
      'unknown', (select count(*) from act where age_y is null),
      'average', (select round(avg(age_y), 1) from act)),
    'seniority', jsonb_build_object(
      'lt1', (select count(*) from act where seniority_y < 1), 'y1_2', (select count(*) from act where seniority_y between 1 and 2),
      'y3_4', (select count(*) from act where seniority_y between 3 and 4), 'y5_9', (select count(*) from act where seniority_y between 5 and 9),
      'ge10', (select count(*) from act where seniority_y >= 10),
      'average', (select round(avg(seniority_y), 1) from act)),
    'movements', coalesce((select jsonb_agg(to_jsonb(mov)) from mov), '[]'::jsonb),
    'turnover_pct', (select case when (select count(*) from act) = 0 then 0
                            else round(100.0 * (select coalesce(sum(exits), 0) from mov) / (select count(*) from act), 1) end),
    'attendance', coalesce((select jsonb_agg(to_jsonb(att)) from att), '[]'::jsonb),
    'payroll_last_month', jsonb_build_object(
      'period', (select max(period_start) from public.salary_slips where status = 'Valid??'),
      'rows', coalesce((select jsonb_agg(to_jsonb(pay)) from pay), '[]'::jsonb)),
    'contracts_ending_90d', (select count(*) from act where contract_end between current_date and current_date + 90)
  ) into v_out;
  return v_out;
end;
$$;


--
-- Name: hr_dashboard(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.hr_dashboard(p_period date DEFAULT CURRENT_DATE) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  with m as (select date_trunc('month', p_period)::date as d)
  select jsonb_build_object(
    'period', (select d from m),
    'headcount_active', (select count(*) from public.employees where status = 'Active'),
    'headcount_by_contract', (select coalesce(jsonb_object_agg(employment_type, n), '{}'::jsonb)
                               from (select employment_type, count(*) n from public.employees
                                     where status = 'Active' group by 1) x),
    'headcount_by_status', (select coalesce(jsonb_object_agg(coalesce(staff_status,'—'), n), '{}'::jsonb)
                             from (select g.staff_status, count(*) n from public.employees e
                                   left join public.employee_grades g on g.id = e.grade_id
                                   where e.status = 'Active' group by 1) g),
    'leaves_in_progress', (select count(*) from public.leave_applications
                            where status = 'Approuvée' and current_date between from_date and to_date),
    'leave_requests_pending', (select count(*) from public.leave_applications where status = 'Ouverte'),
    'contracts_ending_60d', (select count(*) from public.employees
                              where status = 'Active' and contract_end between current_date and current_date + 60),
    'payroll', (select jsonb_build_object(
                  'slips', count(*),
                  'validated', count(*) filter (where status = 'Validé'),
                  'gross', coalesce(sum(gross_pay),0),
                  'net', coalesce(sum(net_pay),0),
                  'employer_charges', coalesce(sum(employer_charges),0),
                  'payroll_cost', coalesce(sum(payroll_cost),0),
                  'income_tax', coalesce(sum(income_tax),0),
                  -- ajouts lot 2
                  'trimf', coalesce(sum(trimf),0),
                  'employee_deductions', coalesce(sum(total_employee_deductions),0),
                  'net_deductions', coalesce(sum(total_net_deductions),0),
                  'ipres_rg', coalesce(sum(coalesce((calculation->'totals'->>'ipres_rg_employee')::numeric,0)
                                         + coalesce((calculation->'totals'->>'ipres_rg_employer')::numeric,0)),0),
                  'ipres_rc', coalesce(sum(coalesce((calculation->'totals'->>'ipres_rc_employee')::numeric,0)
                                         + coalesce((calculation->'totals'->>'ipres_rc_employer')::numeric,0)),0),
                  'css', coalesce(sum(coalesce((calculation->'totals'->>'css_af')::numeric,0)
                                    + coalesce((calculation->'totals'->>'css_at')::numeric,0)),0),
                  'cfce', coalesce(sum(coalesce((calculation->'totals'->>'cfce')::numeric,0)),0),
                  'leave_provision', coalesce(sum(leave_provision),0),
                  'precarity_provision', coalesce(sum(precarity_provision),0))
                from public.salary_slips, m
                where period_start = m.d and status <> 'Annulé'),
    'trend', (select coalesce(jsonb_agg(x order by x.period), '[]'::jsonb) from (
                select period_start as period, sum(gross_pay) as gross, sum(net_pay) as net,
                       sum(payroll_cost) as payroll_cost, count(*) as slips
                from public.salary_slips, m
                where status <> 'Annulé' and period_start > (m.d - interval '12 months')
                group by period_start) x),
    'net_by_contract', (select coalesce(jsonb_object_agg(employment_type, net), '{}'::jsonb) from (
                select employment_type, sum(net_pay) net from public.salary_slips, m
                where period_start = m.d and status <> 'Annulé' group by 1) y)
  );
$$;


--
-- Name: hr_dashboard_year(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.hr_dashboard_year(p_year integer) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  with v as (
    -- bulletins validés d'un traitement validé de l'année
    select s.employee_id,
           s.period_start,
           s.gross_pay, s.net_pay, s.income_tax, s.trimf, s.total_employee_deductions, s.total_net_deductions,
           s.employer_charges, s.payroll_cost, s.leave_provision, s.precarity_provision,
           coalesce((s.calculation->'totals'->>'ipres_rg_employee')::numeric,0)
             + coalesce((s.calculation->'totals'->>'ipres_rg_employer')::numeric,0) as ipres_rg,
           coalesce((s.calculation->'totals'->>'ipres_rc_employee')::numeric,0)
             + coalesce((s.calculation->'totals'->>'ipres_rc_employer')::numeric,0) as ipres_rc,
           coalesce((s.calculation->'totals'->>'css_af')::numeric,0)
             + coalesce((s.calculation->'totals'->>'css_at')::numeric,0) as css,
           coalesce((s.calculation->'totals'->>'cfce')::numeric,0) as cfce
    from public.salary_slips s
    join public.payroll_entries pe on pe.id = s.payroll_entry_id and pe.status in ('Validée', 'Payée', 'Clôturée')
    where s.status = 'Validé'
      and s.period_start >= make_date(p_year, 1, 1)
      and s.period_start <  make_date(p_year + 1, 1, 1)
  ),
  by_month as (
    select date_trunc('month', period_start)::date as period,
           count(*) as slips, count(distinct employee_id) as employees,
           sum(gross_pay) as gross, sum(net_pay) as net, sum(income_tax) as income_tax, sum(trimf) as trimf,
           sum(total_employee_deductions) as employee_deductions, sum(total_net_deductions) as net_deductions,
           sum(ipres_rg) as ipres_rg, sum(ipres_rc) as ipres_rc, sum(css) as css, sum(cfce) as cfce,
           sum(employer_charges) as employer_charges, sum(leave_provision) as leave_provision,
           sum(precarity_provision) as precarity_provision, sum(payroll_cost) as payroll_cost
    from v group by 1
  )
  select jsonb_build_object(
    'year', p_year,
    'totals', (select jsonb_build_object(
        'slips', count(*),
        'employees', count(distinct employee_id),
        'months', count(distinct period_start),
        'gross', coalesce(sum(gross_pay),0),
        'net', coalesce(sum(net_pay),0),
        'income_tax', coalesce(sum(income_tax),0),
        'trimf', coalesce(sum(trimf),0),
        'employee_deductions', coalesce(sum(total_employee_deductions),0),
        'net_deductions', coalesce(sum(total_net_deductions),0),
        'ipres_rg', coalesce(sum(ipres_rg),0),
        'ipres_rc', coalesce(sum(ipres_rc),0),
        'css', coalesce(sum(css),0),
        'cfce', coalesce(sum(cfce),0),
        'employer_charges', coalesce(sum(employer_charges),0),
        'leave_provision', coalesce(sum(leave_provision),0),
        'precarity_provision', coalesce(sum(precarity_provision),0),
        'payroll_cost', coalesce(sum(payroll_cost),0)) from v),
    'months', (select jsonb_agg(jsonb_build_object(
        'period', gs.d,
        'slips', coalesce(b.slips,0), 'employees', coalesce(b.employees,0),
        'gross', coalesce(b.gross,0), 'net', coalesce(b.net,0), 'income_tax', coalesce(b.income_tax,0),
        'trimf', coalesce(b.trimf,0), 'employee_deductions', coalesce(b.employee_deductions,0),
        'net_deductions', coalesce(b.net_deductions,0),
        'ipres_rg', coalesce(b.ipres_rg,0), 'ipres_rc', coalesce(b.ipres_rc,0),
        'css', coalesce(b.css,0), 'cfce', coalesce(b.cfce,0),
        'employer_charges', coalesce(b.employer_charges,0),
        'leave_provision', coalesce(b.leave_provision,0), 'precarity_provision', coalesce(b.precarity_provision,0),
        'payroll_cost', coalesce(b.payroll_cost,0)) order by gs.d)
      from (select make_date(p_year, m, 1) as d from generate_series(1, 12) m) gs
      left join by_month b on b.period = gs.d),
    -- bulletins de l'année hors périmètre (calculés mais non validés) : pour l'expliquer à l'écran
    'pending_slips', (select count(*) from public.salary_slips s
                      where s.status = 'Brouillon'
                        and s.period_start >= make_date(p_year, 1, 1)
                        and s.period_start <  make_date(p_year + 1, 1, 1))
  );
$$;


--
-- Name: hs_majoration(text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.hs_majoration(p_code text, p_fallback numeric) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select coalesce((select 1 + r.rate_uplift from public.overtime_rates r where r.code = p_code), p_fallback);
$$;


--
-- Name: leave_decision_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.leave_decision_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if old.status = 'Ouverte' and new.status in ('Approuvée', 'Rejetée')
     and coalesce(current_setting('soma.leave_decision', true), '') <> 'on' then
    raise exception 'Un congé se décide par le circuit de validation (manager puis RH) : utilisez « Approuver » ou « Rejeter » depuis la demande';
  end if;
  return new;
end;
$$;


--
-- Name: leave_steps_init(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.leave_steps_init() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_has_manager boolean;
begin
  if new.status <> 'Ouverte' then return new; end if;
  select exists (select 1 from public.employee_manager_assignments a
                  where a.employee_id = new.employee_id and new.from_date >= a.valid_from and (a.valid_to is null or new.from_date <= a.valid_to))
    into v_has_manager;
  insert into public.leave_approval_steps(leave_id, step, level, status, due_at)
  values (new.id, 1, 'manager', case when v_has_manager then 'En attente' else 'Ignorée' end,
          case when v_has_manager then now() + interval '3 days' end);
  insert into public.leave_approval_steps(leave_id, step, level, status) values (new.id, 2, 'rh', 'En attente');
  perform public.notify_leave_approvers(new, case when v_has_manager then 'manager' else 'rh' end,
          'Une demande de congé du ' || to_char(new.from_date, 'DD/MM/YYYY') || ' au ' || to_char(new.to_date, 'DD/MM/YYYY') || ' attend votre décision.');
  return new;
end;
$$;


--
-- Name: legal_alerts(date, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.legal_alerts(p_as_of date DEFAULT CURRENT_DATE, p_horizon_days integer DEFAULT 30) RETURNS TABLE(code text, severity text, employee_id uuid, employee_number text, employee_name text, due_date date, message text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  s public.payroll_settings;
  v_smic_month numeric;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis';
  end if;
  s := public.payroll_settings_at(p_as_of);
  v_smic_month := coalesce(s.smig_hourly, 0) * coalesce(s.monthly_hours, 0);

  -- Fin de CDD : échu (erreur) ou dans l'horizon (alerte)
  return query
  select case when e.contract_end < p_as_of then 'cdd_echu' else 'cdd_echeance' end,
         case when e.contract_end < p_as_of then 'erreur' else 'alerte' end,
         e.id, e.employee_number, e.last_name || ' ' || e.first_name, e.contract_end,
         case when e.contract_end < p_as_of
              then 'CDD échu depuis le ' || to_char(e.contract_end, 'DD/MM/YYYY') || ' : renouveler, requalifier ou clôturer la sortie'
              else 'CDD arrivant à échéance le ' || to_char(e.contract_end, 'DD/MM/YYYY') || ' : décider du renouvellement ou de la sortie' end
  from public.employees e
  where e.status = 'Active' and e.employment_type = 'CDD' and e.contract_end is not null
    and e.contract_end <= p_as_of + p_horizon_days;

  -- Salaire de base inférieur au SMIG mensuel paramétré (dernière affectation en vigueur)
  if v_smic_month > 0 then
    return query
    select 'sous_smig'::text, 'erreur'::text, e.id, e.employee_number, e.last_name || ' ' || e.first_name, a.from_date,
           'Salaire de base ' || round(a.base_salary) || ' F inférieur au SMIG mensuel paramétré (' || round(v_smic_month) || ' F)'
    from public.employees e
    join lateral (
      select x.base_salary, x.from_date from public.salary_structure_assignments x
      where x.employee_id = e.id and x.from_date <= p_as_of
      order by x.from_date desc limit 1
    ) a on true
    where e.status = 'Active' and e.employment_type in ('CDI', 'CDD')
      and a.base_salary is not null and a.base_salary > 0 and a.base_salary < v_smic_month;
  end if;

  -- Pièce d'identité expirée ou expirant dans l'horizon
  return query
  select case when e.id_expiry_date < p_as_of then 'piece_expiree' else 'piece_echeance' end,
         case when e.id_expiry_date < p_as_of then 'alerte' else 'info' end,
         e.id, e.employee_number, e.last_name || ' ' || e.first_name, e.id_expiry_date,
         'Pièce d''identité ' || case when e.id_expiry_date < p_as_of then 'expirée le ' else 'expirant le ' end || to_char(e.id_expiry_date, 'DD/MM/YYYY')
  from public.employees e
  where e.status = 'Active' and e.id_expiry_date is not null and e.id_expiry_date <= p_as_of + p_horizon_days;
end;
$$;


--
-- Name: load_module_manifest(jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.load_module_manifest(p_manifest jsonb, p_hash text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id text := p_manifest->>'module_id'; v_old text; v_seeded int;
begin
  if not (select public.has_role(array['rh'])) then
    raise exception 'droits insuffisants' using errcode = '42501';
  end if;
  if v_id is null or p_manifest->>'version' is null or p_manifest->>'module_name' is null then
    raise exception 'manifeste invalide : module_id, module_name et version obligatoires';
  end if;
  select hash into v_old from public.module_manifest where module_id = v_id;
  insert into public.module_manifest(module_id, name, version, status, hash, manifest)
  values (v_id, p_manifest->>'module_name', p_manifest->>'version', coalesce(p_manifest->>'status', 'draft'), p_hash, p_manifest)
  on conflict (module_id) do update
    set name = excluded.name, version = excluded.version, status = excluded.status,
        hash = excluded.hash, manifest = excluded.manifest, loaded_at = now()
    where public.module_manifest.hash is distinct from excluded.hash;
  insert into public.module_parameter_value(module_id, param_key, value, legal_status, source)
  select v_id, p.key, p.value->'value', p.value->>'legal_status', p.value->>'source'
  from jsonb_each(coalesce(p_manifest->'parameters', '{}'::jsonb)) p
  where p.value->>'legal_status' in ('verified','secondary')
    and jsonb_typeof(p.value->'value') is not null and jsonb_typeof(p.value->'value') <> 'null'
    and not exists (select 1 from public.module_parameter_value v where v.module_id = v_id and v.param_key = p.key);
  get diagnostics v_seeded = row_count;
  return jsonb_build_object('module_id', v_id, 'changed', v_old is distinct from p_hash, 'seeded', v_seeded);
end $$;


--
-- Name: employee_document_access_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_document_access_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    document_id uuid NOT NULL,
    user_id uuid DEFAULT auth.uid() NOT NULL,
    accessed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: log_employee_document_access(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_employee_document_access(p_document_id uuid) RETURNS public.employee_document_access_log
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_log public.employee_document_access_log;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentification requise';
  end if;
  if not exists (
    select 1
    from public.employee_documents d
    where d.id = p_document_id
      and (
        (select public.has_role(array['rh']))
        or d.employee_id = (select public.my_employee_id())
      )
  ) then
    raise exception 'Document introuvable ou non autoris??';
  end if;

  insert into public.employee_document_access_log(document_id, user_id)
  values (p_document_id, (select auth.uid()))
  returning * into v_log;
  return v_log;
end;
$$;


--
-- Name: majoration_retard_cotisations(numeric, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.majoration_retard_cotisations(p_amount numeric, p_due_date date, p_paid_on date) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
declare
  v_months integer;
begin
  if p_amount is null or p_amount <= 0 or p_paid_on <= p_due_date then return 0; end if;
  v_months := (extract(year from p_paid_on)::int - extract(year from p_due_date)::int) * 12
            + (extract(month from p_paid_on)::int - extract(month from p_due_date)::int)
            + case when extract(day from p_paid_on) > extract(day from p_due_date) then 1 else 0 end;
  v_months := greatest(1, v_months);
  return p_amount * least(0.10 * v_months, 0.50);
end;
$$;


--
-- Name: FUNCTION majoration_retard_cotisations(p_amount numeric, p_due_date date, p_paid_on date); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.majoration_retard_cotisations(p_amount numeric, p_due_date date, p_paid_on date) IS '10 % par mois ou fraction de mois de retard, plafonné à 50 % (CSS art. 320). Le plafond est annuel : au-delà d''un an, appliquer le calcul par année.';


--
-- Name: manager_has_employee(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manager_has_employee(p_employee_id uuid, p_on_date date DEFAULT CURRENT_DATE) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1
    from public.employee_manager_assignments a
    where (select public.has_role(array['manager']))
      and a.manager_employee_id = (select public.my_employee_id())
      and a.employee_id = p_employee_id
      and p_on_date >= a.valid_from
      and (a.valid_to is null or p_on_date <= a.valid_to)
  );
$$;


--
-- Name: employee_notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    request_id uuid,
    title text NOT NULL,
    message text NOT NULL,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: mark_employee_notification_read(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_employee_notification_read(p_notification_id uuid) RETURNS public.employee_notifications
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_notification public.employee_notifications;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentification requise';
  end if;

  update public.employee_notifications
     set read_at = coalesce(read_at, now())
   where id = p_notification_id
     and user_id = (select auth.uid())
  returning * into v_notification;

  if not found then
    raise exception 'Notification introuvable ou non autorisée';
  end if;

  return v_notification;
end;
$$;


--
-- Name: module_activation_stamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.module_activation_stamp() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if new.enabled and (tg_op = 'INSERT' or not old.enabled) then
    select m.version, m.hash into new.manifest_version, new.manifest_hash
      from public.module_manifest m where m.module_id = new.module_id;
    new.enabled_at := now(); new.enabled_by := (select auth.uid()); new.disabled_at := null;
  elsif not new.enabled and tg_op = 'UPDATE' and old.enabled then
    new.disabled_at := now();
  end if;
  return new;
end $$;


--
-- Name: my_employee_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.my_employee_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select e.id from public.employees e where e.user_id = (select auth.uid()) limit 1;
$$;


--
-- Name: my_leave_approvals(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.my_leave_approvals() RETURNS TABLE(leave_id uuid, employee_number text, employee_name text, leave_type text, from_date date, to_date date, total_days numeric, reason text, step smallint, level text, due_at timestamp with time zone, overdue boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select l.id, e.employee_number, e.first_name || ' ' || e.last_name, l.leave_type, l.from_date, l.to_date,
         l.total_days, l.reason, s.step, s.level, s.due_at, coalesce(s.due_at < now(), false)
    from public.leave_applications l
    join public.employees e on e.id = l.employee_id
    join lateral (select * from public.leave_approval_steps x where x.leave_id = l.id and x.status = 'En attente' order by x.step limit 1) s on true
   where l.status = 'Ouverte'
     and l.employee_id is distinct from (select public.my_employee_id())
     and not exists (select 1 from public.leave_approval_steps d where d.leave_id = l.id and d.decided_by = (select auth.uid()))
     and (public.has_role(array['admin'])
          or (s.level = 'rh' and public.has_role(array['rh']))
          or (s.level = 'manager' and public.user_manages_employee((select auth.uid()), l.employee_id, l.from_date)))
   order by l.from_date
$$;


--
-- Name: next_employee_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.next_employee_number() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v text;
begin
  loop
    v := 'S' || lpad(nextval('public.employee_number_seq')::text, 4, '0');
    exit when not exists (select 1 from public.employees where upper(employee_number) = v);
  end loop;
  return v;
end;
$$;


--
-- Name: leave_applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_applications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    leave_type text NOT NULL,
    from_date date NOT NULL,
    to_date date NOT NULL,
    half_day boolean DEFAULT false NOT NULL,
    total_days numeric GENERATED ALWAYS AS (
CASE
    WHEN half_day THEN 0.5
    ELSE (((to_date - from_date) + 1))::numeric
END) STORED,
    reason text,
    status text DEFAULT 'Ouverte'::text NOT NULL,
    approver_id uuid,
    approved_at timestamp with time zone,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT leave_applications_check CHECK ((to_date >= from_date)),
    CONSTRAINT leave_applications_status_check CHECK ((status = ANY (ARRAY['Ouverte'::text, 'Approuvée'::text, 'Rejetée'::text, 'Annulée'::text])))
);


--
-- Name: notify_leave_approvers(public.leave_applications, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_leave_approvers(p_leave public.leave_applications, p_level text, p_text text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r record;
begin
  if p_level = 'rh' then
    for r in select distinct user_id from public.user_roles where role = 'rh' loop
      perform public.notify_user(r.user_id, 'Congé à valider (RH)', p_text, 'leave:' || p_leave.id || ':rh');
    end loop;
  else
    for r in
      select m.user_id from public.employee_manager_assignments a join public.employees m on m.id = a.manager_employee_id
       where a.employee_id = p_leave.employee_id and p_leave.from_date >= a.valid_from and (a.valid_to is null or p_leave.from_date <= a.valid_to)
      union
      select d.delegate_user from public.approval_delegations d
        join public.employees m on m.user_id = d.delegator_user
        join public.employee_manager_assignments a on a.manager_employee_id = m.id
       where d.active and current_date between d.valid_from and d.valid_to and a.employee_id = p_leave.employee_id
    loop
      perform public.notify_user(r.user_id, 'Congé à valider (manager)', p_text, 'leave:' || p_leave.id || ':manager');
    end loop;
  end if;
end;
$$;


--
-- Name: notify_user(uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_user(p_user uuid, p_title text, p_message text, p_key text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_email text;
begin
  if p_user is null then return; end if;
  insert into public.employee_notifications(user_id, title, message) values (p_user, p_title, p_message);
  select email into v_email from auth.users where id = p_user;
  if v_email is not null then
    insert into public.email_outbox(to_email, subject, body, dedup_key)
    values (v_email, p_title, p_message, p_key || ':' || p_user::text)
    on conflict (dedup_key) do nothing;
  end if;
end;
$$;


--
-- Name: org_apply_reorg(jsonb, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_apply_reorg(p_moves jsonb, p_from date, p_reason text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare m jsonb; n integer := 0;
begin
  perform public.org_require_hr(p_reason);
  if p_from is null then raise exception 'La date d''effet est obligatoire'; end if;
  if jsonb_typeof(p_moves) is distinct from 'array' or jsonb_array_length(p_moves) = 0 then raise exception 'Aucun changement à appliquer'; end if;
  for m in select * from jsonb_array_elements(p_moves) loop
    case m->>'kind'
      when 'manager' then perform public.org_set_manager((m->>'employee')::uuid, nullif(m->>'manager', '')::uuid, p_from, p_reason);
      when 'unit' then perform public.org_set_employee_unit((m->>'employee')::uuid, nullif(m->>'unit', '')::uuid, p_reason);
      when 'relation' then perform public.org_save_relation(null, (m->>'employee')::uuid, (m->>'related')::uuid, m->>'type', p_from,
                                                            nullif(m->>'end', '')::date, nullif(m->>'pct', '')::numeric, null, p_reason);
      else raise exception 'Type de changement inconnu : %', m->>'kind';
    end case;
    n := n + 1;
  end loop;
  return n;
end;
$$;


--
-- Name: org_attach_to_unit(uuid, uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_attach_to_unit(p_employee uuid, p_unit uuid, p_link_head boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  e public.employees; u public.departments;
  v_prev_unit text; v_prev_mgr uuid; v_prev_mgr_name text; v_new_mgr uuid; v_new_mgr_name text; v_msg text;
begin
  perform public.org_require_hr(null);
  select * into e from public.employees where id = p_employee;
  if not found then raise exception 'Salarié introuvable'; end if;
  select * into u from public.departments where id = p_unit;
  if not found then raise exception 'Unité introuvable'; end if;
  select name into v_prev_unit from public.departments where id = e.department_id;
  select a.manager_employee_id, m.first_name || ' ' || m.last_name into v_prev_mgr, v_prev_mgr_name
    from public.employee_manager_assignments a join public.employees m on m.id = a.manager_employee_id
   where a.employee_id = p_employee and current_date between a.valid_from and coalesce(a.valid_to, date 'infinity') limit 1;

  update public.employees set department_id = p_unit where id = p_employee;

  -- le salarié suit son manager direct : on le rattache aussi au responsable de la direction si on le demande
  if p_link_head and u.head_employee_id is not null and u.head_employee_id <> p_employee and u.head_employee_id is distinct from v_prev_mgr then
    perform public.org_set_manager(p_employee, u.head_employee_id, current_date, 'Rattachement à ' || u.name);
    v_new_mgr := u.head_employee_id;
    select first_name || ' ' || last_name into v_new_mgr_name from public.employees where id = v_new_mgr;
  end if;

  v_msg := e.first_name || ' ' || e.last_name || ' est rattaché(e) à « ' || u.name || ' »'
        || case when v_prev_unit is not null and v_prev_unit <> u.name then ' (auparavant : ' || v_prev_unit || ')' else '' end
        || case when v_new_mgr is not null then ' ; son manager direct passe de ' || coalesce(v_prev_mgr_name, 'aucun') || ' à ' || v_new_mgr_name
                when v_prev_mgr is not null then ' ; son manager direct reste ' || v_prev_mgr_name else '' end || '.';
  if e.user_id is not null then
    perform public.notify_user(e.user_id, 'Changement de rattachement', v_msg, 'org-unit:' || p_employee || ':' || p_unit || ':' || current_date);
  end if;
  perform public.org_log('employees', p_employee, 'rattachement_unite', null,
          jsonb_build_object('unite', p_unit, 'unite_precedente', v_prev_unit, 'manager_precedent', v_prev_mgr, 'nouveau_manager', v_new_mgr));
  return jsonb_build_object('message', v_msg, 'unite_precedente', v_prev_unit, 'manager_precedent', v_prev_mgr_name,
                            'nouveau_manager', v_new_mgr_name, 'notifie', e.user_id is not null);
end;
$$;


--
-- Name: org_chart(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_chart(p_on date DEFAULT CURRENT_DATE) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_hr boolean := public.has_role(array['rh']);
  v_nodes jsonb; v_edges jsonb; v_teams jsonb; v_anom jsonb := '[]'::jsonb;
begin
  if (select auth.uid()) is null or not (public.has_role(array['rh', 'paie', 'manager', 'salarie']) or (select public.my_employee_id()) is not null) then
    raise exception 'Droits insuffisants pour consulter l''organigramme';
  end if;

  create temp table if not exists pg_temp.org_nodes (id uuid primary key) on commit drop;
  truncate pg_temp.org_nodes;
  insert into pg_temp.org_nodes
    select e.id from public.employees e
     where e.status in ('Active', 'Left', 'Suspended') and e.date_of_joining <= p_on
       and (e.relieving_date is null or e.relieving_date >= p_on);

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', e.id, 'matricule', e.employee_number, 'prenom', e.first_name, 'nom', e.last_name,
      'poste', coalesce(d.name, ''), 'poste_id', e.designation_id, 'departement', dep.name, 'unite', e.department_id,
      'email', case when v_hr then e.email_work end,
      'statut', case
          when exists (select 1 from public.leave_applications l where l.employee_id = e.id and l.status = 'Approuvée' and p_on between l.from_date and l.to_date) then 'en_conge'
          when exists (select 1 from public.org_relations r where r.employee_id = e.id and r.relation_type = 'interim' and p_on between r.start_date and coalesce(r.end_date, date 'infinity')) then 'interim'
          else 'actif' end,
      'sortie', e.relieving_date,
      'responsable_de', coalesce((select jsonb_agg(u.name order by u.name) from public.departments u where u.head_employee_id = e.id), '[]'::jsonb)
        || coalesce((select jsonb_agg(t2.name order by t2.name) from public.teams t2 where t2.lead_employee_id = e.id and p_on between t2.start_date and coalesce(t2.end_date, date 'infinity')), '[]'::jsonb),
      'subordonnes', (select count(*) from public.employee_manager_assignments a
                       where a.manager_employee_id = e.id and p_on between a.valid_from and coalesce(a.valid_to, date 'infinity')
                         and a.employee_id in (select id from pg_temp.org_nodes)),
      'equipes', (select count(*) from public.team_members m join public.teams t on t.id = m.team_id
                   where m.employee_id = e.id and p_on between m.start_date and coalesce(m.end_date, date 'infinity')
                     and p_on between t.start_date and coalesce(t.end_date, date 'infinity'))
    ) order by e.last_name, e.first_name), '[]'::jsonb)
    into v_nodes
    from public.employees e
    left join public.designations d on d.id = e.designation_id
    left join public.departments dep on dep.id = e.department_id
   where e.id in (select id from pg_temp.org_nodes);

  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_edges from (
    select jsonb_build_object('id', a.id, 'type', 'direct', 'source', a.manager_employee_id, 'target', a.employee_id,
                              'debut', a.valid_from, 'fin', a.valid_to) as x
      from public.employee_manager_assignments a
     where p_on between a.valid_from and coalesce(a.valid_to, date 'infinity')
       and a.employee_id in (select id from pg_temp.org_nodes) and a.manager_employee_id in (select id from pg_temp.org_nodes)
    union all
    select jsonb_build_object('id', r.id, 'type', r.relation_type, 'source', r.related_employee_id, 'target', r.employee_id,
                              'debut', r.start_date, 'fin', r.end_date, 'quote_part', r.allocation_pct, 'note', r.note)
      from public.org_relations r
     where p_on between r.start_date and coalesce(r.end_date, date 'infinity')
       and r.employee_id in (select id from pg_temp.org_nodes) and r.related_employee_id in (select id from pg_temp.org_nodes)
  ) t;

  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'nom', t.name, 'type', t.kind, 'responsable', t.lead_employee_id,
      'debut', t.start_date, 'fin', t.end_date,
      'membres', (select coalesce(jsonb_agg(jsonb_build_object('employe', m.employee_id, 'role', m.role_in_team, 'quote_part', m.allocation_pct)), '[]'::jsonb)
                    from public.team_members m where m.team_id = t.id and p_on between m.start_date and coalesce(m.end_date, date 'infinity')
                      and m.employee_id in (select id from pg_temp.org_nodes))
    ) order by t.name), '[]'::jsonb)
    into v_teams from public.teams t where p_on between t.start_date and coalesce(t.end_date, date 'infinity');

  -- anomalies
  v_anom := v_anom || coalesce((
    select jsonb_agg(jsonb_build_object('code', 'manager_sorti', 'employe', a.employee_id,
             'message', 'Le manager a quitté la société le ' || to_char(m.relieving_date, 'DD/MM/YYYY') || ' : réaffecter ce salarié'))
      from public.employee_manager_assignments a join public.employees m on m.id = a.manager_employee_id
     where m.relieving_date is not null and m.relieving_date < p_on
       and p_on between a.valid_from and coalesce(a.valid_to, date 'infinity')
       and a.employee_id in (select id from pg_temp.org_nodes)), '[]'::jsonb);
  v_anom := v_anom || coalesce((
    select jsonb_agg(jsonb_build_object('code', 'interim_expire', 'employe', r.employee_id,
             'message', 'Intérim terminé le ' || to_char(r.end_date, 'DD/MM/YYYY') || ' : confirmer ou clôturer'))
      from public.org_relations r
     where r.relation_type = 'interim' and r.end_date < p_on and r.end_date >= p_on - 90
       and r.employee_id in (select id from pg_temp.org_nodes)), '[]'::jsonb);
  v_anom := v_anom || coalesce((
    select jsonb_agg(jsonb_build_object('code', 'allocation_depassee', 'employe', s.employee_id,
             'message', 'Quotes-parts cumulées de ' || s.total || ' % (maximum 100 %)'))
      from (select employee_id, sum(pct) as total from (
              select r.employee_id, r.allocation_pct as pct from public.org_relations r
               where r.allocation_pct is not null and p_on between r.start_date and coalesce(r.end_date, date 'infinity')
              union all
              select m.employee_id, m.allocation_pct from public.team_members m
               where p_on between m.start_date and coalesce(m.end_date, date 'infinity')) q
             group by employee_id having sum(pct) > 100) s
     where s.employee_id in (select id from pg_temp.org_nodes)), '[]'::jsonb);
  -- salarié sans manager et sans subordonné : non rattaché à la hiérarchie (les têtes de branche ne sont pas des anomalies)
  v_anom := v_anom || coalesce((
    select jsonb_agg(jsonb_build_object('code', 'sans_manager', 'employe', n.id, 'message', 'Aucun manager direct à cette date'))
      from pg_temp.org_nodes n
     where not exists (select 1 from public.employee_manager_assignments a
                        where a.employee_id = n.id and p_on between a.valid_from and coalesce(a.valid_to, date 'infinity'))
       and not exists (select 1 from public.employee_manager_assignments a2
                        where a2.manager_employee_id = n.id and p_on between a2.valid_from and coalesce(a2.valid_to, date 'infinity'))), '[]'::jsonb);

  return jsonb_build_object('date', p_on, 'noeuds', v_nodes, 'liens', v_edges, 'equipes', v_teams, 'anomalies', v_anom,
    'unites', (select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'nom', u.name, 'type', u.kind, 'parent', u.parent_id, 'responsable', u.head_employee_id,
                 'membres', (select count(*) from public.employees e2 where e2.department_id = u.id and e2.id in (select id from pg_temp.org_nodes))) order by u.name), '[]'::jsonb)
                 from public.departments u),
    'postes', (select coalesce(jsonb_agg(jsonb_build_object('id', ds.id, 'nom', ds.name) order by ds.name), '[]'::jsonb)
                 from public.designations ds where ds.is_active is not false),
    'vacants', case when public.has_role(array['rh', 'paie']) then (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'unite', p.unit_id, 'poste_id', p.designation_id, 'poste', ds2.name,
                 'prevus', p.headcount, 'pourvus', pv.n, 'vacants', greatest(p.headcount - pv.n, 0), 'note', p.note) order by ds2.name), '[]'::jsonb)
                 from public.org_positions p join public.designations ds2 on ds2.id = p.designation_id
                 cross join lateral (select count(*)::int as n from public.employees e where e.department_id = p.unit_id and e.designation_id = p.designation_id
                                       and e.id in (select id from pg_temp.org_nodes)) pv) else '[]'::jsonb end);
end;
$$;


--
-- Name: org_delete_position(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_delete_position(p_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.org_require_hr(null);
  delete from public.org_positions where id = p_id;
  if not found then raise exception 'Poste prévu introuvable'; end if;
  perform public.org_log('org_positions', p_id, 'poste_prevu_supprime', null, '{}'::jsonb);
end;
$$;


--
-- Name: org_delete_unit(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_delete_unit(p_id uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_n integer; v_name text;
begin
  perform public.org_require_hr(null);
  select name into v_name from public.departments where id = p_id;
  if v_name is null then raise exception 'Unité introuvable'; end if;
  if exists (select 1 from public.departments where parent_id = p_id) then
    raise exception 'Cette unité contient des sous-unités : déplacez-les ou supprimez-les d''abord';
  end if;
  update public.employees set department_id = null where department_id = p_id;
  get diagnostics v_n = row_count;
  delete from public.departments where id = p_id;
  perform public.org_log('departments', p_id, 'suppression_unite', null, jsonb_build_object('nom', v_name, 'salaries_detaches', v_n));
  return v_n;
end;
$$;


--
-- Name: org_end_relation(uuid, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_end_relation(p_id uuid, p_end date, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.org_require_hr(p_reason);
  update public.org_relations set end_date = p_end where id = p_id and start_date <= p_end and (end_date is null or end_date > p_end);
  if not found then raise exception 'Lien introuvable, déjà terminé à cette date, ou date de fin antérieure au début'; end if;
  perform public.org_log('org_relations', p_id, 'fin_lien', trim(p_reason), jsonb_build_object('fin', p_end));
end;
$$;


--
-- Name: org_log(text, uuid, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_log(p_table text, p_record uuid, p_action text, p_reason text, p_data jsonb) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$ insert into public.audit_log (table_name, record_id, action, reason, new_data) values (p_table, p_record, p_action, nullif(trim(coalesce(p_reason, '')), ''), p_data) $$;


--
-- Name: org_log_export(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_log_export(p_format text, p_rows integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if (select auth.uid()) is null then raise exception 'Connexion requise'; end if;
  insert into public.audit_log (table_name, action, new_data) values ('organigramme', 'export_organigramme', jsonb_build_object('format', p_format, 'lignes', p_rows));
end;
$$;


--
-- Name: org_prevent_cycle(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_prevent_cycle() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if new.manager_employee_id = new.employee_id then
    raise exception 'Un salarié ne peut pas être son propre manager';
  end if;
  -- un seul manager direct valide à une date donnée (règle 2 du module ; l'ancien contrôle ne visait que le même couple)
  if exists (select 1 from public.employee_manager_assignments a
              where a.id is distinct from new.id and a.employee_id = new.employee_id
                and a.valid_from <= coalesce(new.valid_to, date 'infinity')
                and coalesce(a.valid_to, date 'infinity') >= new.valid_from) then
    raise exception 'Ce salarié a déjà un manager direct sur cette période : utilisez « changer de manager » (date d''effet) plutôt que d''ajouter un second rattachement';
  end if;
  if exists (
    with recursive up(id, depth) as (
      select new.manager_employee_id, 1
      union all
      select a.manager_employee_id, up.depth + 1
        from up join public.employee_manager_assignments a on a.employee_id = up.id
       where a.id is distinct from new.id and up.depth < 60
         and a.valid_from <= coalesce(new.valid_to, date 'infinity')
         and coalesce(a.valid_to, date 'infinity') >= new.valid_from)
    select 1 from up where id = new.employee_id) then
    raise exception 'Cycle hiérarchique refusé : ce rattachement ferait du manager un subordonné de ce salarié (directement ou indirectement)';
  end if;
  return new;
end;
$$;


--
-- Name: org_relations_no_overlap(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_relations_no_overlap() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if exists (select 1 from public.org_relations r
              where r.id is distinct from new.id and r.employee_id = new.employee_id
                and r.related_employee_id = new.related_employee_id and r.relation_type = new.relation_type
                and r.start_date <= coalesce(new.end_date, date 'infinity')
                and coalesce(r.end_date, date 'infinity') >= new.start_date) then
    raise exception 'Un lien du même type existe déjà entre ces deux salariés sur cette période : terminez-le ou modifiez ses dates';
  end if;
  return new;
end;
$$;


--
-- Name: org_remove_team_member(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_remove_team_member(p_team uuid, p_employee uuid, p_note text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.org_require_hr(null);
  delete from public.team_members where team_id = p_team and employee_id = p_employee and start_date > current_date;
  update public.team_members set end_date = current_date
   where team_id = p_team and employee_id = p_employee and (end_date is null or end_date > current_date) and start_date <= current_date;
  perform public.org_log('team_members', p_team, 'retrait_membre', nullif(trim(coalesce(p_note, '')), ''), jsonb_build_object('employe', p_employee));
end;
$$;


--
-- Name: org_require_hr(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_require_hr(p_reason text) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
begin
  if not public.has_role(array['rh']) then raise exception 'Réservé au service RH (ou à un administrateur)'; end if;
end;
$$;


--
-- Name: org_save_position(uuid, uuid, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_save_position(p_unit uuid, p_post uuid, p_headcount integer, p_note text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid;
begin
  perform public.org_require_hr(null);
  if p_headcount is null or p_headcount < 1 then raise exception 'L''effectif prévu doit être au moins 1'; end if;
  if not exists (select 1 from public.departments where id = p_unit) then raise exception 'Unité introuvable'; end if;
  if not exists (select 1 from public.designations where id = p_post) then raise exception 'Poste introuvable'; end if;
  insert into public.org_positions(unit_id, designation_id, headcount, note)
  values (p_unit, p_post, p_headcount, nullif(trim(coalesce(p_note, '')), ''))
  on conflict (unit_id, designation_id) do update set headcount = excluded.headcount, note = excluded.note
  returning id into v_id;
  perform public.org_log('org_positions', v_id, 'poste_prevu', null, jsonb_build_object('unite', p_unit, 'poste', p_post, 'effectif', p_headcount));
  return v_id;
end;
$$;


--
-- Name: org_save_post(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_save_post(p_name text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid;
begin
  perform public.org_require_hr(null);
  if coalesce(trim(p_name), '') = '' then raise exception 'Le nom du poste est obligatoire'; end if;
  select id into v_id from public.designations where lower(name) = lower(trim(p_name));
  if v_id is null then
    insert into public.designations(name) values (trim(p_name)) returning id into v_id;
    perform public.org_log('designations', v_id, 'creation_poste', null, jsonb_build_object('nom', trim(p_name)));
  end if;
  return v_id;
end;
$$;


--
-- Name: org_save_relation(uuid, uuid, uuid, text, date, date, numeric, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_save_relation(p_id uuid, p_employee uuid, p_related uuid, p_type text, p_start date, p_end date, p_pct numeric, p_note text, p_reason text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid;
begin
  perform public.org_require_hr(p_reason);
  if p_id is null then
    insert into public.org_relations(employee_id, related_employee_id, relation_type, start_date, end_date, allocation_pct, note)
    values (p_employee, p_related, p_type, p_start, p_end, p_pct, nullif(trim(coalesce(p_note, '')), '')) returning id into v_id;
  else
    update public.org_relations set employee_id = p_employee, related_employee_id = p_related, relation_type = p_type,
           start_date = p_start, end_date = p_end, allocation_pct = p_pct, note = nullif(trim(coalesce(p_note, '')), '')
     where id = p_id returning id into v_id;
    if v_id is null then raise exception 'Lien introuvable'; end if;
  end if;
  perform public.org_log('org_relations', v_id, case when p_id is null then 'creation_lien' else 'modification_lien' end, trim(p_reason),
          jsonb_build_object('type', p_type, 'debut', p_start, 'fin', p_end, 'quote_part', p_pct));
  return v_id;
end;
$$;


--
-- Name: org_save_team(uuid, text, text, uuid, date, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_save_team(p_id uuid, p_name text, p_kind text, p_lead uuid, p_start date, p_end date, p_reason text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid;
begin
  perform public.org_require_hr(p_reason);
  if p_id is null then
    insert into public.teams(name, kind, lead_employee_id, start_date, end_date) values (trim(p_name), p_kind, p_lead, coalesce(p_start, current_date), p_end) returning id into v_id;
  else
    update public.teams set name = trim(p_name), kind = p_kind, lead_employee_id = p_lead, start_date = coalesce(p_start, start_date), end_date = p_end where id = p_id returning id into v_id;
    if v_id is null then raise exception 'Équipe introuvable'; end if;
  end if;
  perform public.org_log('teams', v_id, case when p_id is null then 'creation_equipe' else 'modification_equipe' end, trim(p_reason), jsonb_build_object('nom', trim(p_name), 'type', p_kind));
  return v_id;
end;
$$;


--
-- Name: org_save_unit(uuid, text, text, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_save_unit(p_id uuid, p_name text, p_kind text, p_parent uuid, p_head uuid, p_note text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid; v_company uuid;
begin
  perform public.org_require_hr(null);
  if coalesce(trim(p_name), '') = '' then raise exception 'Le nom est obligatoire'; end if;
  if p_kind not in ('direction', 'secteur', 'section', 'service') then raise exception 'Type d''unité invalide'; end if;
  select coalesce((select company_id from public.departments where id = p_parent), (select company_id from public.departments where id = p_id),
                  (select id from public.companies order by created_at limit 1)) into v_company;
  begin
    if p_id is null then
      insert into public.departments(company_id, name, kind, parent_id, head_employee_id, note)
      values (v_company, trim(p_name), p_kind, p_parent, p_head, nullif(trim(coalesce(p_note, '')), '')) returning id into v_id;
    else
      update public.departments set name = trim(p_name), kind = p_kind, parent_id = p_parent, head_employee_id = p_head, note = nullif(trim(coalesce(p_note, '')), '')
       where id = p_id returning id into v_id;
      if v_id is null then raise exception 'Unité introuvable'; end if;
    end if;
  exception when unique_violation then
    raise exception 'Une unité porte déjà le nom « % »', trim(p_name);
  end;
  perform public.org_log('departments', v_id, case when p_id is null then 'creation_unite' else 'modification_unite' end, nullif(trim(coalesce(p_note, '')), ''),
          jsonb_build_object('nom', trim(p_name), 'type', p_kind, 'parent', p_parent, 'responsable', p_head));
  return v_id;
end;
$$;


--
-- Name: org_set_employee_post(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_set_employee_post(p_employee uuid, p_post uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.org_require_hr(null);
  if p_post is not null and not exists (select 1 from public.designations where id = p_post) then raise exception 'Poste introuvable'; end if;
  update public.employees set designation_id = p_post where id = p_employee;
  if not found then raise exception 'Salarié introuvable'; end if;
  perform public.org_log('employees', p_employee, 'changement_poste', null, jsonb_build_object('poste', p_post));
end;
$$;


--
-- Name: org_set_employee_unit(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_set_employee_unit(p_employee uuid, p_unit uuid, p_note text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.org_require_hr(null);
  if p_unit is not null and not exists (select 1 from public.departments where id = p_unit) then raise exception 'Unité introuvable'; end if;
  update public.employees set department_id = p_unit where id = p_employee;
  if not found then raise exception 'Salarié introuvable'; end if;
  perform public.org_log('employees', p_employee, case when p_unit is null then 'detachement_unite' else 'rattachement_unite' end,
          nullif(trim(coalesce(p_note, '')), ''), jsonb_build_object('unite', p_unit));
end;
$$;


--
-- Name: org_set_manager(uuid, uuid, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_set_manager(p_employee uuid, p_manager uuid, p_from date, p_reason text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid; v_user uuid; v_has boolean; v_emp_user uuid; v_mgr_name text;
begin
  perform public.org_require_hr(p_reason);
  if p_from is null then raise exception 'La date d''effet est obligatoire'; end if;
  select user_id into v_emp_user from public.employees where id = p_employee;
  if not found then raise exception 'Salarié introuvable'; end if;
  select exists (select 1 from public.employee_manager_assignments
                  where employee_id = p_employee and valid_from <= p_from and (valid_to is null or valid_to >= p_from)) into v_has;
  if p_manager is null and not v_has then raise exception 'Ce salarié n''a pas de manager direct à détacher'; end if;
  -- correction le jour même : un rattachement qui commence à la date d'effet est remplacé (sinon « détacher » échouerait)
  delete from public.employee_manager_assignments where employee_id = p_employee and valid_from = p_from;
  if exists (select 1 from public.employee_manager_assignments where employee_id = p_employee and valid_from > p_from) then
    raise exception 'Un rattachement commence déjà à partir de cette date : choisissez une date postérieure';
  end if;
  update public.employee_manager_assignments set valid_to = p_from - 1
   where employee_id = p_employee and valid_from < p_from and (valid_to is null or valid_to >= p_from);
  if p_manager is not null then
    insert into public.employee_manager_assignments(manager_employee_id, employee_id, valid_from, valid_to, delegated_by)
    values (p_manager, p_employee, p_from, null, (select auth.uid())) returning id into v_id;
    select user_id, first_name || ' ' || last_name into v_user, v_mgr_name from public.employees where id = p_manager;
    if v_user is not null then insert into public.user_roles(user_id, role) values (v_user, 'manager') on conflict (user_id, role) do nothing; end if;
  end if;
  perform public.org_log('employee_manager_assignments', coalesce(v_id, p_employee), case when p_manager is null then 'detachement_manager' else 'changement_manager' end,
          nullif(trim(coalesce(p_reason, '')), ''), jsonb_build_object('employe', p_employee, 'manager', p_manager, 'effet', p_from));
  if v_emp_user is not null then
    perform public.notify_user(v_emp_user, 'Changement de manager',
      case when p_manager is null then 'Vous n''avez plus de manager direct à partir du ' || to_char(p_from, 'DD/MM/YYYY') || '.'
           else 'Votre manager direct est ' || v_mgr_name || ' à partir du ' || to_char(p_from, 'DD/MM/YYYY') || '.' end,
      'org-mgr:' || p_employee || ':' || p_from || ':' || coalesce(p_manager::text, 'none'));
  end if;
  return v_id;
end;
$$;


--
-- Name: org_set_team_member(uuid, uuid, text, numeric, date, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_set_team_member(p_team uuid, p_employee uuid, p_role text, p_pct numeric, p_start date, p_end date, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.org_require_hr(p_reason);
  insert into public.team_members(team_id, employee_id, role_in_team, allocation_pct, start_date, end_date)
  values (p_team, p_employee, coalesce(nullif(trim(p_role), ''), 'membre'), coalesce(p_pct, 0), coalesce(p_start, current_date), p_end)
  on conflict (team_id, employee_id, start_date) do update set role_in_team = excluded.role_in_team, allocation_pct = excluded.allocation_pct, end_date = excluded.end_date;
  perform public.org_log('team_members', p_team, 'membre_equipe', trim(p_reason), jsonb_build_object('employe', p_employee, 'quote_part', p_pct));
end;
$$;


--
-- Name: org_set_unit_head(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_set_unit_head(p_unit uuid, p_employee uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.org_require_hr(null);
  update public.departments set head_employee_id = p_employee where id = p_unit;
  if not found then raise exception 'Unité introuvable'; end if;
  perform public.org_log('departments', p_unit, 'responsable_unite', null, jsonb_build_object('responsable', p_employee));
end;
$$;


--
-- Name: org_unit_no_cycle(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_unit_no_cycle() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if new.parent_id is null then return new; end if;
  if new.parent_id = new.id then raise exception 'Une unité ne peut pas dépendre d''elle-même'; end if;
  if exists (with recursive up(id, depth) as (
               select new.parent_id, 1
               union all
               select d.parent_id, up.depth + 1 from up join public.departments d on d.id = up.id where d.parent_id is not null and up.depth < 30)
             select 1 from up where id = new.id) then
    raise exception 'Cycle refusé : cette unité deviendrait sa propre sous-unité';
  end if;
  return new;
end;
$$;


--
-- Name: payment_export(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payment_export(p_payroll_entry_id uuid, p_mode text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare v jsonb; pe public.payroll_entries;
begin
  if not public.has_role(array['paie']) then
    raise exception 'Droits insuffisants : rôle « paie » requis pour exporter les ordres de paiement';
  end if;
  select * into pe from public.payroll_entries where id = p_payroll_entry_id;
  if not found then raise exception 'Traitement de paie introuvable'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'ordre', t.rn, 'matricule', t.employee_number, 'nom', t.employee_name, 'mode', t.mode,
           'banque', t.bank_name, 'compte', t.bank_account, 'montant', t.amount, 'devise', 'XOF',
           'reference', 'PAIE-' || to_char(pe.period_start, 'YYYY-MM') || '-' || t.employee_number,
           'echeance', pe.period_end) order by t.rn), '[]'::jsonb)
    into v
    from (select row_number() over (order by o.employee_number) as rn, o.*, e.bank_name, e.bank_account
            from public.payment_orders(p_payroll_entry_id) o join public.employees e on e.id = o.employee_id
           where p_mode is null or o.mode = p_mode) t;
  return v;
end;
$$;


--
-- Name: payment_orders(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payment_orders(p_payroll_entry_id uuid) RETURNS TABLE(slip_id uuid, employee_id uuid, employee_number text, employee_name text, mode text, net_exact numeric, amount bigint, paid boolean)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select s.id, s.employee_id, s.employee_number, s.employee_name,
         coalesce(nullif(s.payment_mode, ''), 'espèces'), s.net_pay, round(s.net_pay)::bigint,
         coalesce(p.status = 'Payé', false)
    from public.salary_slips s
    left join public.salary_payments p on p.slip_id = s.id
   where s.payroll_entry_id = p_payroll_entry_id and s.status = 'Validé'
     and public.has_role(array['paie', 'rh'])
   order by s.employee_number
$$;


--
-- Name: payment_summary(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payment_summary(p_payroll_entry_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare
  v_n integer; v_orders bigint; v_net numeric; v_by jsonb; v_anom jsonb := '[]'::jsonb;
begin
  if not public.has_role(array['paie', 'rh']) then
    raise exception 'Droits insuffisants : rôle « paie » ou « rh » requis';
  end if;
  select count(*), coalesce(sum(amount), 0), coalesce(sum(net_exact), 0)
    into v_n, v_orders, v_net from public.payment_orders(p_payroll_entry_id);

  select coalesce(jsonb_agg(jsonb_build_object('mode', mode, 'ordres', n, 'du', du, 'paye', paye, 'reste', du - paye) order by mode), '[]'::jsonb)
    into v_by
    from (select mode, count(*) as n, sum(amount) as du, coalesce(sum(amount) filter (where paid), 0) as paye
            from public.payment_orders(p_payroll_entry_id) group by mode) t;

  -- anomalies de rapprochement
  v_anom := v_anom || coalesce((
    select jsonb_agg(jsonb_build_object('code', 'mode_different', 'matricule', o.employee_number,
             'message', 'Paiement enregistré en « ' || p.payment_mode || ' » alors que le bulletin prévoit « ' || o.mode || ' »'))
      from public.payment_orders(p_payroll_entry_id) o join public.salary_payments p on p.slip_id = o.slip_id
     where p.payment_mode <> o.mode), '[]'::jsonb);
  v_anom := v_anom || coalesce((
    select jsonb_agg(jsonb_build_object('code', 'paiement_orphelin', 'matricule', s.employee_number,
             'message', 'Paiement enregistré sur un bulletin qui n''est plus validé (statut « ' || s.status || ' »)'))
      from public.salary_slips s join public.salary_payments p on p.slip_id = s.id
     where s.payroll_entry_id = p_payroll_entry_id and s.status <> 'Validé'), '[]'::jsonb);
  v_anom := v_anom || coalesce((
    select jsonb_agg(jsonb_build_object('code', 'compte_manquant', 'matricule', o.employee_number,
             'message', 'Paiement par virement sans compte bancaire renseigné'))
      from public.payment_orders(p_payroll_entry_id) o join public.employees e on e.id = o.employee_id
     where o.mode ~* 'virement|banc' and coalesce(trim(e.bank_account), '') = ''), '[]'::jsonb);

  return jsonb_build_object(
    'ordres', v_n, 'total_ordres', v_orders, 'total_nets', v_net,
    'ecart_arrondi', v_orders - v_net, 'ecart_max', v_n * 0.5,
    'ok', abs(v_orders - v_net) <= v_n * 0.5,
    'par_mode', v_by, 'anomalies', v_anom);
end;
$$;


--
-- Name: payroll_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    posting_date date DEFAULT CURRENT_DATE NOT NULL,
    payment_mode text DEFAULT 'espèces'::text NOT NULL,
    status text DEFAULT 'Brouillon'::text NOT NULL,
    notes text,
    created_by uuid DEFAULT auth.uid(),
    submitted_by uuid,
    submitted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    settings_snapshot jsonb,
    period_id uuid,
    approved_by uuid,
    approved_at timestamp with time zone,
    paid_by uuid,
    paid_at timestamp with time zone,
    closed_by uuid,
    closed_at timestamp with time zone,
    reopened_by uuid,
    reopened_at timestamp with time zone,
    reopen_reason text,
    CONSTRAINT payroll_entries_check CHECK ((period_end >= period_start)),
    CONSTRAINT payroll_entries_status_check CHECK ((status = ANY (ARRAY['Brouillon'::text, 'Calculée'::text, 'En revue'::text, 'Approuvée'::text, 'Validée'::text, 'Payée'::text, 'Clôturée'::text, 'Réouverte'::text, 'Annulée'::text])))
);


--
-- Name: payroll_assert_separation(public.payroll_entries, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_assert_separation(p_entry public.payroll_entries, p_action text, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_actor uuid := auth.uid();
begin
  -- created_by : a lancé le calcul ; submitted_by : a envoyé la paie en revue (avant approbation)
  if v_actor is null
     or (v_actor is distinct from p_entry.created_by and v_actor is distinct from p_entry.submitted_by) then
    return;
  end if;
  if public.has_role(array['admin']) and nullif(trim(p_reason), '') is not null then
    insert into public.audit_events(actor_id, action, resource_type, resource_id, payroll_entry_id, after_data, reason)
    values (v_actor, 'derogation_separation', 'payroll_entry', p_entry.id, p_entry.id,
            jsonb_build_object('action', p_action, 'statut', p_entry.status), p_reason);
    return;
  end if;
  raise exception using errcode = 'SD403',
    message = 'Séparation des tâches : la personne qui a préparé cette paie ne peut pas la ' || p_action
              || '. ' || case when public.has_role(array['admin'])
                              then 'En tant qu''administrateur, vous pouvez déroger en indiquant un motif.'
                              else 'Demandez à une autre personne habilitée, ou à un administrateur.' end;
end;
$$;


--
-- Name: payroll_closing_report(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_closing_report(p_payroll_entry_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  pe public.payroll_entries;
  v jsonb;
begin
  if not public.has_role(array['admin', 'rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « admin », « rh » ou « paie » requis pour le rapport de clôture';
  end if;
  select * into pe from public.payroll_entries where id = p_payroll_entry_id;
  if not found then raise exception 'Traitement de paie introuvable'; end if;
  select jsonb_build_object(
    'entry', jsonb_build_object('id', pe.id, 'period_start', pe.period_start, 'period_end', pe.period_end,
                                'status', pe.status, 'closed_at', pe.closed_at),
    'totals', (select jsonb_build_object('slips', count(*), 'gross_pay', coalesce(sum(gross_pay), 0),
                                         'net_pay', coalesce(sum(net_pay), 0),
                                         'employer_charges', coalesce(sum(employer_charges), 0),
                                         'payroll_cost', coalesce(sum(payroll_cost), 0))
                 from public.salary_slips where payroll_entry_id = pe.id and status <> 'Annulé'),
    'checks', public.payroll_entry_checks(pe.id),
    'history', coalesce((select jsonb_agg(jsonb_build_object('at', l.occurred_at, 'action', l.action, 'result', l.result,
                                'actor', (select u.email from auth.users u where u.id = l.actor),
                                'from', l.old_data ->> 'status', 'to', coalesce(l.new_data ->> 'status', l.new_data ->> 'cible'),
                                'reason', l.reason) order by l.chain_pos)
                         from public.audit_log l where l.payroll_entry_id = pe.id), '[]'::jsonb),
    'snapshot', (select jsonb_build_object('hash', s.payload_hash, 'algo', s.hash_algo, 'at', s.created_at)
                   from public.payroll_snapshots s where s.payroll_entry_id = pe.id),
    'audit_chain_breaks', case when public.has_role(array['rh']) then (select count(*) from public.audit_verify()) end
  ) into v;
  return v;
end;
$$;


--
-- Name: payroll_entry_checks(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_entry_checks(p_payroll_entry_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
   where period_start < pe.period_start and status in ('Validée', 'Payée', 'Clôturée')
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
       and e.date_of_joining <= pe.period_end
       and (e.relieving_date is null or e.relieving_date >= pe.period_start)
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
$$;


--
-- Name: payroll_entry_comparison(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_entry_comparison(p_payroll_entry_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare
  pe public.payroll_entries;
  v_prev public.payroll_entries;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants';
  end if;
  select * into pe from public.payroll_entries where id = p_payroll_entry_id;
  if not found then return null; end if;
  select * into v_prev from public.payroll_entries
   where period_start < pe.period_start and status in ('Validée', 'Payée', 'Clôturée')
   order by period_start desc limit 1;
  if not found then return null; end if;

  return jsonb_build_object(
    'previous_period', v_prev.period_start,
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
               'employee_number', e.employee_number, 'name', e.last_name || ' ' || e.first_name,
               'prev_gross', p.gross_pay, 'gross', c.gross_pay, 'prev_net', p.net_pay, 'net', c.net_pay)
             order by e.employee_number)
        from (select employee_id, gross_pay, net_pay from public.salary_slips where payroll_entry_id = pe.id and status <> 'Annulé') c
        full join (select employee_id, gross_pay, net_pay from public.salary_slips where payroll_entry_id = v_prev.id and status <> 'Annulé') p
               on p.employee_id = c.employee_id
        join public.employees e on e.id = coalesce(c.employee_id, p.employee_id)), '[]'::jsonb));
end;
$$;


--
-- Name: payroll_entry_period_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_entry_period_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare v_prev date := (date_trunc('month', new.period_start) - interval '1 month')::date;
begin
  if new.status = 'Validée' and (tg_op = 'INSERT' or old.status is distinct from 'Validée') then
    if new.period_start > date_trunc('month', current_date)::date then
      raise exception 'Période % : impossible de valider un mois futur', to_char(new.period_start, 'MM/YYYY');
    end if;
    if not public.has_role(array['admin'])
       and exists (select 1 from public.payroll_entries e where e.period_start < new.period_start and e.id <> new.id)
       and not exists (select 1 from public.payroll_entries e
                       where date_trunc('month', e.period_start) = v_prev and e.status = 'Validée') then
      raise exception 'Période % : le mois précédent (%) n''est pas validé. Validez-le d''abord (ou demandez à un administrateur).',
        to_char(new.period_start, 'MM/YYYY'), to_char(v_prev, 'MM/YYYY');
    end if;
  end if;
  return new;
end;
$$;


--
-- Name: payroll_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_settings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    effective_from date NOT NULL,
    monthly_hours numeric DEFAULT 173.33 NOT NULL,
    hourly_rate_divisor numeric DEFAULT 173.3333333333333333 NOT NULL,
    cfce_rate numeric DEFAULT 0.03 NOT NULL,
    brs_rate numeric DEFAULT 0.05 NOT NULL,
    ipres_rg_ceiling numeric DEFAULT 432000 NOT NULL,
    ipres_rg_rate numeric DEFAULT 0.14 NOT NULL,
    ipres_rg_employee_share numeric DEFAULT 0.4 NOT NULL,
    ipres_rc_ceiling numeric DEFAULT 1296000 NOT NULL,
    ipres_rc_rate numeric DEFAULT 0.06 NOT NULL,
    ipres_rc_employee_share numeric DEFAULT 0.4 NOT NULL,
    css_ceiling numeric DEFAULT 63000 NOT NULL,
    css_af_rate numeric DEFAULT 0.07 NOT NULL,
    css_at_rate numeric DEFAULT 0.05 NOT NULL,
    ipm_ceiling numeric DEFAULT 10000 NOT NULL,
    ipm_rate numeric DEFAULT 1 NOT NULL,
    ipm_employee_share numeric DEFAULT 0.5 NOT NULL,
    transport_allowance numeric DEFAULT 26000 NOT NULL,
    smig_hourly numeric DEFAULT 370.526 NOT NULL,
    meal_allowance_factor numeric DEFAULT 3 NOT NULL,
    km_allowance numeric DEFAULT 50000 NOT NULL,
    ir_abatement_rate numeric DEFAULT 0.30 NOT NULL,
    ir_abatement_cap numeric DEFAULT 900000 NOT NULL,
    precarity_rate numeric DEFAULT 0.07 NOT NULL,
    seniority_min_years integer DEFAULT 2 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    allowance_absence_basis text DEFAULT 'gross'::text NOT NULL,
    ipm_on_contractors boolean DEFAULT false NOT NULL,
    severance_basis text DEFAULT 'base_salary'::text NOT NULL,
    deduction_global_cap numeric DEFAULT 0.6666666666666667 NOT NULL,
    severance_min_months smallint DEFAULT 12 NOT NULL,
    interim_ifc_rate numeric DEFAULT 0.07 NOT NULL,
    CONSTRAINT payroll_settings_deduction_global_cap_check CHECK (((deduction_global_cap > (0)::numeric) AND (deduction_global_cap <= (1)::numeric))),
    CONSTRAINT payroll_settings_interim_ifc_rate_check CHECK (((interim_ifc_rate >= (0)::numeric) AND (interim_ifc_rate <= (1)::numeric))),
    CONSTRAINT payroll_settings_severance_min_months_check CHECK ((severance_min_months >= 0))
);


--
-- Name: TABLE payroll_settings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.payroll_settings IS 'Taux, plafonds et constantes (Excel: PARAMETRES!A1:E12). Une ligne par date d''effet.';


--
-- Name: COLUMN payroll_settings.deduction_global_cap; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll_settings.deduction_global_cap IS 'Part maximale de l''assiette retenable, cessions volontaires comprises (CPC art. 381 : deux tiers).';


--
-- Name: COLUMN payroll_settings.severance_min_months; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll_settings.severance_min_months IS 'Ancienneté minimale (mois) pour l''indemnité de licenciement (C26-05).';


--
-- Name: COLUMN payroll_settings.interim_ifc_rate; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll_settings.interim_ifc_rate IS 'Indemnité de fin de mission d''intérim : 7 % PROVISOIRE (source secondaire, décret 2009-1412 non lu). Source : legal_sources.IFC_INTERIM.';


--
-- Name: payroll_settings_at(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_settings_at(p_date date) RETURNS public.payroll_settings
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select s.* from public.payroll_settings s
  where s.effective_from <= p_date
  order by s.effective_from desc
  limit 1;
$$;


--
-- Name: payroll_snapshots_verify(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_snapshots_verify() RETURNS TABLE(payroll_entry_id uuid, hash_algo text, ok boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select s.payroll_entry_id, s.hash_algo,
         s.payload_hash = case s.hash_algo when 'sha256' then encode(sha256(convert_to(s.payload::text, 'UTF8')), 'hex')
                                           else md5(s.payload::text) end
    from public.payroll_snapshots s
   where public.has_role(array['admin', 'rh', 'paie'])
$$;


--
-- Name: plafond_retenues(numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.plafond_retenues(p_assiette numeric, p_cap numeric DEFAULT (2.0 / 3.0)) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select greatest(0, p_assiette) * p_cap;
$$;


--
-- Name: FUNCTION plafond_retenues(p_assiette numeric, p_cap numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.plafond_retenues(p_assiette numeric, p_cap numeric) IS 'Plafond global des retenues (deux tiers de l''assiette par défaut).';


--
-- Name: preavis_mois(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.preavis_mois(p_employee_id uuid, p_on date DEFAULT CURRENT_DATE) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  with emp as (
    select e.agreement_code,
           case when lower(g.staff_status) like 'cadre%' then 'CADRE'
                when lower(g.staff_status) like '%ma_trise%' then 'MAITRISE'
                else 'OUVRIER_EMPLOYE' end as category
      from public.employees e
      left join public.employee_grades g on g.id = e.grade_id
     where e.id = p_employee_id
       and (select public.has_role(array['rh','paie']))
  )
  select n.notice_months
    from emp
    join public.notice_scales n on n.category = emp.category and n.valid_from <= p_on
                               and (n.agreement_code = emp.agreement_code or n.agreement_code is null)
   order by (n.agreement_code is not null) desc, n.valid_from desc
   limit 1;
$$;


--
-- Name: prevent_closed_payroll_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_closed_payroll_mutation() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare
  v_status text;
begin
  if tg_table_name = 'payroll_entries' then
    v_status := old.status;
    if v_status = 'Clôturée'
       and new.status = 'Réouverte'
       and nullif(trim(new.reopen_reason), '') is not null
       and public.has_role(array['admin']) then
      return new;
    end if;
  else
    select status into v_status
    from public.payroll_entries
    where id = old.payroll_entry_id;
  end if;
  if v_status = 'Clôturée' then
    raise exception 'La paie clôturée est immuable; une réouverture motivée est requise';
  end if;
  return coalesce(new, old);
end;
$$;


--
-- Name: prevent_closed_period_data_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_closed_period_data_mutation() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_closed boolean := false;
  v_slip uuid;
  v_emp  uuid;
  v_per  date;
begin
  if tg_table_name = 'salary_payments' then
    for v_slip in select x from unnest(case tg_op
        when 'INSERT' then array[new.slip_id]
        when 'DELETE' then array[old.slip_id]
        else array[old.slip_id, new.slip_id] end) as t(x) loop
      select exists (
        select 1 from public.salary_slips s join public.payroll_entries e on e.id = s.payroll_entry_id
         where s.id = v_slip and e.status = U&'Cl\00F4tur\00E9e') into v_closed;
      exit when v_closed;
    end loop;
  else
    for v_per in select x from unnest(case tg_op
        when 'INSERT' then array[new.period]
        when 'DELETE' then array[old.period]
        else array[old.period, new.period] end) as t(x) loop
      select exists (
        select 1 from public.payroll_entries e
         where e.status = U&'Cl\00F4tur\00E9e' and v_per between e.period_start and e.period_end) into v_closed;
      exit when v_closed;
    end loop;
  end if;
  if v_closed then
    raise exception 'La paie clôturée est immuable : % refusé ; une réouverture motivée est requise', tg_op;
  end if;
  return coalesce(new, old);
end;
$$;


--
-- Name: prevent_manager_assignment_overlap(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_manager_assignment_overlap() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if exists (
    select 1
    from public.employee_manager_assignments a
    where a.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
      and a.manager_employee_id = new.manager_employee_id
      and a.employee_id = new.employee_id
      and daterange(a.valid_from, coalesce(a.valid_to, 'infinity'::date), '[]')
          && daterange(new.valid_from, coalesce(new.valid_to, 'infinity'::date), '[]')
  ) then
    raise exception 'La délégation manager existe déjà sur cette période';
  end if;
  return new;
end;
$$;


--
-- Name: preview_employee_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.preview_employee_number() RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare n bigint; called boolean; v text;
begin
  select last_value, is_called into n, called from public.employee_number_seq;
  if called then n := n + 1; end if;
  loop
    v := 'S' || lpad(n::text, 4, '0');
    exit when not exists (select 1 from public.employees where upper(employee_number) = v);
    n := n + 1;
  end loop;
  return v;
end;
$$;


--
-- Name: quotite_cessible(numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.quotite_cessible(p_assiette numeric, p_kind text DEFAULT 'PRINCIPAL'::text) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select coalesce(sum(
    greatest(0, least(p_assiette, coalesce(g.upper_bound, p_assiette)) - g.lower_bound) * g.rate
  ), 0)
  from public.garnishment_scale g
  where g.kind = p_kind and p_assiette > 0;
$$;


--
-- Name: FUNCTION quotite_cessible(p_assiette numeric, p_kind text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.quotite_cessible(p_assiette numeric, p_kind text) IS 'Part saisissable de l''assiette mensuelle selon les tranches progressives (PRINCIPAL ou SUPPLEMENTAIRE).';


--
-- Name: reference_audit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reference_audit() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  o jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  n jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  r jsonb := coalesce(n, o);
begin
  -- une mise à jour sans changement réel (hors horodatage) n'est pas journalisée
  if tg_op = 'UPDATE' and (o - 'updated_at' - 'updated_by') = (n - 'updated_at' - 'updated_by') then
    return null;
  end if;
  insert into public.audit_log (table_name, record_id, record_key, action, old_data, new_data)
  values (tg_table_name,
          case when r ? 'id' then (r->>'id')::uuid end,
          coalesce(r->>'code', r->>'name'),
          case tg_op when 'INSERT' then 'création' when 'UPDATE' then
            case when (o->>'is_active') is distinct from (n->>'is_active')
                 then case when (n->>'is_active')::boolean then 'activation' else 'désactivation' end
                 else 'modification' end
            else 'suppression' end,
          o, n);
  return null;
end;
$$;


--
-- Name: reference_guard_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reference_guard_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_key text := coalesce(to_jsonb(old)->>'id', to_jsonb(old)->>'code'); u jsonb;
begin
  u := public.reference_usage(tg_table_name, v_key);
  if (u->>'total')::bigint > 0 then
    raise exception 'Valeur utilisée (% salarié(s), % bulletin(s) ou rattachement(s), % traitement(s)) : désactivez-la au lieu de la supprimer',
      u->>'employees', u->>'slips', u->>'entries';
  end if;
  return old;
end;
$$;


--
-- Name: reference_touch(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reference_touch() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  new.updated_at := now();
  new.updated_by := coalesce((select auth.uid()), new.updated_by);
  return new;
end;
$$;


--
-- Name: reference_usage(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reference_usage(p_table text, p_key text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_emp bigint := 0; v_slip bigint := 0; v_entry bigint := 0; v_name text;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants';
  end if;
  case p_table
    when 'designations' then
      select name into v_name from public.designations where id::text = p_key;
      select count(*) into v_emp from public.employees where designation_id::text = p_key;
      select count(*) into v_slip from public.salary_slips where designation = v_name;
    when 'collective_agreements' then
      select count(*) into v_emp from public.employees where agreement_code = p_key;
      select count(*) into v_slip from public.employee_grades where agreement_code = p_key; -- catégories rattachées
    when 'employee_grades' then
      select count(*) into v_emp from public.employees where grade_id::text = p_key;
    when 'contract_types' then
      select count(*) into v_emp from public.employees where employment_type = p_key;
      select count(*) into v_slip from public.salary_slips where employment_type = p_key;
    when 'payment_modes' then
      select count(*) into v_emp from public.employees where payment_mode = p_key;
      select count(*) into v_slip from public.salary_slips where payment_mode = p_key;
      select count(*) into v_entry from public.payroll_entries where payment_mode = p_key;
    else
      raise exception 'Référentiel inconnu : %', p_table;
  end case;
  return jsonb_build_object('employees', v_emp, 'slips', v_slip, 'entries', v_entry, 'total', v_emp + v_slip + v_entry);
end;
$$;


--
-- Name: reopen_payroll_entry(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reopen_payroll_entry(p_payroll_entry_id uuid, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare pe public.payroll_entries;
begin
  if not public.has_role(array['admin']) then
    raise exception 'Seul un administrateur peut rouvrir une paie validée';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'Un motif d''au moins 5 caractères est obligatoire';
  end if;
  select * into pe from public.payroll_entries where id = p_payroll_entry_id for update;
  if not found or pe.status <> 'Validée' then
    raise exception 'Seul un traitement « Validée » peut être rouvert';
  end if;
  if exists (select 1 from public.payroll_entries e where e.period_start > pe.period_start and e.status = 'Validée') then
    raise exception 'Rouvrez d''abord les mois suivants déjà validés';
  end if;
  update public.salary_slips set status = 'Brouillon' where payroll_entry_id = pe.id and status = 'Validé';
  update public.payroll_entries
     set status = 'Calculée', submitted_by = null, submitted_at = null, settings_snapshot = null
   where id = pe.id;
  insert into public.audit_log (table_name, record_id, record_key, action, reason, old_data, new_data)
  values ('payroll_entries', pe.id, to_char(pe.period_start, 'YYYY-MM'), 'réouverture', trim(p_reason),
          jsonb_build_object('status', 'Validée'), jsonb_build_object('status', 'Calculée'));
end;
$$;


--
-- Name: revert_payroll_entry(uuid, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.revert_payroll_entry(p_payroll_entry_id uuid, p_reason text, p_cancel_payments boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  pe public.payroll_entries;
  v_paid integer;
begin
  if not public.has_role(array['admin']) then
    raise exception 'Seul un administrateur peut remettre une paie à l''état « Calculée »';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'Un motif d''au moins 5 caractères est obligatoire';
  end if;
  select * into pe from public.payroll_entries where id = p_payroll_entry_id for update;
  if not found then raise exception 'Traitement de paie introuvable'; end if;
  if pe.status = 'Clôturée' then
    raise exception 'Une paie clôturée doit d''abord être rouverte (action « Rouvrir » avec motif) avant de pouvoir être remise à l''état « Calculée » ou supprimée';
  end if;
  if pe.status not in ('En revue', 'Approuvée', 'Validée', 'Payée') then
    raise exception 'La paie est déjà « % » : aucun retour arrière nécessaire', pe.status;
  end if;
  if exists (select 1 from public.payroll_entries e
              where e.period_start > pe.period_start and e.status in ('Validée', 'Payée', 'Clôturée')) then
    raise exception 'Remettez d''abord à l''état « Calculée » les mois suivants déjà validés';
  end if;

  select count(*) into v_paid
    from public.salary_payments sp join public.salary_slips s on s.id = sp.slip_id
   where s.payroll_entry_id = pe.id and sp.status = 'Payé';
  if v_paid > 0 and not p_cancel_payments then
    raise exception '% paiement(s) déjà enregistré(s) sur cette paie : confirmez leur annulation pour continuer', v_paid;
  end if;
  if v_paid > 0 then
    delete from public.salary_payments sp using public.salary_slips s
     where s.id = sp.slip_id and s.payroll_entry_id = pe.id;
  end if;

  perform set_config('soma.payroll_transition', 'on', true);
  update public.salary_slips set status = 'Brouillon' where payroll_entry_id = pe.id and status <> 'Annulé';
  update public.payroll_entries
     set status = 'Calculée', approved_by = null, approved_at = null, paid_by = null, paid_at = null,
         submitted_by = null, submitted_at = null, settings_snapshot = null
   where id = pe.id;
  update public.payroll_periods set status = 'Calculée' where id = pe.period_id;

  insert into public.audit_events(actor_id, action, resource_type, resource_id, payroll_entry_id, before_data, after_data, reason)
  values (auth.uid(), 'retour_calculee', 'payroll_entry', pe.id, pe.id,
          jsonb_build_object('status', pe.status),
          jsonb_build_object('status', 'Calculée', 'paiements_annules', v_paid), trim(p_reason));
end;
$$;


--
-- Name: review_employee_document(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.review_employee_document(p_document_id uuid, p_status text, p_reason text DEFAULT NULL::text) RETURNS public.employee_documents
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_document public.employee_documents;
begin
  if not (select public.has_role(array['admin', 'rh'])) then
    raise exception 'Droits administrateur ou RH requis';
  end if;
  if p_status not in ('valide', 'refuse') then
    raise exception 'Statut de validation invalide';
  end if;
  if p_status = 'refuse' and nullif(trim(p_reason), '') is null then
    raise exception 'Le motif de refus est obligatoire';
  end if;

  update public.employee_documents
  set status = p_status,
      rejection_reason = case when p_status = 'refuse' then trim(p_reason) else null end,
      validated_by = (select auth.uid()),
      validated_at = now()
  where id = p_document_id
  returning * into v_document;

  if not found then
    raise exception 'Document introuvable';
  end if;

  insert into public.document_reviews(document_id, status, reason, reviewed_by)
  values (p_document_id, p_status, case when p_status = 'refuse' then trim(p_reason) else null end, (select auth.uid()));
  return v_document;
end;
$$;


--
-- Name: revoke_delegation(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.revoke_delegation(p_delegation_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  update public.approval_delegations set active = false
   where id = p_delegation_id and active and (delegator_user = (select auth.uid()) or public.has_role(array['rh']));
  if not found then raise exception 'Délégation introuvable, déjà retirée ou non autorisée'; end if;
end;
$$;


--
-- Name: run_payroll_batch(uuid, text, uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.run_payroll_batch(p_payroll_entry_id uuid, p_employment_type text DEFAULT NULL::text, p_employee_ids uuid[] DEFAULT NULL::uuid[]) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare
  pe       public.payroll_entries;
  emp      record;
  v_done   int := 0;
  v_synced int := 0;
  v_errors jsonb := '[]'::jsonb;
begin
  if not public.has_role(array['paie','rh']) then
    raise exception 'Droits insuffisants : rôle « paie » ou « rh » requis';
  end if;
  select * into pe from public.payroll_entries where id = p_payroll_entry_id for update;
  if pe.id is null then raise exception 'Traitement de paie introuvable'; end if;
  if pe.status in ('Validée','Annulée') then
    raise exception 'Le traitement est % : recalcul impossible', pe.status;
  end if;

  v_synced := public.sync_attendance_to_payroll_inputs(pe.period_start);
  perform public.apply_period_adjustments(pe.id);

  for emp in
    select e.id, e.employee_number, e.last_name
    from public.employees e
    where e.company_id = pe.company_id
      and e.status in ('Active','Left')
      and e.date_of_joining <= pe.period_end
      and (e.relieving_date is null or e.relieving_date >= pe.period_start)
      and (p_employment_type is null or e.employment_type = p_employment_type)
      and (p_employee_ids is null or e.id = any(p_employee_ids))
    order by e.employee_number
  loop
    begin
      perform public.calculate_salary_slip(emp.id, pe.period_start, pe.period_end, pe.id);
      v_done := v_done + 1;
    exception when others then
      v_errors := v_errors || jsonb_build_object('employee_number', emp.employee_number,
                                                 'name', emp.last_name, 'error', sqlerrm);
    end;
  end loop;

  update public.payroll_entries set status = 'Calculée' where id = pe.id;
  return jsonb_build_object('calculated', v_done, 'errors', v_errors, 'attendance_synced', v_synced);
end;
$$;


--
-- Name: run_payroll_entry(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.run_payroll_entry(p_payroll_entry_id uuid) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$ select public.run_payroll_batch(p_payroll_entry_id, null, null) $$;


--
-- Name: salary_payments_audit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salary_payments_audit() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  insert into public.audit_log (table_name, record_id, record_key, action, old_data, new_data)
  values ('salary_payments', null, coalesce(new.slip_id, old.slip_id)::text,
          case tg_op when 'INSERT' then 'création' when 'UPDATE' then 'modification' else 'suppression' end,
          case when tg_op <> 'INSERT' then to_jsonb(old) - 'updated_at' end,
          case when tg_op <> 'DELETE' then to_jsonb(new) - 'updated_at' end);
  return null;
end;
$$;


--
-- Name: salary_payments_touch(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salary_payments_touch() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  new.updated_at := now();
  new.paid_by := coalesce((select auth.uid()), new.paid_by);
  return new;
end;
$$;


--
-- Name: salary_slip_explained(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salary_slip_explained(p_slip_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  with s as (select * from public.salary_slips where id = p_slip_id),
  prev as (
    select p.id from public.salary_slips p join s on p.employee_id = s.employee_id
     where p.status = 'Validé' and p.id <> s.id
       and p.period_start >= date_trunc('year', s.period_start)::date and p.period_start < s.period_start
  ),
  cum as (
    select x.component_code, sum(x.gain_amount) as gain, sum(x.deduction_amount) as deduction, sum(x.employer_amount) as employer
      from public.salary_slip_details x where x.salary_slip_id in (select id from prev) group by x.component_code
  )
  select jsonb_build_object(
    'gross_pay', s.gross_pay, 'net_pay', s.net_pay,
    'employer_charges', s.employer_charges, 'payroll_cost', s.payroll_cost,
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
        'code', d.component_code, 'label', d.label, 'section', d.section,
        'base', d.base, 'quantity', d.quantity, 'rate', d.employee_rate, 'employer_rate', d.employer_rate,
        'gain', d.gain_amount, 'deduction', d.deduction_amount, 'employer', d.employer_amount,
        'ytd_gain', d.gain_amount + coalesce(c.gain, 0),
        'ytd_deduction', d.deduction_amount + coalesce(c.deduction, 0),
        'ytd_employer', d.employer_amount + coalesce(c.employer, 0)
      ) order by d.sort_order)
      from public.salary_slip_details d left join cum c on c.component_code = d.component_code
      where d.salary_slip_id = s.id), '[]'::jsonb)
  )
  from s
$$;


--
-- Name: salary_slip_non_negative_net(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salary_slip_non_negative_net() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare
  v_who text;
begin
  if new.status <> 'Annulé' and new.net_pay < 0 then
    select e.employee_number || ' ' || e.last_name || ' ' || e.first_name into v_who from public.employees e where e.id = new.employee_id;
    raise exception 'Bulletin refusé : le net à payer de % serait négatif (% F). Vérifiez ses retenues (prêts, régularisations) et sa structure salariale.',
      coalesce(v_who, new.employee_id::text), round(new.net_pay);
  end if;
  return new;
end;
$$;


--
-- Name: set_loan_max_rate(numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_loan_max_rate(p_rate numeric) RETURNS numeric
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  new.updated_at := now();
  return new;
end;
$$;


--
-- Name: severance_coefficient(date, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.severance_coefficient(p_entry date, p_exit date, p_kind text) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
declare
  v_years numeric;
  y int; m int; d int;
begin
  if p_entry is null or p_exit is null then return 0; end if;
  v_years := (p_exit - p_entry)::numeric / 365;
  y := public.excel_datedif(p_entry, p_exit + 1, 'y');
  m := public.excel_datedif(p_entry, p_exit + 1, 'ym');
  d := public.excel_datedif(p_entry, p_exit + 1, 'md');
  if p_kind = 'LICENCIEMENT' then
    if v_years > 10 then
      return 0.25*5 + 0.30*5 + 0.40*(y-10) + 0.40*m/12.0 + 0.40*d/360.0;
    elsif v_years > 5 then
      return 0.25*5 + 0.30*(y-5) + 0.30*m/12.0 + 0.30*d/360.0;
    elsif v_years >= 0 then
      return 0.25*y + 0.25*m/12.0 + 0.25*d/360.0;
    end if;
  elsif p_kind = 'RETRAITE' then
    if v_years > 20 then
      return 0.25*5 + 0.30*5 + 0.45*10 + 0.50*(y-20) + 0.50*m/12.0 + 0.50*d/360.0;
    elsif v_years > 10 then
      return 0.25*5 + 0.30*5 + 0.45*(y-10) + 0.45*m/12.0 + 0.45*d/360.0;
    elsif v_years > 5 then
      return 0.25*5 + 0.30*(y-5) + 0.30*m/12.0 + 0.30*d/360.0;
    elsif v_years >= 0 then
      return 0.25*y + 0.25*m/12.0 + 0.25*d/360.0;
    end if;
  end if;
  return 0;
end;
$$;


--
-- Name: solde_tout_compte(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.solde_tout_compte(p_employee_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
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
    'special_indemnity', v_t->'special_indemnity',
    'funeral_indemnity', v_t->'funeral_indemnity',
    'precarity_allowance', v_t->'precarity_allowance',
    'leave_days_unused', v_jours,
    'leave_daily_rate', round(v_taux, 2),
    'leave_compensation', v_conges,
    'total_due', coalesce((v_t->>'net_pay')::numeric, 0) + v_conges,
    'slip', v_slip,
    'assumptions', jsonb_build_array(
      'Bulletin du mois de sortie calculé par le moteur de paie (compute_salary_slip), indemnités de sortie comprises.',
      'Indemnités de sortie lues dans exit_reasons : licenciement (si éligible et ancienneté ≥ minimum), indemnité spéciale d''un mois, frais funéraires en cas de décès. Base d''un mois = salaire de base + sursalaire + prime d''ancienneté : à confirmer par le juriste.',
      case when v_deja_paye then 'Congés payés réglés chaque mois sur le bulletin : aucune indemnité compensatrice due.'
           else 'Indemnité compensatrice de congés = jours de congé annuel non pris × salaire brut du mois / 30 (formule à valider par la RH).' end,
      'Solde de congé annuel de l''année en cours uniquement ; les reliquats des années précédentes ne sont pas repris.'),
    'generated_at', now());
end;
$$;


--
-- Name: solve_sursalaire_for_net(uuid, date, date, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.solve_sursalaire_for_net(p_employee_id uuid, p_period_start date, p_period_end date, p_target_net numeric) RETURNS numeric
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare
  lo numeric := 0;
  hi numeric;
  mid numeric;
  v_net numeric;
  i int;
begin
  if p_target_net is null or p_target_net <= 0 then
    raise exception 'Net cible invalide';
  end if;
  v_net := (public.compute_salary_slip(p_employee_id, p_period_start, p_period_end, 0)->'totals'->>'net_pay')::numeric;
  if v_net >= p_target_net then
    return 0;   -- le net sans sursalaire atteint déjà la cible
  end if;
  hi := p_target_net * 4 + 1000000;
  for i in 1..200 loop
    mid := (lo + hi) / 2;
    v_net := (public.compute_salary_slip(p_employee_id, p_period_start, p_period_end, mid)->'totals'->>'net_pay')::numeric;
    if abs(v_net - p_target_net) < 0.000001 then
      return mid;
    elsif v_net < p_target_net then
      lo := mid;
    else
      hi := mid;
    end if;
  end loop;
  return mid;
end;
$$;


--
-- Name: sortie_salarie(uuid, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sortie_salarie(p_employee_id uuid, p_exit_date date, p_exit_reason text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  e public.employees;
  v_managers integer := 0;
  v_liens integer := 0;
  v_acces integer := 0;
  v_effective boolean := p_exit_date <= current_date;
begin
  if not public.has_role(array['rh']) then raise exception 'Réservé au service RH'; end if;
  if p_exit_date is null then raise exception 'La date de sortie est obligatoire'; end if;
  if p_exit_reason is null or not exists (select 1 from public.exit_reasons where code = p_exit_reason) then
    raise exception 'Motif de sortie invalide : voir la liste des motifs (table exit_reasons)';
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


--
-- Name: submit_payroll_entry(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_payroll_entry(p_payroll_entry_id uuid, p_reason text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.has_role(array['paie']) then
    raise exception 'Droits insuffisants : rôle « paie » requis pour valider la paie';
  end if;
  if not exists (select 1 from public.payroll_entries where id = p_payroll_entry_id and status = 'Calculée') then
    raise exception 'Seul un traitement « Calculée » peut être validé';
  end if;
  perform public.transition_payroll_entry(p_payroll_entry_id, 'Validée', p_reason);
end;
$$;


--
-- Name: sync_attendance_to_payroll_inputs(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_attendance_to_payroll_inputs(p_period date) RETURNS integer
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare
  v_start date := date_trunc('month', p_period)::date;
  v_end   date := (date_trunc('month', p_period) + interval '1 month - 1 day')::date;
  v_count int;
begin
  if not public.has_role(array['paie','rh']) then
    raise exception 'Droits insuffisants : rôle « paie » requis';
  end if;
  insert into public.payroll_inputs as pi
    (employee_id, period, absence_hours, sick_leave_hours, overtime_15, overtime_40, overtime_60, overtime_100)
  select a.employee_id, v_start,
         sum(case when a.status = 'Congé' then 0 else a.absence_hours end),
         sum(a.sick_hours),
         sum(a.overtime_15), sum(a.overtime_40), sum(a.overtime_60), sum(a.overtime_100)
  from public.attendance a
  where a.attendance_date between v_start and v_end
  group by a.employee_id
  on conflict (employee_id, period) do update
    set absence_hours    = excluded.absence_hours,
        sick_leave_hours = excluded.sick_leave_hours,
        overtime_15      = excluded.overtime_15,
        overtime_40      = excluded.overtime_40,
        overtime_60      = excluded.overtime_60,
        overtime_100     = excluded.overtime_100
    where not pi.attendance_override;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;


--
-- Name: tax_slab_at(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tax_slab_at(p_date date) RETURNS uuid
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select t.id from public.tax_slabs t
  where t.effective_from <= p_date
  order by t.effective_from desc
  limit 1;
$$;


--
-- Name: transition_payroll_entry(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.transition_payroll_entry(p_payroll_entry_id uuid, p_target_status text, p_reason text DEFAULT NULL::text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_entry public.payroll_entries;
  v_allowed boolean := false;
  v_actor uuid := auth.uid();
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
$$;


--
-- Name: try_transition_payroll_entry(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.try_transition_payroll_entry(p_payroll_entry_id uuid, p_target_status text, p_reason text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_from text;
  v_code text;
  v_msg text;
begin
  select status into v_from from public.payroll_entries where id = p_payroll_entry_id;
  begin
    return jsonb_build_object('ok', true, 'status', public.transition_payroll_entry(p_payroll_entry_id, p_target_status, p_reason));
  exception when others then
    get stacked diagnostics v_msg = message_text;
    v_code := sqlstate;
  end;
  -- le bloc interne est annulé : l'écriture ci-dessous subsiste
  insert into public.audit_events(actor_id, action, resource_type, resource_id, payroll_entry_id,
                                  before_data, after_data, reason, result)
  values (auth.uid(), 'transition_refusee', 'payroll_entry', p_payroll_entry_id,
          case when v_from is null then null else p_payroll_entry_id end,
          jsonb_build_object('status', v_from),
          jsonb_build_object('cible', p_target_status, 'message', v_msg), p_reason, 'denied');
  return jsonb_build_object('ok', false, 'message', v_msg, 'code', v_code);
end;
$$;


--
-- Name: user_emails(uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.user_emails(p_ids uuid[]) RETURNS TABLE(id uuid, email text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select u.id, u.email::text from auth.users u
  where u.id = any(p_ids) and public.has_role(array['rh', 'paie']);
$$;


--
-- Name: user_manages_employee(uuid, uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.user_manages_employee(p_user uuid, p_employee uuid, p_on date) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1 from public.employee_manager_assignments a join public.employees m on m.id = a.manager_employee_id
     where m.user_id = p_user and a.employee_id = p_employee
       and p_on >= a.valid_from and (a.valid_to is null or p_on <= a.valid_to))
  or exists (
    select 1 from public.approval_delegations d
      join public.employees m on m.user_id = d.delegator_user
      join public.employee_manager_assignments a on a.manager_employee_id = m.id
     where d.delegate_user = p_user and d.active and current_date between d.valid_from and d.valid_to
       and a.employee_id = p_employee and p_on >= a.valid_from and (a.valid_to is null or p_on <= a.valid_to))
$$;


--
-- Name: validate_employee_document_family_slot(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_employee_document_family_slot() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare
  v_spouses smallint;
  v_children smallint;
begin
  select spouses_count, children_count into v_spouses, v_children
  from public.employees where id = new.employee_id;
  if new.requirement_code = 'situation_matrimoniale' and new.document_slot > greatest(v_spouses, 1) then
    raise exception 'Le numéro de l''acte de mariage dépasse le nombre de conjoints déclaré';
  end if;
  if new.requirement_code = 'actes_enfants' and new.document_slot > v_children then
    raise exception 'Le numéro de l''acte de naissance dépasse le nombre d''enfants déclaré';
  end if;
  return new;
end;
$$;


--
-- Name: validate_journal_balance(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_journal_balance(p_payroll_entry_id uuid) RETURNS boolean
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare
  v_total_debit numeric := 0;
  v_total_credit numeric := 0;
begin
  -- Vérifier l'équilibre du journal comptable
  SELECT sum(debit), sum(credit) INTO v_total_debit, v_total_credit
  FROM public.v_accounting_journal
  WHERE payroll_entry_id = p_payroll_entry_id;

  IF v_total_debit IS NULL THEN v_total_debit := 0; END IF;
  IF v_total_credit IS NULL THEN v_total_credit := 0; END IF;

  -- Retourner vrai si équilibré, faux sinon
  IF v_total_debit = v_total_credit THEN
    RETURN true;
  ELSE
    RETURN false;
  END IF;
end;
$$;


--
-- Name: additional_salaries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.additional_salaries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    period date NOT NULL,
    component_code text NOT NULL,
    amount numeric NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    kind text DEFAULT 'ponctuel'::text NOT NULL,
    source_id uuid,
    CONSTRAINT additional_salaries_amount_check CHECK ((amount >= (0)::numeric)),
    CONSTRAINT additional_salaries_kind_check CHECK ((kind = ANY (ARRAY['ponctuel'::text, 'recurrent'::text, 'pret'::text, 'regularisation'::text]))),
    CONSTRAINT additional_salaries_period_check CHECK ((EXTRACT(day FROM period) = (1)::numeric))
);


--
-- Name: TABLE additional_salaries; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.additional_salaries IS 'Primes et retenues ponctuelles du mois (Frappe: Additional Salary). Montants toujours positifs.';


--
-- Name: app_parameters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_parameters (
    code text NOT NULL,
    label text NOT NULL,
    value numeric NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: approval_delegations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_delegations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    delegator_user uuid NOT NULL,
    delegate_user uuid NOT NULL,
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    reason text,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT approval_delegations_check CHECK ((valid_to >= valid_from)),
    CONSTRAINT approval_delegations_check1 CHECK ((delegator_user <> delegate_user))
);


--
-- Name: attendance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    attendance_date date NOT NULL,
    status text NOT NULL,
    working_hours numeric,
    absence_hours numeric DEFAULT 0 NOT NULL,
    overtime_15 numeric DEFAULT 0 NOT NULL,
    overtime_40 numeric DEFAULT 0 NOT NULL,
    overtime_60 numeric DEFAULT 0 NOT NULL,
    overtime_100 numeric DEFAULT 0 NOT NULL,
    leave_application_id uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    sick_hours numeric DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid DEFAULT auth.uid(),
    CONSTRAINT attendance_absence_hours_check CHECK ((absence_hours >= (0)::numeric)),
    CONSTRAINT attendance_day_hours_check CHECK ((((COALESCE(working_hours, (0)::numeric) + absence_hours) + sick_hours) <= (24)::numeric)),
    CONSTRAINT attendance_overtime_100_check CHECK ((overtime_100 >= (0)::numeric)),
    CONSTRAINT attendance_overtime_15_check CHECK ((overtime_15 >= (0)::numeric)),
    CONSTRAINT attendance_overtime_40_check CHECK ((overtime_40 >= (0)::numeric)),
    CONSTRAINT attendance_overtime_60_check CHECK ((overtime_60 >= (0)::numeric)),
    CONSTRAINT attendance_sick_hours_check CHECK ((sick_hours >= (0)::numeric)),
    CONSTRAINT attendance_status_check CHECK ((status = ANY (ARRAY['Présent'::text, 'Absent'::text, 'Demi-journée'::text, 'Congé'::text, 'Maladie'::text]))),
    CONSTRAINT attendance_working_hours_check CHECK ((working_hours >= (0)::numeric))
);


--
-- Name: TABLE attendance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.attendance IS 'Pointage journalier (Frappe: Attendance) — agrégé en heures d''absence / HS pour la paie.';


--
-- Name: COLUMN attendance.sick_hours; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.sick_hours IS 'Heures d''arrêt maladie de la journée (indemnité maladie de la paie).';


--
-- Name: audit_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    actor_id uuid,
    action text NOT NULL,
    resource_type text NOT NULL,
    resource_id uuid,
    payroll_entry_id uuid,
    before_data jsonb,
    after_data jsonb,
    reason text,
    result text DEFAULT 'success'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT audit_events_result_check CHECK ((result = ANY (ARRAY['success'::text, 'denied'::text, 'error'::text])))
);


--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: candidatures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.candidatures (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    job_postulation_id uuid NOT NULL,
    status text DEFAULT 'en_attente'::text NOT NULL,
    motivation text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT candidatures_status_check CHECK ((status = ANY (ARRAY['en_attente'::text, 'approuvée'::text, 'refusée'::text])))
);


--
-- Name: collective_agreements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.collective_agreements (
    code text NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid DEFAULT auth.uid()
);


--
-- Name: TABLE collective_agreements; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.collective_agreements IS 'Conventions collectives (Excel: PARAMETRES!CONVENTIONS_COLLECTIVES).';


--
-- Name: companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.companies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    legal_form text,
    share_capital numeric,
    address text,
    phone text,
    email text,
    ninea text,
    rccm text,
    logo_url text,
    currency text DEFAULT 'XOF'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    ipres_number text,
    css_number text,
    collective_agreement_code text
);


--
-- Name: TABLE companies; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.companies IS 'Sociétés employeuses (Frappe: Company).';


--
-- Name: compliance_findings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.compliance_findings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    rule_id text NOT NULL,
    severity text NOT NULL,
    entity text NOT NULL,
    entity_id uuid,
    message text NOT NULL,
    detected_on date DEFAULT CURRENT_DATE NOT NULL,
    resolved_on date,
    waived_by uuid,
    waiver_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT compliance_findings_check CHECK (((waived_by IS NULL) OR (waiver_reason IS NOT NULL))),
    CONSTRAINT compliance_findings_severity_check CHECK ((severity = ANY (ARRAY['A'::text, 'B'::text])))
);


--
-- Name: TABLE compliance_findings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.compliance_findings IS 'Résultats des garde-fous. A = alerte, B = bloquant ; une dérogation exige un motif écrit.';


--
-- Name: contract_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_types (
    code text NOT NULL,
    label text NOT NULL,
    nature text DEFAULT 'TRAVAIL'::text NOT NULL,
    precarity_eligible boolean DEFAULT false NOT NULL,
    severance_eligible boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 100 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid DEFAULT auth.uid(),
    CONSTRAINT contract_types_code_check CHECK ((code ~ '^[A-Z0-9_ -]{2,30}$'::text)),
    CONSTRAINT contract_types_label_check CHECK ((length(TRIM(BOTH FROM label)) > 0)),
    CONSTRAINT contract_types_nature_check CHECK ((nature = ANY (ARRAY['TRAVAIL'::text, 'STAGE'::text, 'APPRENTISSAGE'::text, 'PRESTATION'::text, 'AUTRE'::text])))
);


--
-- Name: TABLE contract_types; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.contract_types IS 'Référentiel des types de contrat. nature : TRAVAIL (IR, TRIMF, IPRES, CFCE, AF), PRESTATION (BRS), STAGE, APPRENTISSAGE, AUTRE.';


--
-- Name: contribution_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contribution_payments (
    month date NOT NULL,
    paid_on date NOT NULL,
    amount numeric NOT NULL,
    notes text,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT contribution_payments_amount_check CHECK ((amount >= (0)::numeric)),
    CONSTRAINT contribution_payments_month_check CHECK ((month = (date_trunc('month'::text, (month)::timestamp with time zone))::date))
);


--
-- Name: delegate_seats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delegate_seats (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workers_min integer NOT NULL,
    workers_max integer,
    seats smallint NOT NULL,
    source_code text,
    CONSTRAINT delegate_seats_check CHECK (((workers_max IS NULL) OR (workers_max >= workers_min))),
    CONSTRAINT delegate_seats_seats_check CHECK ((seats > 0)),
    CONSTRAINT delegate_seats_workers_min_check CHECK ((workers_min > 0))
);


--
-- Name: TABLE delegate_seats; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.delegate_seats IS 'Nombre de délégués titulaires selon l''effectif ; au-delà de 1 000, +1 par tranche de 500 supplémentaires (à gérer par le code).';


--
-- Name: departments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name text NOT NULL,
    parent_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    kind text DEFAULT 'direction'::text NOT NULL,
    head_employee_id uuid,
    note text,
    CONSTRAINT departments_kind_check CHECK ((kind = ANY (ARRAY['direction'::text, 'secteur'::text, 'section'::text, 'service'::text])))
);


--
-- Name: designations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.designations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid DEFAULT auth.uid()
);


--
-- Name: TABLE designations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.designations IS 'Emplois / fonctions (Frappe: Designation ; Excel: colonne fonction).';


--
-- Name: document_requirements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_requirements (
    code text NOT NULL,
    section_code text NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    icon text,
    required boolean DEFAULT true NOT NULL,
    conditional_rule text,
    allowed_mime_types text[] DEFAULT ARRAY['application/pdf'::text, 'image/jpeg'::text, 'image/png'::text] NOT NULL,
    max_size_bytes bigint DEFAULT 10485760 NOT NULL,
    validity_days integer,
    manager_shareable boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT document_requirements_max_size_bytes_check CHECK ((max_size_bytes > 0)),
    CONSTRAINT document_requirements_section_code_check CHECK ((section_code = ANY (ARRAY['identite'::text, 'qualification'::text, 'famille_social'::text, 'aptitude_medicale'::text, 'cas_specifiques'::text]))),
    CONSTRAINT document_requirements_validity_days_check CHECK (((validity_days IS NULL) OR (validity_days > 0)))
);


--
-- Name: document_reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    document_id uuid NOT NULL,
    status text NOT NULL,
    reason text,
    reviewed_by uuid DEFAULT auth.uid() NOT NULL,
    reviewed_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT document_reviews_check CHECK (((status <> 'refuse'::text) OR (NULLIF(TRIM(BOTH FROM reason), ''::text) IS NOT NULL))),
    CONSTRAINT document_reviews_status_check CHECK ((status = ANY (ARRAY['en_attente'::text, 'valide'::text, 'refuse'::text])))
);


--
-- Name: document_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_versions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    document_id uuid NOT NULL,
    version_number integer NOT NULL,
    storage_path text NOT NULL,
    file_name text NOT NULL,
    mime_type text NOT NULL,
    size_bytes bigint NOT NULL,
    checksum text,
    uploaded_by uuid DEFAULT auth.uid() NOT NULL,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT document_versions_size_bytes_check CHECK ((size_bytes >= 0)),
    CONSTRAINT document_versions_version_number_check CHECK ((version_number > 0))
);


--
-- Name: email_outbox; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_outbox (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    to_email text NOT NULL,
    subject text NOT NULL,
    body text NOT NULL,
    dedup_key text NOT NULL,
    status text DEFAULT 'En attente'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    sent_at timestamp with time zone,
    CONSTRAINT email_outbox_status_check CHECK ((status = ANY (ARRAY['En attente'::text, 'Envoyé'::text, 'Erreur'::text])))
);


--
-- Name: employee_grades; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_grades (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    agreement_code text NOT NULL,
    code text NOT NULL,
    hourly_rate numeric NOT NULL,
    base_salary numeric NOT NULL,
    staff_status text NOT NULL,
    grade_class text,
    effective_from date DEFAULT '2023-01-01'::date NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid DEFAULT auth.uid()
);


--
-- Name: TABLE employee_grades; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.employee_grades IS 'Grille des salaires minima par convention et catégorie (Frappe: Employee Grade ; Excel: table CC).';


--
-- Name: employee_module_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_module_data (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    module_id text NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    valid_from date,
    valid_to date,
    CONSTRAINT employee_module_data_check CHECK (((valid_to IS NULL) OR (valid_from IS NULL) OR (valid_to > valid_from)))
);


--
-- Name: employee_number_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.employee_number_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_representatives; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_representatives (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    mandate text NOT NULL,
    start_date date NOT NULL,
    end_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT employee_representatives_check CHECK (((end_date IS NULL) OR (end_date >= start_date))),
    CONSTRAINT employee_representatives_mandate_check CHECK ((mandate = ANY (ARRAY['DELEGUE_TITULAIRE'::text, 'DELEGUE_SUPPLEANT'::text, 'MEMBRE_CHST'::text])))
);


--
-- Name: TABLE employee_representatives; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.employee_representatives IS 'Salariés protégés : leur sortie exige une autorisation (ticket C26-15). Mandat de 3 ans.';


--
-- Name: employee_request_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_request_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    request_id uuid NOT NULL,
    status text NOT NULL,
    note text,
    actor_id uuid DEFAULT auth.uid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT employee_request_history_status_check CHECK ((status = ANY (ARRAY['Ouverte'::text, 'Approuvée'::text, 'Rejetée'::text, 'Annulée'::text])))
);


--
-- Name: employees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employees (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_number text NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    gender text,
    date_of_birth date,
    place_of_birth text,
    nationality text,
    father_name text,
    mother_name text,
    id_document_number text,
    id_issue_date date,
    id_expiry_date date,
    ninea text,
    ipres_number text,
    css_number text,
    address text,
    phone_personal text,
    phone_work text,
    email_personal text,
    email_work text,
    emergency_contact_name text,
    emergency_contact_phone text,
    marital_status text,
    spouses_count smallint DEFAULT 0 NOT NULL,
    children_count smallint DEFAULT 0 NOT NULL,
    trimf_parts numeric(4,1) DEFAULT 1 NOT NULL,
    ir_parts numeric(4,1) DEFAULT 1 NOT NULL,
    designation_id uuid,
    department_id uuid,
    agreement_code text,
    grade_id uuid,
    employment_type text NOT NULL,
    date_of_joining date NOT NULL,
    contract_start date,
    contract_end date,
    relieving_date date,
    exit_reason text,
    leave_return_date date,
    bank_name text,
    bank_account text,
    payment_mode text DEFAULT 'espèces'::text NOT NULL,
    status text DEFAULT 'Active'::text NOT NULL,
    user_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    hire_declaration_ref text,
    hire_declared_on date,
    affiliation_date date,
    CONSTRAINT employees_check CHECK (((relieving_date IS NULL) OR (relieving_date >= date_of_joining))),
    CONSTRAINT employees_check1 CHECK (((relieving_date IS NULL) OR (exit_reason IS NOT NULL))),
    CONSTRAINT employees_children_count_check CHECK ((children_count >= 0)),
    CONSTRAINT employees_gender_check CHECK ((gender = ANY (ARRAY['M'::text, 'F'::text]))),
    CONSTRAINT employees_ir_parts_check CHECK (((ir_parts >= (1)::numeric) AND (ir_parts <= (5)::numeric))),
    CONSTRAINT employees_marital_status_check CHECK ((marital_status = ANY (ARRAY['Marié(e)'::text, 'Célibataire'::text, 'Divorcé(e)'::text, 'Veuf(ve)'::text]))),
    CONSTRAINT employees_spouses_count_check CHECK ((spouses_count >= 0)),
    CONSTRAINT employees_status_check CHECK ((status = ANY (ARRAY['Active'::text, 'Inactive'::text, 'Suspended'::text, 'Left'::text]))),
    CONSTRAINT employees_trimf_parts_check CHECK ((trimf_parts > (0)::numeric))
);


--
-- Name: TABLE employees; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.employees IS 'Fiche de personnel (Frappe: Employee ; Excel: FICHE DE PERSONNEL).';


--
-- Name: COLUMN employees.hire_declaration_ref; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employees.hire_declaration_ref IS 'Référence de la déclaration d''embauche à l''inspection du travail (Code du Travail art. 363).';


--
-- Name: COLUMN employees.affiliation_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employees.affiliation_date IS 'Date d''affiliation à la sécurité sociale ; au plus tard 2 mois après l''embauche (CSS art. 89-90).';


--
-- Name: evaluations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evaluations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    evaluator text,
    period text,
    global_note numeric,
    commentaires text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT evaluations_global_note_check CHECK (((global_note >= (0)::numeric) AND (global_note <= (20)::numeric)))
);


--
-- Name: exit_reasons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exit_reasons (
    code text NOT NULL,
    label text NOT NULL,
    severance_eligible boolean DEFAULT false NOT NULL,
    retirement_indemnity boolean DEFAULT false NOT NULL,
    special_indemnity_months numeric DEFAULT 0 NOT NULL,
    is_legacy boolean DEFAULT false NOT NULL,
    source_code text,
    notes text,
    sort_order smallint DEFAULT 0 NOT NULL,
    funeral_indemnity_months numeric DEFAULT 0 NOT NULL,
    CONSTRAINT exit_reasons_funeral_indemnity_months_check CHECK ((funeral_indemnity_months >= (0)::numeric)),
    CONSTRAINT exit_reasons_special_indemnity_months_check CHECK ((special_indemnity_months >= (0)::numeric))
);


--
-- Name: TABLE exit_reasons; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.exit_reasons IS 'Motifs de sortie. severance_eligible et special_indemnity_months ne sont renseignés que là où le Code 2026 le dit ; les autres lignes sont à confirmer (notes).';


--
-- Name: COLUMN exit_reasons.funeral_indemnity_months; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exit_reasons.funeral_indemnity_months IS 'Participation aux frais funéraires, en mois de salaire (CCNI art. 83 : au moins 1 mois en cas de décès). À confirmer.';


--
-- Name: garnishment_scale; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.garnishment_scale (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kind text NOT NULL,
    lower_bound numeric NOT NULL,
    upper_bound numeric,
    rate numeric NOT NULL,
    source_code text,
    CONSTRAINT garnishment_scale_check CHECK (((upper_bound IS NULL) OR (upper_bound > lower_bound))),
    CONSTRAINT garnishment_scale_kind_check CHECK ((kind = ANY (ARRAY['PRINCIPAL'::text, 'SUPPLEMENTAIRE'::text]))),
    CONSTRAINT garnishment_scale_lower_bound_check CHECK ((lower_bound >= (0)::numeric)),
    CONSTRAINT garnishment_scale_rate_check CHECK (((rate > (0)::numeric) AND (rate <= (1)::numeric)))
);


--
-- Name: TABLE garnishment_scale; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.garnishment_scale IS 'Tranches mensuelles de la part saisissable ; le taux s''applique à la part d''assiette comprise dans chaque tranche.';


--
-- Name: ir_family_reductions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ir_family_reductions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slab_id uuid NOT NULL,
    parts numeric(4,1) NOT NULL,
    rate numeric NOT NULL,
    min_amount numeric NOT NULL,
    max_amount numeric NOT NULL
);


--
-- Name: TABLE ir_family_reductions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ir_family_reductions IS 'Réductions d''impôt pour charges de famille selon le nombre de parts (quotient familial).';


--
-- Name: job_postulations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_postulations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    job_title text NOT NULL,
    department text,
    status text DEFAULT 'en_attente'::text NOT NULL,
    source text,
    source_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT job_postulations_status_check CHECK ((status = ANY (ARRAY['en_attente'::text, 'approuvée'::text, 'refusée'::text])))
);


--
-- Name: leave_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_allocations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    leave_type text NOT NULL,
    from_date date NOT NULL,
    to_date date NOT NULL,
    days numeric NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT leave_allocations_check CHECK ((to_date >= from_date)),
    CONSTRAINT leave_allocations_days_check CHECK ((days >= (0)::numeric))
);


--
-- Name: leave_approval_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_approval_steps (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    leave_id uuid NOT NULL,
    step smallint NOT NULL,
    level text NOT NULL,
    status text DEFAULT 'En attente'::text NOT NULL,
    due_at timestamp with time zone,
    decided_by uuid,
    decided_at timestamp with time zone,
    note text,
    via_delegation boolean DEFAULT false NOT NULL,
    CONSTRAINT leave_approval_steps_level_check CHECK ((level = ANY (ARRAY['manager'::text, 'rh'::text]))),
    CONSTRAINT leave_approval_steps_status_check CHECK ((status = ANY (ARRAY['En attente'::text, 'Approuvée'::text, 'Rejetée'::text, 'Ignorée'::text]))),
    CONSTRAINT leave_approval_steps_step_check CHECK ((step = ANY (ARRAY[1, 2])))
);


--
-- Name: leave_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_types (
    code text NOT NULL,
    name text NOT NULL,
    is_paid boolean DEFAULT true NOT NULL,
    affects_payroll text DEFAULT 'none'::text NOT NULL,
    days_per_month numeric DEFAULT 0 NOT NULL,
    max_days_per_year numeric,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    extension_days numeric DEFAULT 0 NOT NULL,
    CONSTRAINT leave_types_affects_payroll_check CHECK ((affects_payroll = ANY (ARRAY['none'::text, 'absence'::text, 'sick_leave'::text]))),
    CONSTRAINT leave_types_extension_days_check CHECK ((extension_days >= (0)::numeric))
);


--
-- Name: COLUMN leave_types.extension_days; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_types.extension_days IS 'Jours supplémentaires possibles au-delà du maximum (maternité : 21 jours, soit 147 au total ; art. 277, sur justificatif).';


--
-- Name: legal_sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.legal_sources (
    code text NOT NULL,
    label text NOT NULL,
    source_type text NOT NULL,
    document text,
    article text,
    valid_from date,
    status text DEFAULT 'a_confirmer'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT legal_sources_source_type_check CHECK ((source_type = ANY (ARRAY['CODE'::text, 'HERITEE'::text, 'A_FOURNIR'::text]))),
    CONSTRAINT legal_sources_status_check CHECK ((status = ANY (ARRAY['a_confirmer'::text, 'confirme'::text])))
);


--
-- Name: TABLE legal_sources; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.legal_sources IS 'Origine de chaque valeur légale : Code 2026, texte hérité ou à fournir. « confirme » seulement après revue juridique.';


--
-- Name: loan_balances; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.loan_balances AS
SELECT
    NULL::uuid AS loan_id,
    NULL::uuid AS employee_id,
    NULL::text AS label,
    NULL::numeric AS principal,
    NULL::text AS status,
    NULL::numeric AS retenu,
    NULL::numeric AS restant,
    NULL::date AS prochaine_echeance;


--
-- Name: loan_installments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loan_installments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    loan_id uuid NOT NULL,
    due_period date NOT NULL,
    amount numeric NOT NULL,
    status text DEFAULT 'Prévue'::text NOT NULL,
    applied_period date,
    CONSTRAINT loan_installments_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT loan_installments_status_check CHECK ((status = ANY (ARRAY['Prévue'::text, 'Retenue'::text, 'Annulée'::text])))
);


--
-- Name: loans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    label text NOT NULL,
    principal numeric NOT NULL,
    installments integer NOT NULL,
    first_period date NOT NULL,
    status text DEFAULT 'Actif'::text NOT NULL,
    request_id uuid,
    cancel_reason text,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT loans_first_period_check CHECK ((first_period = (date_trunc('month'::text, (first_period)::timestamp with time zone))::date)),
    CONSTRAINT loans_installments_check CHECK (((installments >= 1) AND (installments <= 60))),
    CONSTRAINT loans_label_check CHECK ((length(TRIM(BOTH FROM label)) > 0)),
    CONSTRAINT loans_principal_check CHECK ((principal > (0)::numeric)),
    CONSTRAINT loans_status_check CHECK ((status = ANY (ARRAY['Actif'::text, 'Soldé'::text, 'Annulé'::text])))
);


--
-- Name: module_activation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_activation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    module_id text NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    manifest_version text,
    manifest_hash text,
    enabled_at timestamp with time zone,
    enabled_by uuid,
    disabled_at timestamp with time zone
);


--
-- Name: module_manifest; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_manifest (
    module_id text NOT NULL,
    name text NOT NULL,
    version text NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    hash text NOT NULL,
    manifest jsonb NOT NULL,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT module_manifest_module_id_check CHECK ((module_id ~ '^[a-z][a-z0-9-]*$'::text))
);


--
-- Name: module_parameter_value; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_parameter_value (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    module_id text NOT NULL,
    param_key text NOT NULL,
    value jsonb NOT NULL,
    legal_status text NOT NULL,
    source text,
    valid_from date,
    valid_to date,
    entered_by uuid DEFAULT auth.uid(),
    entered_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT module_parameter_value_check CHECK (((valid_to IS NULL) OR (valid_from IS NULL) OR (valid_to > valid_from))),
    CONSTRAINT module_parameter_value_legal_status_check CHECK ((legal_status = ANY (ARRAY['verified'::text, 'secondary'::text, 'to_provide'::text])))
);


--
-- Name: notice_scales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notice_scales (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    agreement_code text,
    category text NOT NULL,
    notice_months numeric NOT NULL,
    free_days_week smallint DEFAULT 2 NOT NULL,
    source_code text,
    valid_from date DEFAULT '2026-10-01'::date NOT NULL,
    CONSTRAINT notice_scales_category_check CHECK ((category = ANY (ARRAY['OUVRIER_EMPLOYE'::text, 'MAITRISE'::text, 'CADRE'::text]))),
    CONSTRAINT notice_scales_free_days_week_check CHECK ((free_days_week >= 0)),
    CONSTRAINT notice_scales_notice_months_check CHECK ((notice_months >= (0)::numeric))
);


--
-- Name: notifications_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    type text NOT NULL,
    title text NOT NULL,
    message text NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 3 NOT NULL,
    last_error text,
    scheduled_at timestamp with time zone,
    sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone,
    CONSTRAINT notifications_log_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text]))),
    CONSTRAINT notifications_log_type_check CHECK ((type = ANY (ARRAY['e-mail'::text, 'sms'::text, 'whatsapp'::text])))
);


--
-- Name: TABLE notifications_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.notifications_log IS 'Journal traçable de toutes les notifications envoyées aux salariés. Traite e-mail, SMS et WhatsApp avec reprise sur échec.';


--
-- Name: org_positions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.org_positions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    unit_id uuid NOT NULL,
    designation_id uuid NOT NULL,
    headcount integer NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT auth.uid(),
    CONSTRAINT org_positions_headcount_check CHECK (((headcount >= 1) AND (headcount <= 500)))
);


--
-- Name: org_relations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.org_relations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    related_employee_id uuid NOT NULL,
    relation_type text NOT NULL,
    start_date date NOT NULL,
    end_date date,
    allocation_pct numeric,
    note text,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT org_relations_allocation_pct_check CHECK (((allocation_pct IS NULL) OR ((allocation_pct >= (0)::numeric) AND (allocation_pct <= (100)::numeric)))),
    CONSTRAINT org_relations_check CHECK ((employee_id <> related_employee_id)),
    CONSTRAINT org_relations_check1 CHECK (((end_date IS NULL) OR (end_date >= start_date))),
    CONSTRAINT org_relations_relation_type_check CHECK ((relation_type = ANY (ARRAY['dotted'::text, 'interim'::text, 'functional'::text])))
);


--
-- Name: TABLE org_relations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.org_relations IS 'Liens hors hiérarchie. interim : employee_id assure l''intérim de related_employee_id ; dotted / functional : employee_id rapporte aussi à related_employee_id.';


--
-- Name: overtime_rates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.overtime_rates (
    code text NOT NULL,
    label text NOT NULL,
    rate_uplift numeric NOT NULL,
    hours_from numeric,
    hours_to numeric,
    source_code text,
    legal_min_uplift numeric DEFAULT 0 NOT NULL,
    legal_min_source text,
    CONSTRAINT overtime_rates_legal_min_uplift_check CHECK ((legal_min_uplift >= (0)::numeric)),
    CONSTRAINT overtime_rates_not_below_legal_min CHECK ((rate_uplift >= legal_min_uplift)),
    CONSTRAINT overtime_rates_rate_uplift_check CHECK ((rate_uplift >= (0)::numeric))
);


--
-- Name: COLUMN overtime_rates.legal_min_uplift; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.overtime_rates.legal_min_uplift IS 'Majoration minimale du décret 70-184 ; rate_uplift (CCNI ou accord) ne peut pas être inférieur.';


--
-- Name: payment_modes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_modes (
    code text NOT NULL,
    label text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 100 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid DEFAULT auth.uid(),
    CONSTRAINT payment_modes_code_check CHECK (((length(TRIM(BOTH FROM code)) >= 2) AND (length(TRIM(BOTH FROM code)) <= 40))),
    CONSTRAINT payment_modes_label_check CHECK ((length(TRIM(BOTH FROM label)) > 0))
);


--
-- Name: TABLE payment_modes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.payment_modes IS 'Référentiel des modes de paiement du salaire.';


--
-- Name: payroll_anomalies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_anomalies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payroll_entry_id uuid NOT NULL,
    severity text NOT NULL,
    code text NOT NULL,
    message text NOT NULL,
    employee_id uuid,
    status text DEFAULT 'ouverte'::text NOT NULL,
    resolution_note text,
    resolved_by uuid,
    resolved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payroll_anomalies_severity_check CHECK ((severity = ANY (ARRAY['bloquante'::text, 'avertissement'::text, 'information'::text]))),
    CONSTRAINT payroll_anomalies_status_check CHECK ((status = ANY (ARRAY['ouverte'::text, 'justifiée'::text, 'résolue'::text, 'ignorée'::text])))
);


--
-- Name: payroll_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_approvals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payroll_entry_id uuid NOT NULL,
    role text NOT NULL,
    decision text NOT NULL,
    comment text,
    actor_id uuid DEFAULT auth.uid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payroll_approvals_decision_check CHECK ((decision = ANY (ARRAY['approuvée'::text, 'rejetée'::text]))),
    CONSTRAINT payroll_approvals_role_check CHECK ((role = ANY (ARRAY['paie'::text, 'rh'::text, 'admin'::text])))
);


--
-- Name: payroll_corrections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_corrections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    source_period date NOT NULL,
    kind text NOT NULL,
    amount numeric NOT NULL,
    reason text NOT NULL,
    status text DEFAULT 'En attente'::text NOT NULL,
    applied_period date,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payroll_corrections_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT payroll_corrections_kind_check CHECK ((kind = ANY (ARRAY['gain'::text, 'retenue'::text]))),
    CONSTRAINT payroll_corrections_reason_check CHECK ((length(TRIM(BOTH FROM reason)) > 0)),
    CONSTRAINT payroll_corrections_source_period_check CHECK ((source_period = (date_trunc('month'::text, (source_period)::timestamp with time zone))::date)),
    CONSTRAINT payroll_corrections_status_check CHECK ((status = ANY (ARRAY['En attente'::text, 'Appliquée'::text, 'Annulée'::text])))
);


--
-- Name: TABLE payroll_corrections; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.payroll_corrections IS 'Correction d''un mois déjà validé : appliquée comme ligne de régularisation sur la prochaine période calculée, le mois d''origine reste intact.';


--
-- Name: payroll_inputs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_inputs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    period date NOT NULL,
    absence_hours numeric DEFAULT 0 NOT NULL,
    sick_leave_hours numeric DEFAULT 0 NOT NULL,
    sick_leave_rate numeric DEFAULT 1 NOT NULL,
    meal_count numeric DEFAULT 0 NOT NULL,
    overtime_15 numeric DEFAULT 0 NOT NULL,
    overtime_40 numeric DEFAULT 0 NOT NULL,
    overtime_60 numeric DEFAULT 0 NOT NULL,
    overtime_100 numeric DEFAULT 0 NOT NULL,
    leave_allowance numeric DEFAULT 0 NOT NULL,
    previous_rounding numeric DEFAULT 0 NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    attendance_override boolean DEFAULT false NOT NULL,
    CONSTRAINT payroll_inputs_absence_hours_check CHECK ((absence_hours >= (0)::numeric)),
    CONSTRAINT payroll_inputs_meal_count_check CHECK ((meal_count >= (0)::numeric)),
    CONSTRAINT payroll_inputs_overtime_100_check CHECK ((overtime_100 >= (0)::numeric)),
    CONSTRAINT payroll_inputs_overtime_15_check CHECK ((overtime_15 >= (0)::numeric)),
    CONSTRAINT payroll_inputs_overtime_40_check CHECK ((overtime_40 >= (0)::numeric)),
    CONSTRAINT payroll_inputs_overtime_60_check CHECK ((overtime_60 >= (0)::numeric)),
    CONSTRAINT payroll_inputs_period_check CHECK ((EXTRACT(day FROM period) = (1)::numeric)),
    CONSTRAINT payroll_inputs_sick_leave_hours_check CHECK ((sick_leave_hours >= (0)::numeric)),
    CONSTRAINT payroll_inputs_sick_leave_rate_check CHECK (((sick_leave_rate >= (0)::numeric) AND (sick_leave_rate <= (1)::numeric)))
);


--
-- Name: TABLE payroll_inputs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.payroll_inputs IS 'Éléments variables du mois (Excel: colonnes W à AE, AY, CQ de « élements de salaires »).';


--
-- Name: payroll_periods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_periods (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    status text DEFAULT 'Brouillon'::text NOT NULL,
    locked_at timestamp with time zone,
    locked_by uuid,
    reopened_at timestamp with time zone,
    reopened_by uuid,
    reopen_reason text,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payroll_periods_check CHECK ((period_end >= period_start)),
    CONSTRAINT payroll_periods_status_check CHECK ((status = ANY (ARRAY['Brouillon'::text, 'Calculée'::text, 'En revue'::text, 'Approuvée'::text, 'Validée'::text, 'Payée'::text, 'Clôturée'::text, 'Annulée'::text, 'Réouverte'::text])))
);


--
-- Name: payroll_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_snapshots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payroll_entry_id uuid NOT NULL,
    payload jsonb NOT NULL,
    payload_hash text NOT NULL,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    hash_algo text DEFAULT 'md5'::text NOT NULL
);


--
-- Name: recurring_pay_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recurring_pay_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    component_code text NOT NULL,
    amount numeric NOT NULL,
    from_period date NOT NULL,
    to_period date,
    active boolean DEFAULT true NOT NULL,
    notes text,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT recurring_pay_items_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT recurring_pay_items_check CHECK (((to_period IS NULL) OR ((to_period = (date_trunc('month'::text, (to_period)::timestamp with time zone))::date) AND (to_period >= from_period)))),
    CONSTRAINT recurring_pay_items_from_period_check CHECK ((from_period = (date_trunc('month'::text, (from_period)::timestamp with time zone))::date))
);


--
-- Name: TABLE recurring_pay_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.recurring_pay_items IS 'Prime ou retenue reconduite chaque mois entre from_period et to_period (inclus). Rubriques à saisie variable uniquement.';


--
-- Name: refresh_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    token_hash text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    is_revoked boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone
);


--
-- Name: salary_components; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salary_components (
    code text NOT NULL,
    name text NOT NULL,
    rubric_number integer,
    component_type text NOT NULL,
    input_mode text DEFAULT 'computed'::text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT salary_components_component_type_check CHECK ((component_type = ANY (ARRAY['gross_earning'::text, 'statutory_deduction'::text, 'employer_contribution'::text, 'non_taxable_earning'::text, 'net_deduction'::text, 'rounding'::text]))),
    CONSTRAINT salary_components_input_mode_check CHECK ((input_mode = ANY (ARRAY['computed'::text, 'variable'::text, 'fixed'::text])))
);


--
-- Name: TABLE salary_components; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.salary_components IS 'Rubriques de paie (Frappe: Salary Component). input_mode=variable => saisie mensuelle via additional_salaries.';


--
-- Name: salary_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salary_payments (
    slip_id uuid NOT NULL,
    payment_mode text NOT NULL,
    status text DEFAULT '?? payer'::text NOT NULL,
    paid_at date,
    reference text,
    note text,
    paid_by uuid DEFAULT auth.uid(),
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT salary_payments_check CHECK (((status = 'À payer'::text) OR (paid_at IS NOT NULL))),
    CONSTRAINT salary_payments_status_check CHECK ((status = ANY (ARRAY['À payer'::text, 'Payé'::text])))
);


--
-- Name: salary_slip_details; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salary_slip_details (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    salary_slip_id uuid NOT NULL,
    component_code text NOT NULL,
    label text NOT NULL,
    section text NOT NULL,
    sort_order integer NOT NULL,
    base numeric,
    quantity numeric,
    employee_rate numeric,
    gain_amount numeric DEFAULT 0 NOT NULL,
    deduction_amount numeric DEFAULT 0 NOT NULL,
    employer_rate numeric,
    employer_amount numeric DEFAULT 0 NOT NULL,
    CONSTRAINT salary_slip_details_section_check CHECK ((section = ANY (ARRAY['gain'::text, 'retenue'::text, 'patronal'::text, 'indemnite'::text, 'retenue_net'::text, 'appoint'::text])))
);


--
-- Name: TABLE salary_slip_details; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.salary_slip_details IS 'Lignes du bulletin (Excel: BULLETIN!A18:J67).';


--
-- Name: salary_slips; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salary_slips (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payroll_entry_id uuid,
    employee_id uuid NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    status text DEFAULT 'Brouillon'::text NOT NULL,
    employee_number text NOT NULL,
    employee_name text NOT NULL,
    designation text,
    address text,
    grade_code text,
    grade_class text,
    staff_status text,
    employment_type text,
    contract_situation text,
    date_of_joining date,
    seniority_years integer,
    seniority_months integer,
    marital_status text,
    spouses_count smallint,
    children_count smallint,
    trimf_parts numeric,
    ir_parts numeric,
    payment_mode text,
    hourly_rate numeric,
    gross_pay numeric DEFAULT 0 NOT NULL,
    income_tax numeric DEFAULT 0 NOT NULL,
    trimf numeric DEFAULT 0 NOT NULL,
    total_employee_deductions numeric DEFAULT 0 NOT NULL,
    net_remuneration numeric DEFAULT 0 NOT NULL,
    total_non_taxable numeric DEFAULT 0 NOT NULL,
    total_net_deductions numeric DEFAULT 0 NOT NULL,
    net_pay numeric DEFAULT 0 NOT NULL,
    employer_charges numeric DEFAULT 0 NOT NULL,
    payroll_cost numeric DEFAULT 0 NOT NULL,
    ipres_rg_base numeric DEFAULT 0 NOT NULL,
    ipres_rc_base numeric DEFAULT 0 NOT NULL,
    css_base numeric DEFAULT 0 NOT NULL,
    ipm_base numeric DEFAULT 0 NOT NULL,
    leave_provision numeric DEFAULT 0 NOT NULL,
    calculation jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    precarity_provision numeric DEFAULT 0 NOT NULL,
    CONSTRAINT salary_slips_check CHECK ((period_end >= period_start)),
    CONSTRAINT salary_slips_status_check CHECK ((status = ANY (ARRAY['Brouillon'::text, 'Validé'::text, 'Annulé'::text])))
);


--
-- Name: salary_structure_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salary_structure_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    structure_id uuid NOT NULL,
    from_date date NOT NULL,
    base_salary numeric,
    sursalaire numeric DEFAULT 0 NOT NULL,
    fees numeric DEFAULT 0 NOT NULL,
    other_fixed numeric DEFAULT 0 NOT NULL,
    transport_mode text DEFAULT 'Prime de transport'::text NOT NULL,
    leave_paid_monthly boolean DEFAULT true NOT NULL,
    target_net numeric,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT salary_structure_assignments_transport_mode_check CHECK ((transport_mode = ANY (ARRAY['Prime de transport'::text, 'Indemnité kilométrique'::text, 'Aucun'::text])))
);


--
-- Name: TABLE salary_structure_assignments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.salary_structure_assignments IS 'Affectation de structure (Frappe: Salary Structure Assignment) : base, sursalaire, transport…';


--
-- Name: salary_structure_components; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salary_structure_components (
    structure_id uuid NOT NULL,
    component_code text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL
);


--
-- Name: salary_structures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salary_structures (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: severance_scales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.severance_scales (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kind text NOT NULL,
    year_from smallint NOT NULL,
    year_to smallint,
    rate numeric NOT NULL,
    source_code text,
    CONSTRAINT severance_scales_check CHECK (((year_to IS NULL) OR (year_to > year_from))),
    CONSTRAINT severance_scales_kind_check CHECK ((kind = ANY (ARRAY['LICENCIEMENT'::text, 'RETRAITE'::text]))),
    CONSTRAINT severance_scales_rate_check CHECK (((rate > (0)::numeric) AND (rate <= (1)::numeric))),
    CONSTRAINT severance_scales_year_from_check CHECK ((year_from >= 0))
);


--
-- Name: TABLE severance_scales; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.severance_scales IS 'Taux par année d''ancienneté, miroir de severance_coefficient() ; la fonction n''est pas encore branchée sur cette table (ticket C26-25).';


--
-- Name: shift_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shift_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    work_date date NOT NULL,
    shift_code text NOT NULL,
    post_id uuid,
    notes text,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: shift_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shift_types (
    code text NOT NULL,
    label text NOT NULL,
    start_time time without time zone,
    end_time time without time zone,
    hours numeric DEFAULT 0 NOT NULL,
    is_night boolean DEFAULT false NOT NULL,
    is_rest boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 100 NOT NULL,
    CONSTRAINT shift_types_hours_check CHECK (((hours >= (0)::numeric) AND (hours <= (24)::numeric)))
);


--
-- Name: statutory_notice; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.statutory_notice (
    code text NOT NULL,
    label text NOT NULL,
    amount numeric NOT NULL,
    unit text NOT NULL,
    source_code text,
    CONSTRAINT statutory_notice_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT statutory_notice_unit_check CHECK ((unit = ANY (ARRAY['MOIS'::text, 'JOURS'::text, 'HEURES_PAR_JOURNEE'::text])))
);


--
-- Name: TABLE statutory_notice; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.statutory_notice IS 'Préavis applicable aux entreprises sans convention collective (décret 70-185) ; le contrat peut prévoir plus long (art. 2).';


--
-- Name: tax_slab_brackets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tax_slab_brackets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slab_id uuid NOT NULL,
    from_amount numeric NOT NULL,
    rate numeric NOT NULL,
    CONSTRAINT tax_slab_brackets_rate_check CHECK (((rate >= (0)::numeric) AND (rate < (1)::numeric)))
);


--
-- Name: tax_slabs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tax_slabs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    effective_from date NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: team_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_members (
    team_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    role_in_team text DEFAULT 'membre'::text NOT NULL,
    allocation_pct numeric DEFAULT 0 NOT NULL,
    start_date date DEFAULT CURRENT_DATE NOT NULL,
    end_date date,
    CONSTRAINT team_members_allocation_pct_check CHECK (((allocation_pct >= (0)::numeric) AND (allocation_pct <= (100)::numeric))),
    CONSTRAINT team_members_check CHECK (((end_date IS NULL) OR (end_date >= start_date)))
);


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    kind text NOT NULL,
    lead_employee_id uuid,
    start_date date DEFAULT CURRENT_DATE NOT NULL,
    end_date date,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT teams_check CHECK (((end_date IS NULL) OR (end_date >= start_date))),
    CONSTRAINT teams_kind_check CHECK ((kind = ANY (ARRAY['department'::text, 'cross_functional'::text, 'project'::text, 'committee'::text]))),
    CONSTRAINT teams_name_check CHECK ((length(TRIM(BOTH FROM name)) > 0))
);


--
-- Name: trainings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trainings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    start_date date NOT NULL,
    end_date date,
    status text DEFAULT 'en_cours'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT trainings_status_check CHECK ((status = ANY (ARRAY['en_cours'::text, 'terminé'::text, 'abandonné'::text])))
);


--
-- Name: trimf_brackets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trimf_brackets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slab_id uuid NOT NULL,
    min_annual_gross numeric NOT NULL,
    annual_amount numeric NOT NULL,
    per_part boolean DEFAULT true NOT NULL
);


--
-- Name: TABLE trimf_brackets; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.trimf_brackets IS 'Taxe représentative de l''impôt du minimum fiscal (TRIMF).';


--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_roles (
    user_id uuid NOT NULL,
    role text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_roles_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'rh'::text, 'paie'::text, 'manager'::text, 'salarie'::text])))
);


--
-- Name: v_payroll_register; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_payroll_register WITH (security_invoker='true') AS
 SELECT s.id AS salary_slip_id,
    s.payroll_entry_id,
    s.period_start,
    s.status,
    s.employee_id,
    s.employee_number,
    s.employee_name,
    s.designation,
    s.grade_code,
    s.staff_status,
    s.employment_type,
    s.contract_situation,
    ((j.i ->> 'base_salary'::text))::numeric AS base_salary,
    ((j.i ->> 'sursalaire'::text))::numeric AS sursalaire,
    ((j.t ->> 'seniority_bonus'::text))::numeric AS seniority_bonus,
    ((j.t ->> 'variable_gross'::text))::numeric AS variable_gross,
    ((j.t ->> 'leave_allowance'::text))::numeric AS leave_allowance,
    ((j.t ->> 'overtime_amount'::text))::numeric AS overtime_amount,
    s.gross_pay,
    s.income_tax,
    s.trimf,
    ((j.t ->> 'brs'::text))::numeric AS brs,
    ((j.t ->> 'ipres_rg_employee'::text))::numeric AS ipres_rg_employee,
    ((j.t ->> 'ipres_rc_employee'::text))::numeric AS ipres_rc_employee,
    ((j.t ->> 'ipm_employee'::text))::numeric AS ipm_employee,
    s.total_employee_deductions,
    s.net_remuneration,
    ((j.t ->> 'transport_allowance'::text))::numeric AS transport_allowance,
    ((j.t ->> 'meal_allowance'::text))::numeric AS meal_allowance,
    ((j.t ->> 'km_allowance'::text))::numeric AS km_allowance,
    ((j.t ->> 'previous_rounding'::text))::numeric AS previous_rounding,
    s.total_non_taxable,
    s.total_net_deductions,
    s.net_pay,
    ((j.t ->> 'cfce'::text))::numeric AS cfce,
    ((j.t ->> 'ipres_rg_employer'::text))::numeric AS ipres_rg_employer,
    ((j.t ->> 'ipres_rc_employer'::text))::numeric AS ipres_rc_employer,
    ((j.t ->> 'css_af'::text))::numeric AS css_af,
    ((j.t ->> 'css_at'::text))::numeric AS css_at,
    ((j.t ->> 'ipm_employer'::text))::numeric AS ipm_employer,
    s.employer_charges,
    s.payroll_cost,
    s.leave_provision,
    s.precarity_provision,
    ((j.t ->> 'precarity_allowance'::text))::numeric AS precarity_allowance,
    (COALESCE(((j.t ->> 'ipres_rg_employee'::text))::numeric, (0)::numeric) + COALESCE(((j.t ->> 'ipres_rg_employer'::text))::numeric, (0)::numeric)) AS ipres_rg_total,
    (COALESCE(((j.t ->> 'ipres_rc_employee'::text))::numeric, (0)::numeric) + COALESCE(((j.t ->> 'ipres_rc_employer'::text))::numeric, (0)::numeric)) AS ipres_rc_total,
    (s.status = 'Validé'::text) AS is_validated,
    COALESCE(c.months, (0)::bigint) AS ytd_validated_months,
    COALESCE(c.trimf, (0)::numeric) AS ytd_trimf,
    COALESCE(c.ipres_rg, (0)::numeric) AS ytd_ipres_rg,
    COALESCE(c.ipres_rc, (0)::numeric) AS ytd_ipres_rc,
    COALESCE(c.precarity_provision, (0)::numeric) AS ytd_precarity_provision,
    COALESCE(c.leave_provision, (0)::numeric) AS ytd_leave_provision,
    COALESCE(c.gross, (0)::numeric) AS ytd_gross,
    COALESCE(c.net, (0)::numeric) AS ytd_net_pay,
    COALESCE(c.payroll_cost, (0)::numeric) AS ytd_payroll_cost
   FROM ((public.salary_slips s
     CROSS JOIN LATERAL ( SELECT (s.calculation -> 'inputs'::text) AS i,
            (s.calculation -> 'totals'::text) AS t
         OFFSET 0) j)
     LEFT JOIN LATERAL ( SELECT count(*) AS months,
            sum(p.trimf) AS trimf,
            sum((COALESCE(((k.t ->> 'ipres_rg_employee'::text))::numeric, (0)::numeric) + COALESCE(((k.t ->> 'ipres_rg_employer'::text))::numeric, (0)::numeric))) AS ipres_rg,
            sum((COALESCE(((k.t ->> 'ipres_rc_employee'::text))::numeric, (0)::numeric) + COALESCE(((k.t ->> 'ipres_rc_employer'::text))::numeric, (0)::numeric))) AS ipres_rc,
            sum(p.precarity_provision) AS precarity_provision,
            sum(p.leave_provision) AS leave_provision,
            sum(p.gross_pay) AS gross,
            sum(p.net_pay) AS net,
            sum(p.payroll_cost) AS payroll_cost
           FROM ((public.salary_slips p
             CROSS JOIN LATERAL ( SELECT (p.calculation -> 'totals'::text) AS t
                 OFFSET 0) k)
             JOIN public.payroll_entries pe ON (((pe.id = p.payroll_entry_id) AND (pe.status = ANY (ARRAY['Validée'::text, 'Payée'::text, 'Clôturée'::text])))))
          WHERE ((p.employee_id = s.employee_id) AND (p.status = 'Validé'::text) AND (p.period_start >= (date_trunc('year'::text, (s.period_start)::timestamp with time zone))::date) AND (p.period_start <= s.period_start))) c ON (true))
  WHERE (s.status <> 'Annulé'::text);


--
-- Name: v_accounting_journal; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_accounting_journal WITH (security_invoker='true') AS
 WITH t AS (
         SELECT r.payroll_entry_id,
            r.period_start,
            sum(r.gross_pay) FILTER (WHERE (r.contract_situation <> 'PRESTATION'::text)) AS brut_salaries,
            sum(r.gross_pay) FILTER (WHERE (r.contract_situation = 'PRESTATION'::text)) AS brut_presta,
            sum(r.total_non_taxable) AS indemnites,
            sum(r.previous_rounding) AS appoints,
            sum(r.ipres_rg_employee) AS rg_sal,
            sum(r.ipres_rc_employee) AS rc_sal,
            sum(r.ipm_employee) AS ipm_sal,
            sum(r.income_tax) AS ir,
            sum(r.trimf) AS trimf,
            sum(r.brs) AS brs,
            sum(r.total_net_deductions) AS retenues_net,
            sum(r.ipres_rg_employer) AS rg_pat,
            sum(r.ipres_rc_employer) AS rc_pat,
            sum(r.css_af) AS css_af,
            sum(r.css_at) AS css_at,
            sum(r.ipm_employer) AS ipm_pat,
            sum(r.cfce) AS cfce
           FROM public.v_payroll_register r
          GROUP BY r.payroll_entry_id, r.period_start
        )
 SELECT t.payroll_entry_id,
    t.period_start,
    j.journal,
    j.line_no,
    j.account,
    j.label,
    j.debit,
    j.credit
   FROM (t
     CROSS JOIN LATERAL ( VALUES ('1-Salaires'::text,1,'661'::text,'Rémunération directe versée'::text,COALESCE(t.brut_salaries, (0)::numeric),(0)::numeric), ('1-Salaires'::text,2,'663'::text,'Indemnités forfaitaires'::text,(COALESCE(t.indemnites, (0)::numeric) + COALESCE(t.appoints, (0)::numeric)),0), ('1-Salaires'::text,3,'6057'::text,'Achats d''études et prestations de services'::text,COALESCE(t.brut_presta, (0)::numeric),0), ('1-Salaires'::text,4,'422'::text,'Personnel, rémunérations dues'::text,0,((COALESCE(t.brut_salaries, (0)::numeric) + COALESCE(t.indemnites, (0)::numeric)) + COALESCE(t.appoints, (0)::numeric))), ('1-Salaires'::text,5,'401'::text,'Honoraires prestataires'::text,0,COALESCE(t.brut_presta, (0)::numeric)), ('2-Retenues'::text,1,'422'::text,'Personnel, rémunérations dues'::text,(((((COALESCE(t.rg_sal, (0)::numeric) + COALESCE(t.rc_sal, (0)::numeric)) + COALESCE(t.ipm_sal, (0)::numeric)) + COALESCE(t.ir, (0)::numeric)) + COALESCE(t.trimf, (0)::numeric)) + COALESCE(t.retenues_net, (0)::numeric)),0), ('2-Retenues'::text,2,'401'::text,'Honoraires prestataires (BRS)'::text,COALESCE(t.brs, (0)::numeric),0), ('2-Retenues'::text,3,'421'::text,'Avances et retenues diverses'::text,0,COALESCE(t.retenues_net, (0)::numeric)), ('2-Retenues'::text,4,'4313'::text,'IPRES régime général'::text,0,COALESCE(t.rg_sal, (0)::numeric)), ('2-Retenues'::text,5,'4314'::text,'IPRES régime cadre'::text,0,COALESCE(t.rc_sal, (0)::numeric)), ('2-Retenues'::text,6,'4331'::text,'IPM'::text,0,COALESCE(t.ipm_sal, (0)::numeric)), ('2-Retenues'::text,7,'4471'::text,'Impôt sur le revenu'::text,0,COALESCE(t.ir, (0)::numeric)), ('2-Retenues'::text,8,'4472'::text,'TRIMF'::text,0,COALESCE(t.trimf, (0)::numeric)), ('2-Retenues'::text,9,'4471'::text,'BRS'::text,0,COALESCE(t.brs, (0)::numeric)), ('3-Charges patronales'::text,1,'664'::text,'Charges sociales'::text,((((COALESCE(t.rg_pat, (0)::numeric) + COALESCE(t.rc_pat, (0)::numeric)) + COALESCE(t.css_af, (0)::numeric)) + COALESCE(t.css_at, (0)::numeric)) + COALESCE(t.ipm_pat, (0)::numeric)),0), ('3-Charges patronales'::text,2,'641'::text,'Impôts sur rémunérations (CFCE)'::text,COALESCE(t.cfce, (0)::numeric),0), ('3-Charges patronales'::text,3,'4311'::text,'CSS prestations familiales'::text,0,COALESCE(t.css_af, (0)::numeric)), ('3-Charges patronales'::text,4,'4312'::text,'CSS accidents du travail'::text,0,COALESCE(t.css_at, (0)::numeric)), ('3-Charges patronales'::text,5,'4313'::text,'IPRES régime général'::text,0,COALESCE(t.rg_pat, (0)::numeric)), ('3-Charges patronales'::text,6,'4314'::text,'IPRES régime cadre'::text,0,COALESCE(t.rc_pat, (0)::numeric)), ('3-Charges patronales'::text,7,'4331'::text,'IPM'::text,0,COALESCE(t.ipm_pat, (0)::numeric)), ('3-Charges patronales'::text,8,'4473'::text,'CFCE'::text,0,COALESCE(t.cfce, (0)::numeric))) j(journal, line_no, account, label, debit, credit))
  WHERE ((j.debit <> (0)::numeric) OR (j.credit <> (0)::numeric));


--
-- Name: v_conformite_embauche; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_conformite_embauche WITH (security_invoker='true') AS
 SELECT id AS employee_id,
    employee_number,
    date_of_joining,
    (hire_declaration_ref IS NULL) AS declaration_manquante,
    (((affiliation_date IS NULL) AND (CURRENT_DATE > ((date_of_joining + '2 mons'::interval))::date)) OR ((affiliation_date IS NOT NULL) AND (affiliation_date > ((date_of_joining + '2 mons'::interval))::date))) AS affiliation_hors_delai
   FROM public.employees e
  WHERE ((status <> 'Left'::text) AND ((hire_declaration_ref IS NULL) OR ((affiliation_date IS NULL) AND (CURRENT_DATE > ((date_of_joining + '2 mons'::interval))::date)) OR ((affiliation_date IS NOT NULL) AND (affiliation_date > ((date_of_joining + '2 mons'::interval))::date))));


--
-- Name: VIEW v_conformite_embauche; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_conformite_embauche IS 'Salariés en poste sans déclaration d''embauche ou affiliés plus de 2 mois après l''embauche.';


--
-- Name: v_conformite_retenues; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_conformite_retenues WITH (security_invoker='true') AS
 WITH p AS (
         SELECT min(payroll_settings.deduction_global_cap) AS cap
           FROM public.payroll_settings
        ), b AS (
         SELECT s.id AS slip_id,
            s.employee_id,
            s.employee_number,
            s.period_start,
            s.status,
            s.total_net_deductions AS retenues,
            (s.gross_pay + s.total_non_taxable) AS assiette
           FROM public.salary_slips s
          WHERE (s.total_net_deductions > (0)::numeric)
        )
 SELECT b.slip_id,
    b.employee_id,
    b.employee_number,
    b.period_start,
    b.status,
    b.assiette,
    b.retenues,
    public.quotite_cessible(b.assiette) AS quotite_cessible,
    public.plafond_retenues(b.assiette, p.cap) AS plafond_global,
    (b.retenues > public.quotite_cessible(b.assiette)) AS depasse_quotite_cessible,
    (b.retenues > public.plafond_retenues(b.assiette, p.cap)) AS depasse_plafond_global
   FROM (b
     CROSS JOIN p)
  WHERE ((b.retenues > public.quotite_cessible(b.assiette)) OR (b.retenues > public.plafond_retenues(b.assiette, p.cap)));


--
-- Name: VIEW v_conformite_retenues; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_conformite_retenues IS 'Bulletins dont les retenues sur net dépassent la quotité cessible (CPC 381) ou le plafond global des 2/3 ; lecture seule.';


--
-- Name: v_contribution_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_contribution_summary WITH (security_invoker='true') AS
 SELECT s.payroll_entry_id,
    s.period_start,
    d.component_code,
    min(d.label) AS label,
    min(d.sort_order) AS sort_order,
    max(d.employee_rate) AS employee_rate,
    max(d.employer_rate) AS employer_rate,
    sum(COALESCE(d.base, (0)::numeric)) AS base_total,
    sum(d.deduction_amount) AS employee_amount,
    sum(d.employer_amount) AS employer_amount,
    sum((d.deduction_amount + d.employer_amount)) AS total_amount,
    count(*) FILTER (WHERE ((d.deduction_amount <> (0)::numeric) OR (d.employer_amount <> (0)::numeric))) AS headcount
   FROM (public.salary_slip_details d
     JOIN public.salary_slips s ON ((s.id = d.salary_slip_id)))
  WHERE ((s.status <> 'Annulé'::text) AND (d.section = ANY (ARRAY['retenue'::text, 'patronal'::text])))
  GROUP BY s.payroll_entry_id, s.period_start, d.component_code;


--
-- Name: v_echeancier_cotisations; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_echeancier_cotisations WITH (security_invoker='true') AS
 WITH m AS (
         SELECT (date_trunc('month'::text, (s.period_start)::timestamp with time zone))::date AS mois,
            count(DISTINCT s.employee_id) AS effectif,
            sum((((((COALESCE((((s.calculation -> 'totals'::text) ->> 'ipres_rg_employee'::text))::numeric, (0)::numeric) + COALESCE((((s.calculation -> 'totals'::text) ->> 'ipres_rg_employer'::text))::numeric, (0)::numeric)) + COALESCE((((s.calculation -> 'totals'::text) ->> 'ipres_rc_employee'::text))::numeric, (0)::numeric)) + COALESCE((((s.calculation -> 'totals'::text) ->> 'ipres_rc_employer'::text))::numeric, (0)::numeric)) + COALESCE((((s.calculation -> 'totals'::text) ->> 'css_af'::text))::numeric, (0)::numeric)) + COALESCE((((s.calculation -> 'totals'::text) ->> 'css_at'::text))::numeric, (0)::numeric))) AS montant_du
           FROM public.salary_slips s
          WHERE (s.status = 'Validé'::text)
          GROUP BY ((date_trunc('month'::text, (s.period_start)::timestamp with time zone))::date)
        )
 SELECT m.mois,
    m.effectif,
    m.montant_du,
    public.echeance_cotisations(m.mois, (m.effectif)::integer) AS echeance,
    p.paid_on AS paye_le,
    p.amount AS montant_paye,
    (public.echeance_cotisations(m.mois, (m.effectif)::integer) - CURRENT_DATE) AS jours_restants,
    public.majoration_retard_cotisations(m.montant_du, public.echeance_cotisations(m.mois, (m.effectif)::integer), COALESCE(p.paid_on, CURRENT_DATE)) AS majoration_estimee
   FROM (m
     LEFT JOIN public.contribution_payments p ON ((p.month = m.mois)));


--
-- Name: VIEW v_echeancier_cotisations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_echeancier_cotisations IS 'Cotisations sociales dues par mois de paie validée, échéance légale et majoration de retard estimée.';


--
-- Name: v_leave_balances; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_leave_balances WITH (security_invoker='true') AS
 WITH alloc AS (
         SELECT leave_allocations.employee_id,
            leave_allocations.leave_type,
            sum(leave_allocations.days) AS allocated
           FROM public.leave_allocations
          WHERE (leave_allocations.to_date >= date_trunc('year'::text, (CURRENT_DATE)::timestamp with time zone))
          GROUP BY leave_allocations.employee_id, leave_allocations.leave_type
        ), used AS (
         SELECT leave_applications.employee_id,
            leave_applications.leave_type,
            sum(leave_applications.total_days) AS taken
           FROM public.leave_applications
          WHERE ((leave_applications.status = 'Approuvée'::text) AND (leave_applications.from_date >= date_trunc('year'::text, (CURRENT_DATE)::timestamp with time zone)))
          GROUP BY leave_applications.employee_id, leave_applications.leave_type
        )
 SELECT e.id AS employee_id,
    e.employee_number,
    e.first_name,
    e.last_name,
    lt.code AS leave_type,
    lt.name AS leave_type_name,
    COALESCE(a.allocated, (0)::numeric) AS allocated,
    COALESCE(u.taken, (0)::numeric) AS taken,
    (COALESCE(a.allocated, (0)::numeric) - COALESCE(u.taken, (0)::numeric)) AS balance
   FROM (((public.employees e
     CROSS JOIN public.leave_types lt)
     LEFT JOIN alloc a ON (((a.employee_id = e.id) AND (a.leave_type = lt.code))))
     LEFT JOIN used u ON (((u.employee_id = e.id) AND (u.leave_type = lt.code))))
  WHERE ((e.status = 'Active'::text) AND ((a.allocated IS NOT NULL) OR (u.taken IS NOT NULL)));


--
-- Name: v_payroll_entry_payments; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_payroll_entry_payments WITH (security_invoker='true') AS
 SELECT s.payroll_entry_id,
    count(*) AS slips,
    count(*) FILTER (WHERE (p.status = 'Payé'::text)) AS paid
   FROM (public.salary_slips s
     LEFT JOIN public.salary_payments p ON ((p.slip_id = s.id)))
  WHERE (s.status = 'Validé'::text)
  GROUP BY s.payroll_entry_id;


--
-- Name: v_salary_slip_ytd; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_salary_slip_ytd AS
SELECT
    NULL::uuid AS salary_slip_id,
    NULL::uuid AS employee_id,
    NULL::date AS period_start,
    NULL::numeric AS ytd_gross,
    NULL::numeric AS ytd_income_tax,
    NULL::numeric AS ytd_trimf,
    NULL::numeric AS ytd_leave_provision,
    NULL::numeric AS ytd_ipres_rg,
    NULL::numeric AS ytd_ipres_rc,
    NULL::numeric AS ytd_net_pay,
    NULL::numeric AS ytd_payroll_cost,
    NULL::numeric AS ytd_precarity_provision;


--
-- Name: v_slip_payment_status; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_slip_payment_status WITH (security_invoker='true') AS
 SELECT p.slip_id,
    s.payroll_entry_id,
    (p.status = 'Payé'::text) AS paid,
    p.paid_at,
    p.payment_mode,
    p.reference
   FROM (public.salary_payments p
     JOIN public.salary_slips s ON ((s.id = p.slip_id)))
  WHERE (s.status <> 'Annulé'::text);


--
-- Name: work_posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_posts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    site text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT work_posts_name_check CHECK ((length(TRIM(BOTH FROM name)) > 0))
);


--
-- Name: additional_salaries additional_salaries_employee_id_period_component_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.additional_salaries
    ADD CONSTRAINT additional_salaries_employee_id_period_component_code_key UNIQUE (employee_id, period, component_code);


--
-- Name: additional_salaries additional_salaries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.additional_salaries
    ADD CONSTRAINT additional_salaries_pkey PRIMARY KEY (id);


--
-- Name: app_parameters app_parameters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_parameters
    ADD CONSTRAINT app_parameters_pkey PRIMARY KEY (code);


--
-- Name: approval_delegations approval_delegations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_delegations
    ADD CONSTRAINT approval_delegations_pkey PRIMARY KEY (id);


--
-- Name: attendance attendance_employee_id_attendance_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_employee_id_attendance_date_key UNIQUE (employee_id, attendance_date);


--
-- Name: attendance attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_pkey PRIMARY KEY (id);


--
-- Name: audit_events audit_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT audit_events_pkey PRIMARY KEY (id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: candidatures candidatures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.candidatures
    ADD CONSTRAINT candidatures_pkey PRIMARY KEY (id);


--
-- Name: collective_agreements collective_agreements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collective_agreements
    ADD CONSTRAINT collective_agreements_pkey PRIMARY KEY (code);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: compliance_findings compliance_findings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.compliance_findings
    ADD CONSTRAINT compliance_findings_pkey PRIMARY KEY (id);


--
-- Name: contract_types contract_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_types
    ADD CONSTRAINT contract_types_pkey PRIMARY KEY (code);


--
-- Name: contribution_payments contribution_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contribution_payments
    ADD CONSTRAINT contribution_payments_pkey PRIMARY KEY (month);


--
-- Name: delegate_seats delegate_seats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delegate_seats
    ADD CONSTRAINT delegate_seats_pkey PRIMARY KEY (id);


--
-- Name: delegate_seats delegate_seats_workers_min_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delegate_seats
    ADD CONSTRAINT delegate_seats_workers_min_key UNIQUE (workers_min);


--
-- Name: departments departments_company_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_company_id_name_key UNIQUE (company_id, name);


--
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (id);


--
-- Name: designations designations_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.designations
    ADD CONSTRAINT designations_name_key UNIQUE (name);


--
-- Name: designations designations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.designations
    ADD CONSTRAINT designations_pkey PRIMARY KEY (id);


--
-- Name: document_requirements document_requirements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_requirements
    ADD CONSTRAINT document_requirements_pkey PRIMARY KEY (code);


--
-- Name: document_reviews document_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_reviews
    ADD CONSTRAINT document_reviews_pkey PRIMARY KEY (id);


--
-- Name: document_versions document_versions_document_id_version_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_versions
    ADD CONSTRAINT document_versions_document_id_version_number_key UNIQUE (document_id, version_number);


--
-- Name: document_versions document_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_versions
    ADD CONSTRAINT document_versions_pkey PRIMARY KEY (id);


--
-- Name: document_versions document_versions_storage_path_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_versions
    ADD CONSTRAINT document_versions_storage_path_key UNIQUE (storage_path);


--
-- Name: email_outbox email_outbox_dedup_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_outbox
    ADD CONSTRAINT email_outbox_dedup_key_key UNIQUE (dedup_key);


--
-- Name: email_outbox email_outbox_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_outbox
    ADD CONSTRAINT email_outbox_pkey PRIMARY KEY (id);


--
-- Name: employee_document_access_log employee_document_access_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_document_access_log
    ADD CONSTRAINT employee_document_access_log_pkey PRIMARY KEY (id);


--
-- Name: employee_documents employee_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_pkey PRIMARY KEY (id);


--
-- Name: employee_documents employee_documents_storage_path_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_storage_path_key UNIQUE (storage_path);


--
-- Name: employee_grades employee_grades_agreement_code_code_staff_status_grade_clas_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_grades
    ADD CONSTRAINT employee_grades_agreement_code_code_staff_status_grade_clas_key UNIQUE NULLS NOT DISTINCT (agreement_code, code, staff_status, grade_class, effective_from);


--
-- Name: employee_grades employee_grades_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_grades
    ADD CONSTRAINT employee_grades_pkey PRIMARY KEY (id);


--
-- Name: employee_manager_assignments employee_manager_assignments_manager_employee_id_employee_i_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_manager_assignments
    ADD CONSTRAINT employee_manager_assignments_manager_employee_id_employee_i_key UNIQUE (manager_employee_id, employee_id, valid_from);


--
-- Name: employee_manager_assignments employee_manager_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_manager_assignments
    ADD CONSTRAINT employee_manager_assignments_pkey PRIMARY KEY (id);


--
-- Name: employee_module_data employee_module_data_employee_id_module_id_daterange_excl; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_module_data
    ADD CONSTRAINT employee_module_data_employee_id_module_id_daterange_excl EXCLUDE USING gist (employee_id WITH =, module_id WITH =, daterange(valid_from, valid_to, '[)'::text) WITH &&);


--
-- Name: employee_module_data employee_module_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_module_data
    ADD CONSTRAINT employee_module_data_pkey PRIMARY KEY (id);


--
-- Name: employee_notifications employee_notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_notifications
    ADD CONSTRAINT employee_notifications_pkey PRIMARY KEY (id);


--
-- Name: employee_representatives employee_representatives_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_representatives
    ADD CONSTRAINT employee_representatives_pkey PRIMARY KEY (id);


--
-- Name: employee_request_history employee_request_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_request_history
    ADD CONSTRAINT employee_request_history_pkey PRIMARY KEY (id);


--
-- Name: employee_requests employee_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_requests
    ADD CONSTRAINT employee_requests_pkey PRIMARY KEY (id);


--
-- Name: employees employees_employee_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_employee_number_key UNIQUE (employee_number);


--
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (id);


--
-- Name: employees employees_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_user_id_key UNIQUE (user_id);


--
-- Name: evaluations evaluations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluations
    ADD CONSTRAINT evaluations_pkey PRIMARY KEY (id);


--
-- Name: exit_reasons exit_reasons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exit_reasons
    ADD CONSTRAINT exit_reasons_pkey PRIMARY KEY (code);


--
-- Name: garnishment_scale garnishment_scale_kind_lower_bound_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.garnishment_scale
    ADD CONSTRAINT garnishment_scale_kind_lower_bound_key UNIQUE (kind, lower_bound);


--
-- Name: garnishment_scale garnishment_scale_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.garnishment_scale
    ADD CONSTRAINT garnishment_scale_pkey PRIMARY KEY (id);


--
-- Name: ir_family_reductions ir_family_reductions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ir_family_reductions
    ADD CONSTRAINT ir_family_reductions_pkey PRIMARY KEY (id);


--
-- Name: ir_family_reductions ir_family_reductions_slab_id_parts_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ir_family_reductions
    ADD CONSTRAINT ir_family_reductions_slab_id_parts_key UNIQUE (slab_id, parts);


--
-- Name: job_postulations job_postulations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_postulations
    ADD CONSTRAINT job_postulations_pkey PRIMARY KEY (id);


--
-- Name: leave_allocations leave_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_allocations
    ADD CONSTRAINT leave_allocations_pkey PRIMARY KEY (id);


--
-- Name: leave_applications leave_applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_pkey PRIMARY KEY (id);


--
-- Name: leave_approval_steps leave_approval_steps_leave_id_step_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_approval_steps
    ADD CONSTRAINT leave_approval_steps_leave_id_step_key UNIQUE (leave_id, step);


--
-- Name: leave_approval_steps leave_approval_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_approval_steps
    ADD CONSTRAINT leave_approval_steps_pkey PRIMARY KEY (id);


--
-- Name: leave_types leave_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_types
    ADD CONSTRAINT leave_types_pkey PRIMARY KEY (code);


--
-- Name: legal_sources legal_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legal_sources
    ADD CONSTRAINT legal_sources_pkey PRIMARY KEY (code);


--
-- Name: loan_installments loan_installments_loan_id_due_period_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loan_installments
    ADD CONSTRAINT loan_installments_loan_id_due_period_key UNIQUE (loan_id, due_period);


--
-- Name: loan_installments loan_installments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loan_installments
    ADD CONSTRAINT loan_installments_pkey PRIMARY KEY (id);


--
-- Name: loans loans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_pkey PRIMARY KEY (id);


--
-- Name: module_activation module_activation_module_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_activation
    ADD CONSTRAINT module_activation_module_id_key UNIQUE (module_id);


--
-- Name: module_activation module_activation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_activation
    ADD CONSTRAINT module_activation_pkey PRIMARY KEY (id);


--
-- Name: module_manifest module_manifest_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_manifest
    ADD CONSTRAINT module_manifest_pkey PRIMARY KEY (module_id);


--
-- Name: module_parameter_value module_parameter_value_module_id_param_key_daterange_excl; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_parameter_value
    ADD CONSTRAINT module_parameter_value_module_id_param_key_daterange_excl EXCLUDE USING gist (module_id WITH =, param_key WITH =, daterange(valid_from, valid_to, '[)'::text) WITH &&);


--
-- Name: module_parameter_value module_parameter_value_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_parameter_value
    ADD CONSTRAINT module_parameter_value_pkey PRIMARY KEY (id);


--
-- Name: notice_scales notice_scales_agreement_code_category_valid_from_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notice_scales
    ADD CONSTRAINT notice_scales_agreement_code_category_valid_from_key UNIQUE NULLS NOT DISTINCT (agreement_code, category, valid_from);


--
-- Name: notice_scales notice_scales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notice_scales
    ADD CONSTRAINT notice_scales_pkey PRIMARY KEY (id);


--
-- Name: notifications_log notifications_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications_log
    ADD CONSTRAINT notifications_log_pkey PRIMARY KEY (id);


--
-- Name: org_positions org_positions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_positions
    ADD CONSTRAINT org_positions_pkey PRIMARY KEY (id);


--
-- Name: org_positions org_positions_unit_id_designation_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_positions
    ADD CONSTRAINT org_positions_unit_id_designation_id_key UNIQUE (unit_id, designation_id);


--
-- Name: org_relations org_relations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_relations
    ADD CONSTRAINT org_relations_pkey PRIMARY KEY (id);


--
-- Name: overtime_rates overtime_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_rates
    ADD CONSTRAINT overtime_rates_pkey PRIMARY KEY (code);


--
-- Name: payment_modes payment_modes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_modes
    ADD CONSTRAINT payment_modes_pkey PRIMARY KEY (code);


--
-- Name: payroll_anomalies payroll_anomalies_payroll_entry_id_code_employee_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_anomalies
    ADD CONSTRAINT payroll_anomalies_payroll_entry_id_code_employee_id_key UNIQUE (payroll_entry_id, code, employee_id);


--
-- Name: payroll_anomalies payroll_anomalies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_anomalies
    ADD CONSTRAINT payroll_anomalies_pkey PRIMARY KEY (id);


--
-- Name: payroll_approvals payroll_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_approvals
    ADD CONSTRAINT payroll_approvals_pkey PRIMARY KEY (id);


--
-- Name: payroll_corrections payroll_corrections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_corrections
    ADD CONSTRAINT payroll_corrections_pkey PRIMARY KEY (id);


--
-- Name: payroll_entries payroll_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_entries
    ADD CONSTRAINT payroll_entries_pkey PRIMARY KEY (id);


--
-- Name: payroll_inputs payroll_inputs_employee_id_period_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_inputs
    ADD CONSTRAINT payroll_inputs_employee_id_period_key UNIQUE (employee_id, period);


--
-- Name: payroll_inputs payroll_inputs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_inputs
    ADD CONSTRAINT payroll_inputs_pkey PRIMARY KEY (id);


--
-- Name: payroll_periods payroll_periods_company_id_period_start_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_company_id_period_start_key UNIQUE (company_id, period_start);


--
-- Name: payroll_periods payroll_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_pkey PRIMARY KEY (id);


--
-- Name: payroll_settings payroll_settings_effective_from_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_settings
    ADD CONSTRAINT payroll_settings_effective_from_key UNIQUE (effective_from);


--
-- Name: payroll_settings payroll_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_settings
    ADD CONSTRAINT payroll_settings_pkey PRIMARY KEY (id);


--
-- Name: payroll_snapshots payroll_snapshots_payroll_entry_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_snapshots
    ADD CONSTRAINT payroll_snapshots_payroll_entry_id_key UNIQUE (payroll_entry_id);


--
-- Name: payroll_snapshots payroll_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_snapshots
    ADD CONSTRAINT payroll_snapshots_pkey PRIMARY KEY (id);


--
-- Name: recurring_pay_items recurring_pay_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_pay_items
    ADD CONSTRAINT recurring_pay_items_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: salary_components salary_components_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_components
    ADD CONSTRAINT salary_components_pkey PRIMARY KEY (code);


--
-- Name: salary_payments salary_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_payments
    ADD CONSTRAINT salary_payments_pkey PRIMARY KEY (slip_id);


--
-- Name: salary_slip_details salary_slip_details_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_slip_details
    ADD CONSTRAINT salary_slip_details_pkey PRIMARY KEY (id);


--
-- Name: salary_slips salary_slips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_slips
    ADD CONSTRAINT salary_slips_pkey PRIMARY KEY (id);


--
-- Name: salary_structure_assignments salary_structure_assignments_employee_id_from_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_structure_assignments
    ADD CONSTRAINT salary_structure_assignments_employee_id_from_date_key UNIQUE (employee_id, from_date);


--
-- Name: salary_structure_assignments salary_structure_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_structure_assignments
    ADD CONSTRAINT salary_structure_assignments_pkey PRIMARY KEY (id);


--
-- Name: salary_structure_components salary_structure_components_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_structure_components
    ADD CONSTRAINT salary_structure_components_pkey PRIMARY KEY (structure_id, component_code);


--
-- Name: salary_structures salary_structures_company_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_structures
    ADD CONSTRAINT salary_structures_company_id_name_key UNIQUE (company_id, name);


--
-- Name: salary_structures salary_structures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_structures
    ADD CONSTRAINT salary_structures_pkey PRIMARY KEY (id);


--
-- Name: severance_scales severance_scales_kind_year_from_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.severance_scales
    ADD CONSTRAINT severance_scales_kind_year_from_key UNIQUE (kind, year_from);


--
-- Name: severance_scales severance_scales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.severance_scales
    ADD CONSTRAINT severance_scales_pkey PRIMARY KEY (id);


--
-- Name: shift_assignments shift_assignments_employee_id_work_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_employee_id_work_date_key UNIQUE (employee_id, work_date);


--
-- Name: shift_assignments shift_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_pkey PRIMARY KEY (id);


--
-- Name: shift_types shift_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_types
    ADD CONSTRAINT shift_types_pkey PRIMARY KEY (code);


--
-- Name: statutory_notice statutory_notice_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statutory_notice
    ADD CONSTRAINT statutory_notice_pkey PRIMARY KEY (code);


--
-- Name: tax_slab_brackets tax_slab_brackets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_slab_brackets
    ADD CONSTRAINT tax_slab_brackets_pkey PRIMARY KEY (id);


--
-- Name: tax_slab_brackets tax_slab_brackets_slab_id_from_amount_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_slab_brackets
    ADD CONSTRAINT tax_slab_brackets_slab_id_from_amount_key UNIQUE (slab_id, from_amount);


--
-- Name: tax_slabs tax_slabs_effective_from_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_slabs
    ADD CONSTRAINT tax_slabs_effective_from_key UNIQUE (effective_from);


--
-- Name: tax_slabs tax_slabs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_slabs
    ADD CONSTRAINT tax_slabs_pkey PRIMARY KEY (id);


--
-- Name: team_members team_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_pkey PRIMARY KEY (team_id, employee_id, start_date);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: trainings trainings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trainings
    ADD CONSTRAINT trainings_pkey PRIMARY KEY (id);


--
-- Name: trimf_brackets trimf_brackets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trimf_brackets
    ADD CONSTRAINT trimf_brackets_pkey PRIMARY KEY (id);


--
-- Name: trimf_brackets trimf_brackets_slab_id_min_annual_gross_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trimf_brackets
    ADD CONSTRAINT trimf_brackets_slab_id_min_annual_gross_key UNIQUE (slab_id, min_annual_gross);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role);


--
-- Name: work_posts work_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_posts
    ADD CONSTRAINT work_posts_pkey PRIMARY KEY (id);


--
-- Name: additional_salaries_component_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX additional_salaries_component_idx ON public.additional_salaries USING btree (component_code);


--
-- Name: additional_salaries_kind_period_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX additional_salaries_kind_period_idx ON public.additional_salaries USING btree (period) WHERE (kind <> 'ponctuel'::text);


--
-- Name: additional_salaries_period_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX additional_salaries_period_idx ON public.additional_salaries USING btree (period);


--
-- Name: app_parameters_updated_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_parameters_updated_by_idx ON public.app_parameters USING btree (updated_by);


--
-- Name: approval_delegations_delegate_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX approval_delegations_delegate_idx ON public.approval_delegations USING btree (delegate_user) WHERE active;


--
-- Name: approval_delegations_delegator_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX approval_delegations_delegator_idx ON public.approval_delegations USING btree (delegator_user);


--
-- Name: attendance_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX attendance_date_idx ON public.attendance USING btree (attendance_date);


--
-- Name: attendance_leave_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX attendance_leave_idx ON public.attendance USING btree (leave_application_id);


--
-- Name: attendance_updated_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX attendance_updated_by_idx ON public.attendance USING btree (updated_by);


--
-- Name: audit_events_payroll_entry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_events_payroll_entry_idx ON public.audit_events USING btree (payroll_entry_id, created_at DESC);


--
-- Name: audit_events_resource_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_events_resource_idx ON public.audit_events USING btree (resource_type, resource_id, created_at DESC);


--
-- Name: audit_log_actor_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_actor_idx ON public.audit_log USING btree (actor);


--
-- Name: audit_log_chain_pos_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX audit_log_chain_pos_uidx ON public.audit_log USING btree (chain_pos) WHERE (chain_pos IS NOT NULL);


--
-- Name: audit_log_occurred_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_occurred_idx ON public.audit_log USING btree (occurred_at DESC);


--
-- Name: audit_log_payroll_entry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_payroll_entry_idx ON public.audit_log USING btree (payroll_entry_id);


--
-- Name: audit_log_record_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_record_idx ON public.audit_log USING btree (table_name, record_id);


--
-- Name: audit_log_source_event_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX audit_log_source_event_uidx ON public.audit_log USING btree (source_event_id) WHERE (source_event_id IS NOT NULL);


--
-- Name: audit_log_table_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_table_time_idx ON public.audit_log USING btree (table_name, occurred_at DESC);


--
-- Name: candidatures_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX candidatures_created_by_idx ON public.candidatures USING btree (created_by);


--
-- Name: collective_agreements_name_ci_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX collective_agreements_name_ci_uq ON public.collective_agreements USING btree (lower(TRIM(BOTH FROM name)));


--
-- Name: collective_agreements_updated_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX collective_agreements_updated_by_idx ON public.collective_agreements USING btree (updated_by);


--
-- Name: companies_collective_agreement_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX companies_collective_agreement_idx ON public.companies USING btree (collective_agreement_code);


--
-- Name: compliance_findings_entity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX compliance_findings_entity_idx ON public.compliance_findings USING btree (entity, entity_id);


--
-- Name: compliance_findings_open_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX compliance_findings_open_idx ON public.compliance_findings USING btree (rule_id) WHERE (resolved_on IS NULL);


--
-- Name: compliance_findings_open_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX compliance_findings_open_uniq ON public.compliance_findings USING btree (rule_id, entity_id) WHERE (resolved_on IS NULL);


--
-- Name: compliance_findings_waived_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX compliance_findings_waived_idx ON public.compliance_findings USING btree (waived_by);


--
-- Name: contract_types_label_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contract_types_label_uq ON public.contract_types USING btree (lower(TRIM(BOTH FROM label)));


--
-- Name: contract_types_updated_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contract_types_updated_by_idx ON public.contract_types USING btree (updated_by);


--
-- Name: contribution_payments_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contribution_payments_created_by_idx ON public.contribution_payments USING btree (created_by);


--
-- Name: delegate_seats_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX delegate_seats_source_idx ON public.delegate_seats USING btree (source_code);


--
-- Name: departments_head_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX departments_head_idx ON public.departments USING btree (head_employee_id);


--
-- Name: departments_parent_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX departments_parent_idx ON public.departments USING btree (parent_id);


--
-- Name: designations_name_ci_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX designations_name_ci_uq ON public.designations USING btree (lower(TRIM(BOTH FROM name)));


--
-- Name: designations_updated_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX designations_updated_by_idx ON public.designations USING btree (updated_by);


--
-- Name: document_requirements_section_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_requirements_section_idx ON public.document_requirements USING btree (section_code, sort_order);


--
-- Name: document_reviews_document_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_reviews_document_idx ON public.document_reviews USING btree (document_id, reviewed_at DESC);


--
-- Name: document_versions_document_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_versions_document_idx ON public.document_versions USING btree (document_id, version_number DESC);


--
-- Name: email_outbox_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX email_outbox_status_idx ON public.email_outbox USING btree (status, created_at) WHERE (status <> 'Envoyé'::text);


--
-- Name: employee_document_access_log_document_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_document_access_log_document_idx ON public.employee_document_access_log USING btree (document_id, accessed_at DESC);


--
-- Name: employee_documents_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_documents_employee_idx ON public.employee_documents USING btree (employee_id, created_at DESC);


--
-- Name: employee_documents_family_slot_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX employee_documents_family_slot_uidx ON public.employee_documents USING btree (employee_id, requirement_code, document_slot) WHERE (archived_at IS NULL);


--
-- Name: employee_grades_agreement_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_grades_agreement_idx ON public.employee_grades USING btree (agreement_code);


--
-- Name: employee_grades_updated_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_grades_updated_by_idx ON public.employee_grades USING btree (updated_by);


--
-- Name: employee_manager_assignments_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_manager_assignments_employee_idx ON public.employee_manager_assignments USING btree (employee_id, valid_from, valid_to);


--
-- Name: employee_manager_assignments_manager_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_manager_assignments_manager_idx ON public.employee_manager_assignments USING btree (manager_employee_id, valid_from, valid_to);


--
-- Name: employee_module_data_module_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_module_data_module_idx ON public.employee_module_data USING btree (module_id);


--
-- Name: employee_notifications_unread_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_notifications_unread_idx ON public.employee_notifications USING btree (user_id, read_at) WHERE (read_at IS NULL);


--
-- Name: employee_notifications_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_notifications_user_idx ON public.employee_notifications USING btree (user_id, created_at DESC);


--
-- Name: employee_representatives_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_representatives_employee_idx ON public.employee_representatives USING btree (employee_id);


--
-- Name: employee_request_history_actor_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_request_history_actor_idx ON public.employee_request_history USING btree (actor_id);


--
-- Name: employee_request_history_request_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_request_history_request_idx ON public.employee_request_history USING btree (request_id, created_at DESC);


--
-- Name: employee_requests_decided_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_requests_decided_by_idx ON public.employee_requests USING btree (decided_by);


--
-- Name: employee_requests_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_requests_employee_idx ON public.employee_requests USING btree (employee_id);


--
-- Name: employee_requests_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_requests_status_idx ON public.employee_requests USING btree (status);


--
-- Name: employees_agreement_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employees_agreement_idx ON public.employees USING btree (agreement_code);


--
-- Name: employees_company_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employees_company_idx ON public.employees USING btree (company_id);


--
-- Name: employees_department_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employees_department_idx ON public.employees USING btree (department_id);


--
-- Name: employees_designation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employees_designation_idx ON public.employees USING btree (designation_id);


--
-- Name: employees_employment_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employees_employment_type_idx ON public.employees USING btree (employment_type);


--
-- Name: employees_exit_reason_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employees_exit_reason_idx ON public.employees USING btree (exit_reason);


--
-- Name: employees_grade_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employees_grade_idx ON public.employees USING btree (grade_id);


--
-- Name: employees_payment_mode_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employees_payment_mode_idx ON public.employees USING btree (payment_mode);


--
-- Name: employees_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employees_status_idx ON public.employees USING btree (status);


--
-- Name: exit_reasons_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX exit_reasons_source_idx ON public.exit_reasons USING btree (source_code);


--
-- Name: garnishment_scale_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX garnishment_scale_source_idx ON public.garnishment_scale USING btree (source_code);


--
-- Name: idx_candidatures_employee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_candidatures_employee_id ON public.candidatures USING btree (employee_id);


--
-- Name: idx_candidatures_job_postulation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_candidatures_job_postulation_id ON public.candidatures USING btree (job_postulation_id);


--
-- Name: idx_evaluations_employee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_evaluations_employee_id ON public.evaluations USING btree (employee_id);


--
-- Name: idx_notifications_log_processed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_log_processed ON public.notifications_log USING btree (processed_at) WHERE (processed_at IS NOT NULL);


--
-- Name: idx_notifications_log_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_log_status ON public.notifications_log USING btree (status, scheduled_at) WHERE (status = 'pending'::text);


--
-- Name: idx_notifications_log_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_log_user_id ON public.notifications_log USING btree (user_id);


--
-- Name: idx_trainings_employee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trainings_employee_id ON public.trainings USING btree (employee_id);


--
-- Name: job_postulations_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX job_postulations_created_by_idx ON public.job_postulations USING btree (created_by);


--
-- Name: job_postulations_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX job_postulations_employee_idx ON public.job_postulations USING btree (employee_id);


--
-- Name: leave_allocations_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX leave_allocations_employee_idx ON public.leave_allocations USING btree (employee_id);


--
-- Name: leave_allocations_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX leave_allocations_type_idx ON public.leave_allocations USING btree (leave_type);


--
-- Name: leave_applications_approver_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX leave_applications_approver_idx ON public.leave_applications USING btree (approver_id);


--
-- Name: leave_applications_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX leave_applications_created_by_idx ON public.leave_applications USING btree (created_by);


--
-- Name: leave_applications_dates_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX leave_applications_dates_idx ON public.leave_applications USING btree (from_date, to_date);


--
-- Name: leave_applications_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX leave_applications_employee_idx ON public.leave_applications USING btree (employee_id);


--
-- Name: leave_applications_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX leave_applications_type_idx ON public.leave_applications USING btree (leave_type);


--
-- Name: leave_approval_steps_decided_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX leave_approval_steps_decided_by_idx ON public.leave_approval_steps USING btree (decided_by);


--
-- Name: leave_approval_steps_pending_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX leave_approval_steps_pending_idx ON public.leave_approval_steps USING btree (status, due_at) WHERE (status = 'En attente'::text);


--
-- Name: loan_installments_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX loan_installments_due_idx ON public.loan_installments USING btree (due_period) WHERE (status <> 'Annulée'::text);


--
-- Name: loans_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX loans_created_by_idx ON public.loans USING btree (created_by);


--
-- Name: loans_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX loans_employee_idx ON public.loans USING btree (employee_id);


--
-- Name: loans_request_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX loans_request_idx ON public.loans USING btree (request_id);


--
-- Name: module_activation_enabled_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX module_activation_enabled_by_idx ON public.module_activation USING btree (enabled_by);


--
-- Name: module_parameter_value_entered_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX module_parameter_value_entered_by_idx ON public.module_parameter_value USING btree (entered_by);


--
-- Name: notice_scales_agreement_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notice_scales_agreement_idx ON public.notice_scales USING btree (agreement_code);


--
-- Name: notice_scales_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notice_scales_source_idx ON public.notice_scales USING btree (source_code);


--
-- Name: org_positions_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX org_positions_created_by_idx ON public.org_positions USING btree (created_by);


--
-- Name: org_positions_designation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX org_positions_designation_idx ON public.org_positions USING btree (designation_id);


--
-- Name: org_relations_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX org_relations_created_by_idx ON public.org_relations USING btree (created_by);


--
-- Name: org_relations_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX org_relations_employee_idx ON public.org_relations USING btree (employee_id);


--
-- Name: org_relations_related_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX org_relations_related_idx ON public.org_relations USING btree (related_employee_id);


--
-- Name: overtime_rates_legal_min_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX overtime_rates_legal_min_source_idx ON public.overtime_rates USING btree (legal_min_source);


--
-- Name: overtime_rates_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX overtime_rates_source_idx ON public.overtime_rates USING btree (source_code);


--
-- Name: payment_modes_label_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX payment_modes_label_uq ON public.payment_modes USING btree (lower(TRIM(BOTH FROM label)));


--
-- Name: payment_modes_updated_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payment_modes_updated_by_idx ON public.payment_modes USING btree (updated_by);


--
-- Name: payroll_anomalies_employee_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_anomalies_employee_id_idx ON public.payroll_anomalies USING btree (employee_id);


--
-- Name: payroll_anomalies_entry_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_anomalies_entry_status_idx ON public.payroll_anomalies USING btree (payroll_entry_id, status);


--
-- Name: payroll_approvals_entry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_approvals_entry_idx ON public.payroll_approvals USING btree (payroll_entry_id, created_at DESC);


--
-- Name: payroll_approvals_entry_role_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX payroll_approvals_entry_role_idx ON public.payroll_approvals USING btree (payroll_entry_id, role) WHERE (decision = 'approuvée'::text);


--
-- Name: payroll_corrections_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_corrections_created_by_idx ON public.payroll_corrections USING btree (created_by);


--
-- Name: payroll_corrections_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_corrections_employee_idx ON public.payroll_corrections USING btree (employee_id);


--
-- Name: payroll_corrections_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_corrections_status_idx ON public.payroll_corrections USING btree (status, source_period);


--
-- Name: payroll_entries_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_entries_created_by_idx ON public.payroll_entries USING btree (created_by);


--
-- Name: payroll_entries_period_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_entries_period_id_idx ON public.payroll_entries USING btree (period_id);


--
-- Name: payroll_entries_submitted_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_entries_submitted_by_idx ON public.payroll_entries USING btree (submitted_by);


--
-- Name: payroll_entries_unique_period; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX payroll_entries_unique_period ON public.payroll_entries USING btree (company_id, period_start) WHERE (status <> 'Annulée'::text);


--
-- Name: payroll_inputs_period_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_inputs_period_idx ON public.payroll_inputs USING btree (period);


--
-- Name: payroll_periods_company_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_periods_company_status_idx ON public.payroll_periods USING btree (company_id, status);


--
-- Name: payroll_periods_locked_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_periods_locked_by_idx ON public.payroll_periods USING btree (locked_by);


--
-- Name: payroll_snapshots_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_snapshots_created_by_idx ON public.payroll_snapshots USING btree (created_by);


--
-- Name: recurring_pay_items_component_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recurring_pay_items_component_idx ON public.recurring_pay_items USING btree (component_code);


--
-- Name: recurring_pay_items_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recurring_pay_items_created_by_idx ON public.recurring_pay_items USING btree (created_by);


--
-- Name: recurring_pay_items_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recurring_pay_items_employee_idx ON public.recurring_pay_items USING btree (employee_id);


--
-- Name: refresh_tokens_hash_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_tokens_hash_idx ON public.refresh_tokens USING btree (token_hash);


--
-- Name: refresh_tokens_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_tokens_user_idx ON public.refresh_tokens USING btree (user_id);


--
-- Name: salary_payments_paid_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX salary_payments_paid_by_idx ON public.salary_payments USING btree (paid_by);


--
-- Name: salary_payments_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX salary_payments_status_idx ON public.salary_payments USING btree (status);


--
-- Name: salary_slip_details_component_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX salary_slip_details_component_idx ON public.salary_slip_details USING btree (component_code);


--
-- Name: salary_slip_details_slip_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX salary_slip_details_slip_idx ON public.salary_slip_details USING btree (salary_slip_id);


--
-- Name: salary_slips_employee_period_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX salary_slips_employee_period_idx ON public.salary_slips USING btree (employee_id, period_start) WHERE (status = 'Validé'::text);


--
-- Name: salary_slips_entry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX salary_slips_entry_idx ON public.salary_slips USING btree (payroll_entry_id);


--
-- Name: salary_slips_period_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX salary_slips_period_idx ON public.salary_slips USING btree (period_start);


--
-- Name: salary_slips_unique_period; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX salary_slips_unique_period ON public.salary_slips USING btree (employee_id, period_start) WHERE (status <> 'Annulé'::text);


--
-- Name: salary_structure_components_component_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX salary_structure_components_component_idx ON public.salary_structure_components USING btree (component_code);


--
-- Name: severance_scales_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX severance_scales_source_idx ON public.severance_scales USING btree (source_code);


--
-- Name: shift_assignments_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shift_assignments_code_idx ON public.shift_assignments USING btree (shift_code);


--
-- Name: shift_assignments_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shift_assignments_date_idx ON public.shift_assignments USING btree (work_date);


--
-- Name: shift_assignments_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shift_assignments_employee_idx ON public.shift_assignments USING btree (employee_id);


--
-- Name: shift_assignments_post_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shift_assignments_post_idx ON public.shift_assignments USING btree (post_id);


--
-- Name: ssa_structure_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ssa_structure_idx ON public.salary_structure_assignments USING btree (structure_id);


--
-- Name: statutory_notice_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX statutory_notice_source_idx ON public.statutory_notice USING btree (source_code);


--
-- Name: team_members_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX team_members_employee_idx ON public.team_members USING btree (employee_id);


--
-- Name: teams_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX teams_created_by_idx ON public.teams USING btree (created_by);


--
-- Name: teams_lead_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX teams_lead_idx ON public.teams USING btree (lead_employee_id);


--
-- Name: trainings_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trainings_created_by_idx ON public.trainings USING btree (created_by);


--
-- Name: trainings_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trainings_employee_idx ON public.trainings USING btree (employee_id);


--
-- Name: work_posts_name_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX work_posts_name_uq ON public.work_posts USING btree (lower(TRIM(BOTH FROM name)));


--
-- Name: loan_balances _RETURN; Type: RULE; Schema: public; Owner: -
--

CREATE OR REPLACE VIEW public.loan_balances WITH (security_invoker='true') AS
 SELECT l.id AS loan_id,
    l.employee_id,
    l.label,
    l.principal,
    l.status,
    COALESCE(sum(i.amount) FILTER (WHERE (i.status = 'Retenue'::text)), (0)::numeric) AS retenu,
    COALESCE(sum(i.amount) FILTER (WHERE (i.status = 'Prévue'::text)), (0)::numeric) AS restant,
    min(i.due_period) FILTER (WHERE (i.status = 'Prévue'::text)) AS prochaine_echeance
   FROM (public.loans l
     LEFT JOIN public.loan_installments i ON ((i.loan_id = l.id)))
  GROUP BY l.id;


--
-- Name: v_salary_slip_ytd _RETURN; Type: RULE; Schema: public; Owner: -
--

CREATE OR REPLACE VIEW public.v_salary_slip_ytd WITH (security_invoker='true') AS
 SELECT s.id AS salary_slip_id,
    s.employee_id,
    s.period_start,
    (s.gross_pay + COALESCE(sum(p.gross_pay), (0)::numeric)) AS ytd_gross,
    (s.income_tax + COALESCE(sum(p.income_tax), (0)::numeric)) AS ytd_income_tax,
    (s.trimf + COALESCE(sum(p.trimf), (0)::numeric)) AS ytd_trimf,
    (s.leave_provision + COALESCE(sum(p.leave_provision), (0)::numeric)) AS ytd_leave_provision,
    ((COALESCE((((s.calculation -> 'totals'::text) ->> 'ipres_rg_employee'::text))::numeric, (0)::numeric) + COALESCE((((s.calculation -> 'totals'::text) ->> 'ipres_rg_employer'::text))::numeric, (0)::numeric)) + COALESCE(sum((COALESCE((((p.calculation -> 'totals'::text) ->> 'ipres_rg_employee'::text))::numeric, (0)::numeric) + COALESCE((((p.calculation -> 'totals'::text) ->> 'ipres_rg_employer'::text))::numeric, (0)::numeric))), (0)::numeric)) AS ytd_ipres_rg,
    ((COALESCE((((s.calculation -> 'totals'::text) ->> 'ipres_rc_employee'::text))::numeric, (0)::numeric) + COALESCE((((s.calculation -> 'totals'::text) ->> 'ipres_rc_employer'::text))::numeric, (0)::numeric)) + COALESCE(sum((COALESCE((((p.calculation -> 'totals'::text) ->> 'ipres_rc_employee'::text))::numeric, (0)::numeric) + COALESCE((((p.calculation -> 'totals'::text) ->> 'ipres_rc_employer'::text))::numeric, (0)::numeric))), (0)::numeric)) AS ytd_ipres_rc,
    (s.net_pay + COALESCE(sum(p.net_pay), (0)::numeric)) AS ytd_net_pay,
    (s.payroll_cost + COALESCE(sum(p.payroll_cost), (0)::numeric)) AS ytd_payroll_cost,
    (s.precarity_provision + COALESCE(sum(p.precarity_provision), (0)::numeric)) AS ytd_precarity_provision
   FROM (public.salary_slips s
     LEFT JOIN public.salary_slips p ON (((p.employee_id = s.employee_id) AND (p.status = 'Validé'::text) AND (p.period_start >= (date_trunc('year'::text, (s.period_start)::timestamp with time zone))::date) AND (p.period_start < s.period_start))))
  WHERE (s.status <> 'Annulé'::text)
  GROUP BY s.id;


--
-- Name: additional_salaries additional_salaries_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER additional_salaries_audit AFTER INSERT OR DELETE OR UPDATE ON public.additional_salaries FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: app_parameters app_parameters_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER app_parameters_audit AFTER INSERT OR DELETE OR UPDATE ON public.app_parameters FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: approval_delegations approval_delegations_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER approval_delegations_audit AFTER INSERT OR DELETE OR UPDATE ON public.approval_delegations FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: attendance attendance_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER attendance_audit AFTER INSERT OR DELETE OR UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: attendance attendance_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER attendance_touch BEFORE INSERT OR UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.attendance_touch();


--
-- Name: audit_events audit_events_to_log_ai; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_events_to_log_ai AFTER INSERT ON public.audit_events FOR EACH ROW EXECUTE FUNCTION public.audit_events_to_log();


--
-- Name: audit_log audit_log_chain_bi; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_log_chain_bi BEFORE INSERT ON public.audit_log FOR EACH ROW EXECUTE FUNCTION public.audit_log_chain();


--
-- Name: audit_log audit_log_immutable_bud; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_log_immutable_bud BEFORE DELETE OR UPDATE ON public.audit_log FOR EACH ROW EXECUTE FUNCTION public.audit_log_immutable();


--
-- Name: collective_agreements collective_agreements_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER collective_agreements_audit AFTER INSERT OR DELETE OR UPDATE ON public.collective_agreements FOR EACH ROW EXECUTE FUNCTION public.reference_audit();


--
-- Name: collective_agreements collective_agreements_guard_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER collective_agreements_guard_delete BEFORE DELETE ON public.collective_agreements FOR EACH ROW EXECUTE FUNCTION public.reference_guard_delete();


--
-- Name: collective_agreements collective_agreements_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER collective_agreements_touch BEFORE INSERT OR UPDATE ON public.collective_agreements FOR EACH ROW EXECUTE FUNCTION public.reference_touch();


--
-- Name: companies companies_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER companies_audit AFTER INSERT OR DELETE OR UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: contract_types contract_types_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER contract_types_audit AFTER INSERT OR DELETE OR UPDATE ON public.contract_types FOR EACH ROW EXECUTE FUNCTION public.reference_audit();


--
-- Name: contract_types contract_types_guard_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER contract_types_guard_delete BEFORE DELETE ON public.contract_types FOR EACH ROW EXECUTE FUNCTION public.reference_guard_delete();


--
-- Name: contract_types contract_types_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER contract_types_touch BEFORE INSERT OR UPDATE ON public.contract_types FOR EACH ROW EXECUTE FUNCTION public.reference_touch();


--
-- Name: departments departments_no_cycle; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departments_no_cycle BEFORE INSERT OR UPDATE OF parent_id ON public.departments FOR EACH ROW EXECUTE FUNCTION public.org_unit_no_cycle();


--
-- Name: designations designations_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER designations_audit AFTER INSERT OR DELETE OR UPDATE ON public.designations FOR EACH ROW EXECUTE FUNCTION public.reference_audit();


--
-- Name: designations designations_guard_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER designations_guard_delete BEFORE DELETE ON public.designations FOR EACH ROW EXECUTE FUNCTION public.reference_guard_delete();


--
-- Name: designations designations_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER designations_touch BEFORE INSERT OR UPDATE ON public.designations FOR EACH ROW EXECUTE FUNCTION public.reference_touch();


--
-- Name: document_requirements document_requirements_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER document_requirements_audit AFTER INSERT OR DELETE OR UPDATE ON public.document_requirements FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: employee_documents employee_documents_family_slot_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER employee_documents_family_slot_guard BEFORE INSERT OR UPDATE OF employee_id, requirement_code, document_slot ON public.employee_documents FOR EACH ROW EXECUTE FUNCTION public.validate_employee_document_family_slot();


--
-- Name: employee_grades employee_grades_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER employee_grades_audit AFTER INSERT OR DELETE OR UPDATE ON public.employee_grades FOR EACH ROW EXECUTE FUNCTION public.reference_audit();


--
-- Name: employee_grades employee_grades_guard_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER employee_grades_guard_delete BEFORE DELETE ON public.employee_grades FOR EACH ROW EXECUTE FUNCTION public.reference_guard_delete();


--
-- Name: employee_grades employee_grades_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER employee_grades_touch BEFORE INSERT OR UPDATE ON public.employee_grades FOR EACH ROW EXECUTE FUNCTION public.reference_touch();


--
-- Name: employee_manager_assignments employee_manager_assignments_no_cycle; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER employee_manager_assignments_no_cycle BEFORE INSERT OR UPDATE ON public.employee_manager_assignments FOR EACH ROW EXECUTE FUNCTION public.org_prevent_cycle();


--
-- Name: employee_manager_assignments employee_manager_assignments_no_overlap; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER employee_manager_assignments_no_overlap BEFORE INSERT OR UPDATE ON public.employee_manager_assignments FOR EACH ROW EXECUTE FUNCTION public.prevent_manager_assignment_overlap();


--
-- Name: employee_module_data employee_module_data_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER employee_module_data_audit AFTER INSERT OR DELETE OR UPDATE ON public.employee_module_data FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: employee_requests employee_requests_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER employee_requests_audit AFTER INSERT OR DELETE OR UPDATE ON public.employee_requests FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: employees employees_assign_number; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER employees_assign_number BEFORE INSERT ON public.employees FOR EACH ROW EXECUTE FUNCTION public.employees_assign_number();


--
-- Name: employees employees_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER employees_audit AFTER INSERT OR DELETE OR UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: employees employees_lock_number; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER employees_lock_number BEFORE UPDATE OF employee_number ON public.employees FOR EACH ROW EXECUTE FUNCTION public.employees_lock_number();


--
-- Name: employees employees_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER employees_updated_at BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: ir_family_reductions ir_family_reductions_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ir_family_reductions_audit AFTER INSERT OR DELETE OR UPDATE ON public.ir_family_reductions FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: leave_applications leave_applications_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER leave_applications_audit AFTER INSERT OR DELETE OR UPDATE ON public.leave_applications FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: leave_applications leave_applications_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER leave_applications_updated_at BEFORE UPDATE ON public.leave_applications FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: leave_applications leave_decision_guard_bu; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER leave_decision_guard_bu BEFORE UPDATE OF status ON public.leave_applications FOR EACH ROW EXECUTE FUNCTION public.leave_decision_guard();


--
-- Name: leave_applications leave_steps_init_ai; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER leave_steps_init_ai AFTER INSERT ON public.leave_applications FOR EACH ROW EXECUTE FUNCTION public.leave_steps_init();


--
-- Name: leave_types leave_types_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER leave_types_audit AFTER INSERT OR DELETE OR UPDATE ON public.leave_types FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: loans loans_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER loans_audit AFTER INSERT OR DELETE OR UPDATE ON public.loans FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: module_activation module_activation_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER module_activation_audit AFTER INSERT OR DELETE OR UPDATE ON public.module_activation FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: module_activation module_activation_stamp; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER module_activation_stamp BEFORE INSERT OR UPDATE ON public.module_activation FOR EACH ROW EXECUTE FUNCTION public.module_activation_stamp();


--
-- Name: module_manifest module_manifest_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER module_manifest_audit AFTER INSERT OR DELETE OR UPDATE ON public.module_manifest FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: module_parameter_value module_parameter_value_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER module_parameter_value_audit AFTER INSERT OR DELETE OR UPDATE ON public.module_parameter_value FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: org_relations org_relations_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER org_relations_audit AFTER INSERT OR DELETE OR UPDATE ON public.org_relations FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: org_relations org_relations_no_overlap_biu; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER org_relations_no_overlap_biu BEFORE INSERT OR UPDATE ON public.org_relations FOR EACH ROW EXECUTE FUNCTION public.org_relations_no_overlap();


--
-- Name: payment_modes payment_modes_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payment_modes_audit AFTER INSERT OR DELETE OR UPDATE ON public.payment_modes FOR EACH ROW EXECUTE FUNCTION public.reference_audit();


--
-- Name: payment_modes payment_modes_guard_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payment_modes_guard_delete BEFORE DELETE ON public.payment_modes FOR EACH ROW EXECUTE FUNCTION public.reference_guard_delete();


--
-- Name: payment_modes payment_modes_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payment_modes_touch BEFORE INSERT OR UPDATE ON public.payment_modes FOR EACH ROW EXECUTE FUNCTION public.reference_touch();


--
-- Name: payroll_corrections payroll_corrections_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payroll_corrections_audit AFTER INSERT OR DELETE OR UPDATE ON public.payroll_corrections FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: payroll_entries payroll_entries_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payroll_entries_audit AFTER INSERT OR DELETE OR UPDATE ON public.payroll_entries FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: payroll_entries payroll_entries_closed_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payroll_entries_closed_guard BEFORE DELETE OR UPDATE ON public.payroll_entries FOR EACH ROW EXECUTE FUNCTION public.prevent_closed_payroll_mutation();


--
-- Name: payroll_entries payroll_entries_period_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payroll_entries_period_guard BEFORE INSERT OR UPDATE OF status ON public.payroll_entries FOR EACH ROW EXECUTE FUNCTION public.payroll_entry_period_guard();


--
-- Name: payroll_entries payroll_entries_transition_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payroll_entries_transition_guard BEFORE INSERT OR UPDATE ON public.payroll_entries FOR EACH ROW EXECUTE FUNCTION public.guard_payroll_status_transition();


--
-- Name: payroll_entries payroll_entries_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payroll_entries_updated_at BEFORE UPDATE ON public.payroll_entries FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: payroll_inputs payroll_inputs_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payroll_inputs_audit AFTER INSERT OR DELETE OR UPDATE ON public.payroll_inputs FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: payroll_inputs payroll_inputs_closed_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payroll_inputs_closed_guard BEFORE INSERT OR DELETE OR UPDATE ON public.payroll_inputs FOR EACH ROW EXECUTE FUNCTION public.prevent_closed_period_data_mutation();


--
-- Name: payroll_inputs payroll_inputs_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payroll_inputs_updated_at BEFORE UPDATE ON public.payroll_inputs FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: payroll_periods payroll_periods_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payroll_periods_audit AFTER INSERT OR DELETE OR UPDATE ON public.payroll_periods FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: payroll_periods payroll_periods_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payroll_periods_updated_at BEFORE UPDATE ON public.payroll_periods FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: payroll_settings payroll_settings_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payroll_settings_audit AFTER INSERT OR DELETE OR UPDATE ON public.payroll_settings FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: payroll_entries payroll_validation_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payroll_validation_guard BEFORE UPDATE OF status ON public.payroll_entries FOR EACH ROW EXECUTE FUNCTION public.guard_payroll_validation();


--
-- Name: recurring_pay_items recurring_pay_items_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER recurring_pay_items_audit AFTER INSERT OR DELETE OR UPDATE ON public.recurring_pay_items FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: salary_components salary_components_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER salary_components_audit AFTER INSERT OR DELETE OR UPDATE ON public.salary_components FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: salary_payments salary_payments_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER salary_payments_audit AFTER INSERT OR DELETE OR UPDATE ON public.salary_payments FOR EACH ROW EXECUTE FUNCTION public.salary_payments_audit();


--
-- Name: salary_payments salary_payments_closed_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER salary_payments_closed_guard BEFORE INSERT OR DELETE OR UPDATE ON public.salary_payments FOR EACH ROW EXECUTE FUNCTION public.prevent_closed_period_data_mutation();


--
-- Name: salary_payments salary_payments_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER salary_payments_touch BEFORE INSERT OR UPDATE ON public.salary_payments FOR EACH ROW EXECUTE FUNCTION public.salary_payments_touch();


--
-- Name: salary_slips salary_slips_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER salary_slips_audit AFTER INSERT OR DELETE OR UPDATE ON public.salary_slips FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: salary_slips salary_slips_closed_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER salary_slips_closed_guard BEFORE DELETE OR UPDATE ON public.salary_slips FOR EACH ROW EXECUTE FUNCTION public.prevent_closed_payroll_mutation();


--
-- Name: salary_slips salary_slips_non_negative_net; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER salary_slips_non_negative_net BEFORE INSERT OR UPDATE OF net_pay, status ON public.salary_slips FOR EACH ROW EXECUTE FUNCTION public.salary_slip_non_negative_net();


--
-- Name: salary_slips salary_slips_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER salary_slips_updated_at BEFORE UPDATE ON public.salary_slips FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: salary_structure_assignments salary_structure_assignments_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER salary_structure_assignments_audit AFTER INSERT OR DELETE OR UPDATE ON public.salary_structure_assignments FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: salary_structure_components salary_structure_components_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER salary_structure_components_audit AFTER INSERT OR DELETE OR UPDATE ON public.salary_structure_components FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: salary_structures salary_structures_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER salary_structures_audit AFTER INSERT OR DELETE OR UPDATE ON public.salary_structures FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: shift_types shift_types_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER shift_types_audit AFTER INSERT OR DELETE OR UPDATE ON public.shift_types FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: salary_structure_assignments ssa_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ssa_updated_at BEFORE UPDATE ON public.salary_structure_assignments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: tax_slab_brackets tax_slab_brackets_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tax_slab_brackets_audit AFTER INSERT OR DELETE OR UPDATE ON public.tax_slab_brackets FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: tax_slabs tax_slabs_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tax_slabs_audit AFTER INSERT OR DELETE OR UPDATE ON public.tax_slabs FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: teams teams_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER teams_audit AFTER INSERT OR DELETE OR UPDATE ON public.teams FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: trimf_brackets trimf_brackets_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trimf_brackets_audit AFTER INSERT OR DELETE OR UPDATE ON public.trimf_brackets FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: user_roles user_roles_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER user_roles_audit AFTER INSERT OR DELETE OR UPDATE ON public.user_roles FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: work_posts work_posts_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER work_posts_audit AFTER INSERT OR DELETE OR UPDATE ON public.work_posts FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: additional_salaries additional_salaries_component_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.additional_salaries
    ADD CONSTRAINT additional_salaries_component_code_fkey FOREIGN KEY (component_code) REFERENCES public.salary_components(code) ON UPDATE CASCADE;


--
-- Name: additional_salaries additional_salaries_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.additional_salaries
    ADD CONSTRAINT additional_salaries_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: app_parameters app_parameters_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_parameters
    ADD CONSTRAINT app_parameters_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: approval_delegations approval_delegations_delegate_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_delegations
    ADD CONSTRAINT approval_delegations_delegate_user_fkey FOREIGN KEY (delegate_user) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: approval_delegations approval_delegations_delegator_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_delegations
    ADD CONSTRAINT approval_delegations_delegator_user_fkey FOREIGN KEY (delegator_user) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: attendance attendance_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: attendance attendance_leave_application_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_leave_application_id_fkey FOREIGN KEY (leave_application_id) REFERENCES public.leave_applications(id) ON DELETE SET NULL;


--
-- Name: attendance attendance_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: audit_events audit_events_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT audit_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: audit_events audit_events_payroll_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT audit_events_payroll_entry_id_fkey FOREIGN KEY (payroll_entry_id) REFERENCES public.payroll_entries(id) ON DELETE SET NULL;


--
-- Name: audit_log audit_log_actor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_actor_fkey FOREIGN KEY (actor) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: candidatures candidatures_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.candidatures
    ADD CONSTRAINT candidatures_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: candidatures candidatures_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.candidatures
    ADD CONSTRAINT candidatures_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: candidatures candidatures_job_postulation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.candidatures
    ADD CONSTRAINT candidatures_job_postulation_id_fkey FOREIGN KEY (job_postulation_id) REFERENCES public.job_postulations(id) ON DELETE CASCADE;


--
-- Name: collective_agreements collective_agreements_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collective_agreements
    ADD CONSTRAINT collective_agreements_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: companies companies_collective_agreement_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_collective_agreement_code_fkey FOREIGN KEY (collective_agreement_code) REFERENCES public.collective_agreements(code);


--
-- Name: compliance_findings compliance_findings_waived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.compliance_findings
    ADD CONSTRAINT compliance_findings_waived_by_fkey FOREIGN KEY (waived_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: contract_types contract_types_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_types
    ADD CONSTRAINT contract_types_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: contribution_payments contribution_payments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contribution_payments
    ADD CONSTRAINT contribution_payments_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: delegate_seats delegate_seats_source_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delegate_seats
    ADD CONSTRAINT delegate_seats_source_code_fkey FOREIGN KEY (source_code) REFERENCES public.legal_sources(code);


--
-- Name: departments departments_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: departments departments_head_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_head_employee_id_fkey FOREIGN KEY (head_employee_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: departments departments_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- Name: designations designations_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.designations
    ADD CONSTRAINT designations_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: document_reviews document_reviews_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_reviews
    ADD CONSTRAINT document_reviews_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.employee_documents(id) ON DELETE CASCADE;


--
-- Name: document_reviews document_reviews_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_reviews
    ADD CONSTRAINT document_reviews_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE RESTRICT;


--
-- Name: document_versions document_versions_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_versions
    ADD CONSTRAINT document_versions_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.employee_documents(id) ON DELETE CASCADE;


--
-- Name: document_versions document_versions_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_versions
    ADD CONSTRAINT document_versions_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id) ON DELETE RESTRICT;


--
-- Name: employee_document_access_log employee_document_access_log_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_document_access_log
    ADD CONSTRAINT employee_document_access_log_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.employee_documents(id) ON DELETE CASCADE;


--
-- Name: employee_document_access_log employee_document_access_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_document_access_log
    ADD CONSTRAINT employee_document_access_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;


--
-- Name: employee_documents employee_documents_archived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES auth.users(id);


--
-- Name: employee_documents employee_documents_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;


--
-- Name: employee_documents employee_documents_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: employee_documents employee_documents_requirement_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_requirement_code_fkey FOREIGN KEY (requirement_code) REFERENCES public.document_requirements(code);


--
-- Name: employee_documents employee_documents_validated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_validated_by_fkey FOREIGN KEY (validated_by) REFERENCES auth.users(id);


--
-- Name: employee_grades employee_grades_agreement_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_grades
    ADD CONSTRAINT employee_grades_agreement_code_fkey FOREIGN KEY (agreement_code) REFERENCES public.collective_agreements(code) ON UPDATE CASCADE;


--
-- Name: employee_grades employee_grades_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_grades
    ADD CONSTRAINT employee_grades_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: employee_manager_assignments employee_manager_assignments_delegated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_manager_assignments
    ADD CONSTRAINT employee_manager_assignments_delegated_by_fkey FOREIGN KEY (delegated_by) REFERENCES auth.users(id) ON DELETE RESTRICT;


--
-- Name: employee_manager_assignments employee_manager_assignments_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_manager_assignments
    ADD CONSTRAINT employee_manager_assignments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: employee_manager_assignments employee_manager_assignments_manager_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_manager_assignments
    ADD CONSTRAINT employee_manager_assignments_manager_employee_id_fkey FOREIGN KEY (manager_employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: employee_module_data employee_module_data_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_module_data
    ADD CONSTRAINT employee_module_data_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: employee_module_data employee_module_data_module_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_module_data
    ADD CONSTRAINT employee_module_data_module_id_fkey FOREIGN KEY (module_id) REFERENCES public.module_manifest(module_id) ON DELETE CASCADE;


--
-- Name: employee_notifications employee_notifications_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_notifications
    ADD CONSTRAINT employee_notifications_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.employee_requests(id) ON DELETE CASCADE;


--
-- Name: employee_notifications employee_notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_notifications
    ADD CONSTRAINT employee_notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: employee_representatives employee_representatives_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_representatives
    ADD CONSTRAINT employee_representatives_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: employee_request_history employee_request_history_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_request_history
    ADD CONSTRAINT employee_request_history_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE RESTRICT;


--
-- Name: employee_request_history employee_request_history_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_request_history
    ADD CONSTRAINT employee_request_history_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.employee_requests(id) ON DELETE CASCADE;


--
-- Name: employee_requests employee_requests_decided_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_requests
    ADD CONSTRAINT employee_requests_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: employee_requests employee_requests_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_requests
    ADD CONSTRAINT employee_requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: employees employees_agreement_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_agreement_code_fkey FOREIGN KEY (agreement_code) REFERENCES public.collective_agreements(code) ON UPDATE CASCADE;


--
-- Name: employees employees_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: employees employees_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- Name: employees employees_designation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_designation_id_fkey FOREIGN KEY (designation_id) REFERENCES public.designations(id);


--
-- Name: employees employees_employment_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_employment_type_fkey FOREIGN KEY (employment_type) REFERENCES public.contract_types(code) ON UPDATE CASCADE;


--
-- Name: employees employees_exit_reason_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_exit_reason_fk FOREIGN KEY (exit_reason) REFERENCES public.exit_reasons(code) ON UPDATE CASCADE;


--
-- Name: employees employees_grade_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_grade_id_fkey FOREIGN KEY (grade_id) REFERENCES public.employee_grades(id);


--
-- Name: employees employees_payment_mode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_payment_mode_fkey FOREIGN KEY (payment_mode) REFERENCES public.payment_modes(code) ON UPDATE CASCADE;


--
-- Name: employees employees_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: evaluations evaluations_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluations
    ADD CONSTRAINT evaluations_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: exit_reasons exit_reasons_source_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exit_reasons
    ADD CONSTRAINT exit_reasons_source_code_fkey FOREIGN KEY (source_code) REFERENCES public.legal_sources(code);


--
-- Name: garnishment_scale garnishment_scale_source_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.garnishment_scale
    ADD CONSTRAINT garnishment_scale_source_code_fkey FOREIGN KEY (source_code) REFERENCES public.legal_sources(code);


--
-- Name: ir_family_reductions ir_family_reductions_slab_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ir_family_reductions
    ADD CONSTRAINT ir_family_reductions_slab_id_fkey FOREIGN KEY (slab_id) REFERENCES public.tax_slabs(id) ON DELETE CASCADE;


--
-- Name: job_postulations job_postulations_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_postulations
    ADD CONSTRAINT job_postulations_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: job_postulations job_postulations_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_postulations
    ADD CONSTRAINT job_postulations_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: leave_allocations leave_allocations_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_allocations
    ADD CONSTRAINT leave_allocations_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: leave_allocations leave_allocations_leave_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_allocations
    ADD CONSTRAINT leave_allocations_leave_type_fkey FOREIGN KEY (leave_type) REFERENCES public.leave_types(code);


--
-- Name: leave_applications leave_applications_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: leave_applications leave_applications_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: leave_applications leave_applications_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: leave_applications leave_applications_leave_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_leave_type_fkey FOREIGN KEY (leave_type) REFERENCES public.leave_types(code);


--
-- Name: leave_approval_steps leave_approval_steps_decided_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_approval_steps
    ADD CONSTRAINT leave_approval_steps_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: leave_approval_steps leave_approval_steps_leave_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_approval_steps
    ADD CONSTRAINT leave_approval_steps_leave_id_fkey FOREIGN KEY (leave_id) REFERENCES public.leave_applications(id) ON DELETE CASCADE;


--
-- Name: loan_installments loan_installments_loan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loan_installments
    ADD CONSTRAINT loan_installments_loan_id_fkey FOREIGN KEY (loan_id) REFERENCES public.loans(id) ON DELETE CASCADE;


--
-- Name: loans loans_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: loans loans_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: loans loans_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.employee_requests(id) ON DELETE SET NULL;


--
-- Name: module_activation module_activation_enabled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_activation
    ADD CONSTRAINT module_activation_enabled_by_fkey FOREIGN KEY (enabled_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: module_activation module_activation_module_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_activation
    ADD CONSTRAINT module_activation_module_id_fkey FOREIGN KEY (module_id) REFERENCES public.module_manifest(module_id) ON DELETE RESTRICT;


--
-- Name: module_parameter_value module_parameter_value_entered_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_parameter_value
    ADD CONSTRAINT module_parameter_value_entered_by_fkey FOREIGN KEY (entered_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: module_parameter_value module_parameter_value_module_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_parameter_value
    ADD CONSTRAINT module_parameter_value_module_id_fkey FOREIGN KEY (module_id) REFERENCES public.module_manifest(module_id) ON DELETE CASCADE;


--
-- Name: notice_scales notice_scales_agreement_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notice_scales
    ADD CONSTRAINT notice_scales_agreement_code_fkey FOREIGN KEY (agreement_code) REFERENCES public.collective_agreements(code) ON UPDATE CASCADE;


--
-- Name: notice_scales notice_scales_source_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notice_scales
    ADD CONSTRAINT notice_scales_source_code_fkey FOREIGN KEY (source_code) REFERENCES public.legal_sources(code);


--
-- Name: notifications_log notifications_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications_log
    ADD CONSTRAINT notifications_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: org_positions org_positions_designation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_positions
    ADD CONSTRAINT org_positions_designation_id_fkey FOREIGN KEY (designation_id) REFERENCES public.designations(id) ON DELETE RESTRICT;


--
-- Name: org_positions org_positions_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_positions
    ADD CONSTRAINT org_positions_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.departments(id) ON DELETE CASCADE;


--
-- Name: org_relations org_relations_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_relations
    ADD CONSTRAINT org_relations_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: org_relations org_relations_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_relations
    ADD CONSTRAINT org_relations_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: org_relations org_relations_related_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_relations
    ADD CONSTRAINT org_relations_related_employee_id_fkey FOREIGN KEY (related_employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: overtime_rates overtime_rates_legal_min_source_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_rates
    ADD CONSTRAINT overtime_rates_legal_min_source_fkey FOREIGN KEY (legal_min_source) REFERENCES public.legal_sources(code);


--
-- Name: overtime_rates overtime_rates_source_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_rates
    ADD CONSTRAINT overtime_rates_source_code_fkey FOREIGN KEY (source_code) REFERENCES public.legal_sources(code);


--
-- Name: payment_modes payment_modes_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_modes
    ADD CONSTRAINT payment_modes_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: payroll_anomalies payroll_anomalies_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_anomalies
    ADD CONSTRAINT payroll_anomalies_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: payroll_anomalies payroll_anomalies_payroll_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_anomalies
    ADD CONSTRAINT payroll_anomalies_payroll_entry_id_fkey FOREIGN KEY (payroll_entry_id) REFERENCES public.payroll_entries(id) ON DELETE CASCADE;


--
-- Name: payroll_anomalies payroll_anomalies_resolved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_anomalies
    ADD CONSTRAINT payroll_anomalies_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: payroll_approvals payroll_approvals_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_approvals
    ADD CONSTRAINT payroll_approvals_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE RESTRICT;


--
-- Name: payroll_approvals payroll_approvals_payroll_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_approvals
    ADD CONSTRAINT payroll_approvals_payroll_entry_id_fkey FOREIGN KEY (payroll_entry_id) REFERENCES public.payroll_entries(id) ON DELETE CASCADE;


--
-- Name: payroll_corrections payroll_corrections_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_corrections
    ADD CONSTRAINT payroll_corrections_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: payroll_corrections payroll_corrections_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_corrections
    ADD CONSTRAINT payroll_corrections_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: payroll_entries payroll_entries_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_entries
    ADD CONSTRAINT payroll_entries_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: payroll_entries payroll_entries_closed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_entries
    ADD CONSTRAINT payroll_entries_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: payroll_entries payroll_entries_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_entries
    ADD CONSTRAINT payroll_entries_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: payroll_entries payroll_entries_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_entries
    ADD CONSTRAINT payroll_entries_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: payroll_entries payroll_entries_paid_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_entries
    ADD CONSTRAINT payroll_entries_paid_by_fkey FOREIGN KEY (paid_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: payroll_entries payroll_entries_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_entries
    ADD CONSTRAINT payroll_entries_period_id_fkey FOREIGN KEY (period_id) REFERENCES public.payroll_periods(id);


--
-- Name: payroll_entries payroll_entries_reopened_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_entries
    ADD CONSTRAINT payroll_entries_reopened_by_fkey FOREIGN KEY (reopened_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: payroll_entries payroll_entries_submitted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_entries
    ADD CONSTRAINT payroll_entries_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: payroll_inputs payroll_inputs_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_inputs
    ADD CONSTRAINT payroll_inputs_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: payroll_periods payroll_periods_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: payroll_periods payroll_periods_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: payroll_periods payroll_periods_locked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_locked_by_fkey FOREIGN KEY (locked_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: payroll_periods payroll_periods_reopened_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_reopened_by_fkey FOREIGN KEY (reopened_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: payroll_snapshots payroll_snapshots_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_snapshots
    ADD CONSTRAINT payroll_snapshots_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: payroll_snapshots payroll_snapshots_payroll_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_snapshots
    ADD CONSTRAINT payroll_snapshots_payroll_entry_id_fkey FOREIGN KEY (payroll_entry_id) REFERENCES public.payroll_entries(id) ON DELETE RESTRICT;


--
-- Name: recurring_pay_items recurring_pay_items_component_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_pay_items
    ADD CONSTRAINT recurring_pay_items_component_code_fkey FOREIGN KEY (component_code) REFERENCES public.salary_components(code);


--
-- Name: recurring_pay_items recurring_pay_items_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_pay_items
    ADD CONSTRAINT recurring_pay_items_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: recurring_pay_items recurring_pay_items_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_pay_items
    ADD CONSTRAINT recurring_pay_items_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: refresh_tokens refresh_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT refresh_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: salary_payments salary_payments_paid_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_payments
    ADD CONSTRAINT salary_payments_paid_by_fkey FOREIGN KEY (paid_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: salary_payments salary_payments_slip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_payments
    ADD CONSTRAINT salary_payments_slip_id_fkey FOREIGN KEY (slip_id) REFERENCES public.salary_slips(id) ON DELETE CASCADE;


--
-- Name: salary_slip_details salary_slip_details_component_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_slip_details
    ADD CONSTRAINT salary_slip_details_component_code_fkey FOREIGN KEY (component_code) REFERENCES public.salary_components(code) ON UPDATE CASCADE;


--
-- Name: salary_slip_details salary_slip_details_salary_slip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_slip_details
    ADD CONSTRAINT salary_slip_details_salary_slip_id_fkey FOREIGN KEY (salary_slip_id) REFERENCES public.salary_slips(id) ON DELETE CASCADE;


--
-- Name: salary_slips salary_slips_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_slips
    ADD CONSTRAINT salary_slips_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id);


--
-- Name: salary_slips salary_slips_payroll_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_slips
    ADD CONSTRAINT salary_slips_payroll_entry_id_fkey FOREIGN KEY (payroll_entry_id) REFERENCES public.payroll_entries(id) ON DELETE CASCADE;


--
-- Name: salary_structure_assignments salary_structure_assignments_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_structure_assignments
    ADD CONSTRAINT salary_structure_assignments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: salary_structure_assignments salary_structure_assignments_structure_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_structure_assignments
    ADD CONSTRAINT salary_structure_assignments_structure_id_fkey FOREIGN KEY (structure_id) REFERENCES public.salary_structures(id);


--
-- Name: salary_structure_components salary_structure_components_component_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_structure_components
    ADD CONSTRAINT salary_structure_components_component_code_fkey FOREIGN KEY (component_code) REFERENCES public.salary_components(code) ON UPDATE CASCADE;


--
-- Name: salary_structure_components salary_structure_components_structure_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_structure_components
    ADD CONSTRAINT salary_structure_components_structure_id_fkey FOREIGN KEY (structure_id) REFERENCES public.salary_structures(id) ON DELETE CASCADE;


--
-- Name: salary_structures salary_structures_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_structures
    ADD CONSTRAINT salary_structures_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: severance_scales severance_scales_source_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.severance_scales
    ADD CONSTRAINT severance_scales_source_code_fkey FOREIGN KEY (source_code) REFERENCES public.legal_sources(code);


--
-- Name: shift_assignments shift_assignments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: shift_assignments shift_assignments_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: shift_assignments shift_assignments_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.work_posts(id) ON DELETE SET NULL;


--
-- Name: shift_assignments shift_assignments_shift_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_shift_code_fkey FOREIGN KEY (shift_code) REFERENCES public.shift_types(code);


--
-- Name: statutory_notice statutory_notice_source_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statutory_notice
    ADD CONSTRAINT statutory_notice_source_code_fkey FOREIGN KEY (source_code) REFERENCES public.legal_sources(code);


--
-- Name: tax_slab_brackets tax_slab_brackets_slab_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_slab_brackets
    ADD CONSTRAINT tax_slab_brackets_slab_id_fkey FOREIGN KEY (slab_id) REFERENCES public.tax_slabs(id) ON DELETE CASCADE;


--
-- Name: team_members team_members_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: team_members team_members_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE CASCADE;


--
-- Name: teams teams_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: teams teams_lead_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_lead_employee_id_fkey FOREIGN KEY (lead_employee_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: trainings trainings_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trainings
    ADD CONSTRAINT trainings_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: trainings trainings_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trainings
    ADD CONSTRAINT trainings_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: trimf_brackets trimf_brackets_slab_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trimf_brackets
    ADD CONSTRAINT trimf_brackets_slab_id_fkey FOREIGN KEY (slab_id) REFERENCES public.tax_slabs(id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: additional_salaries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.additional_salaries ENABLE ROW LEVEL SECURITY;

--
-- Name: additional_salaries additional_salaries_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY additional_salaries_del ON public.additional_salaries FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: additional_salaries additional_salaries_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY additional_salaries_ins ON public.additional_salaries FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: additional_salaries additional_salaries_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY additional_salaries_read ON public.additional_salaries FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: additional_salaries additional_salaries_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY additional_salaries_upd ON public.additional_salaries FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: app_parameters; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.app_parameters ENABLE ROW LEVEL SECURITY;

--
-- Name: app_parameters app_parameters_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY app_parameters_read ON public.app_parameters FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['admin'::text, 'rh'::text, 'paie'::text]) AS has_role));


--
-- Name: approval_delegations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.approval_delegations ENABLE ROW LEVEL SECURITY;

--
-- Name: approval_delegations approval_delegations_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY approval_delegations_read ON public.approval_delegations FOR SELECT TO authenticated USING (((delegator_user = ( SELECT auth.uid() AS uid)) OR (delegate_user = ( SELECT auth.uid() AS uid)) OR ( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)));


--
-- Name: attendance; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

--
-- Name: attendance attendance_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY attendance_del ON public.attendance FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: attendance attendance_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY attendance_ins ON public.attendance FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: attendance attendance_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY attendance_select ON public.attendance FOR SELECT TO authenticated USING ((( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role) OR (employee_id = ( SELECT public.my_employee_id() AS my_employee_id))));


--
-- Name: attendance attendance_select_team; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY attendance_select_team ON public.attendance FOR SELECT TO authenticated USING (( SELECT public.can_see_leave(attendance.employee_id, attendance.attendance_date) AS can_see_leave));


--
-- Name: attendance attendance_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY attendance_upd ON public.attendance FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: audit_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_events audit_events_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_events_insert ON public.audit_events FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['admin'::text, 'rh'::text, 'paie'::text]) AS has_role));


--
-- Name: audit_events audit_events_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_events_read ON public.audit_events FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['admin'::text, 'rh'::text, 'paie'::text]) AS has_role));


--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log audit_log_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_log_select ON public.audit_log FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['admin'::text, 'rh'::text]) AS has_role));


--
-- Name: candidatures; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.candidatures ENABLE ROW LEVEL SECURITY;

--
-- Name: candidatures candidatures_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY candidatures_del ON public.candidatures FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: candidatures candidatures_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY candidatures_ins ON public.candidatures FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: candidatures candidatures_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY candidatures_read ON public.candidatures FOR SELECT TO authenticated USING (((employee_id = ( SELECT public.my_employee_id() AS my_employee_id)) OR ( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)));


--
-- Name: candidatures candidatures_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY candidatures_upd ON public.candidatures FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: collective_agreements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.collective_agreements ENABLE ROW LEVEL SECURITY;

--
-- Name: collective_agreements collective_agreements_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY collective_agreements_del ON public.collective_agreements FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: collective_agreements collective_agreements_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY collective_agreements_ins ON public.collective_agreements FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: collective_agreements collective_agreements_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY collective_agreements_read ON public.collective_agreements FOR SELECT TO authenticated USING (true);


--
-- Name: collective_agreements collective_agreements_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY collective_agreements_upd ON public.collective_agreements FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: companies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

--
-- Name: companies companies_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY companies_del ON public.companies FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: companies companies_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY companies_ins ON public.companies FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: companies companies_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY companies_read ON public.companies FOR SELECT TO authenticated USING (true);


--
-- Name: companies companies_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY companies_upd ON public.companies FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: compliance_findings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.compliance_findings ENABLE ROW LEVEL SECURITY;

--
-- Name: compliance_findings compliance_findings_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY compliance_findings_del ON public.compliance_findings FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: compliance_findings compliance_findings_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY compliance_findings_ins ON public.compliance_findings FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: compliance_findings compliance_findings_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY compliance_findings_read ON public.compliance_findings FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: compliance_findings compliance_findings_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY compliance_findings_upd ON public.compliance_findings FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: contract_types; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contract_types ENABLE ROW LEVEL SECURITY;

--
-- Name: contract_types contract_types_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contract_types_del ON public.contract_types FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: contract_types contract_types_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contract_types_ins ON public.contract_types FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: contract_types contract_types_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contract_types_read ON public.contract_types FOR SELECT TO authenticated USING (true);


--
-- Name: contract_types contract_types_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contract_types_upd ON public.contract_types FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: contribution_payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contribution_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: contribution_payments contribution_payments_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contribution_payments_del ON public.contribution_payments FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: contribution_payments contribution_payments_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contribution_payments_ins ON public.contribution_payments FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: contribution_payments contribution_payments_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contribution_payments_read ON public.contribution_payments FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: contribution_payments contribution_payments_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contribution_payments_upd ON public.contribution_payments FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: delegate_seats; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.delegate_seats ENABLE ROW LEVEL SECURITY;

--
-- Name: delegate_seats delegate_seats_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY delegate_seats_del ON public.delegate_seats FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: delegate_seats delegate_seats_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY delegate_seats_ins ON public.delegate_seats FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: delegate_seats delegate_seats_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY delegate_seats_read ON public.delegate_seats FOR SELECT TO authenticated USING (true);


--
-- Name: delegate_seats delegate_seats_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY delegate_seats_upd ON public.delegate_seats FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: departments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;

--
-- Name: departments departments_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY departments_del ON public.departments FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: departments departments_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY departments_ins ON public.departments FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: departments departments_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY departments_read ON public.departments FOR SELECT TO authenticated USING (true);


--
-- Name: departments departments_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY departments_upd ON public.departments FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: designations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.designations ENABLE ROW LEVEL SECURITY;

--
-- Name: designations designations_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY designations_del ON public.designations FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: designations designations_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY designations_ins ON public.designations FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: designations designations_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY designations_read ON public.designations FOR SELECT TO authenticated USING (true);


--
-- Name: designations designations_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY designations_upd ON public.designations FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: document_requirements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.document_requirements ENABLE ROW LEVEL SECURITY;

--
-- Name: document_requirements document_requirements_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY document_requirements_read ON public.document_requirements FOR SELECT TO authenticated USING ((active OR ( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)));


--
-- Name: document_reviews; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.document_reviews ENABLE ROW LEVEL SECURITY;

--
-- Name: document_reviews document_reviews_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY document_reviews_select ON public.document_reviews FOR SELECT TO authenticated USING ((( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR (EXISTS ( SELECT 1
   FROM public.employee_documents d
  WHERE ((d.id = document_reviews.document_id) AND (d.employee_id = ( SELECT public.my_employee_id() AS my_employee_id)))))));


--
-- Name: document_versions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.document_versions ENABLE ROW LEVEL SECURITY;

--
-- Name: document_versions document_versions_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY document_versions_insert ON public.document_versions FOR INSERT TO authenticated WITH CHECK (((uploaded_by = ( SELECT auth.uid() AS uid)) AND (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR (EXISTS ( SELECT 1
   FROM public.employee_documents d
  WHERE ((d.id = document_versions.document_id) AND (d.employee_id = ( SELECT public.my_employee_id() AS my_employee_id))))))));


--
-- Name: document_versions document_versions_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY document_versions_select ON public.document_versions FOR SELECT TO authenticated USING ((( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR (EXISTS ( SELECT 1
   FROM public.employee_documents d
  WHERE ((d.id = document_versions.document_id) AND (d.employee_id = ( SELECT public.my_employee_id() AS my_employee_id)))))));


--
-- Name: email_outbox; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.email_outbox ENABLE ROW LEVEL SECURITY;

--
-- Name: email_outbox email_outbox_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY email_outbox_read ON public.email_outbox FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employee_document_access_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_document_access_log ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_document_access_log employee_document_access_log_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_document_access_log_select ON public.employee_document_access_log FOR SELECT TO authenticated USING ((( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR (user_id = ( SELECT auth.uid() AS uid))));


--
-- Name: employee_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_documents ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_documents employee_documents_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_documents_insert ON public.employee_documents FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employee_documents employee_documents_insert_self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_documents_insert_self ON public.employee_documents FOR INSERT TO authenticated WITH CHECK (((employee_id = ( SELECT public.my_employee_id() AS my_employee_id)) AND (created_by = ( SELECT auth.uid() AS uid))));


--
-- Name: employee_documents employee_documents_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_documents_select ON public.employee_documents FOR SELECT TO authenticated USING ((( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR (employee_id = ( SELECT public.my_employee_id() AS my_employee_id))));


--
-- Name: employee_documents employee_documents_update_rh; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_documents_update_rh ON public.employee_documents FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employee_grades; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_grades ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_grades employee_grades_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_grades_del ON public.employee_grades FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employee_grades employee_grades_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_grades_ins ON public.employee_grades FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employee_grades employee_grades_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_grades_read ON public.employee_grades FOR SELECT TO authenticated USING (true);


--
-- Name: employee_grades employee_grades_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_grades_upd ON public.employee_grades FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employee_manager_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_manager_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_manager_assignments employee_manager_assignments_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_manager_assignments_del ON public.employee_manager_assignments FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employee_manager_assignments employee_manager_assignments_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_manager_assignments_ins ON public.employee_manager_assignments FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employee_manager_assignments employee_manager_assignments_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_manager_assignments_select ON public.employee_manager_assignments FOR SELECT TO authenticated USING ((( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR (( SELECT public.has_role(ARRAY['manager'::text]) AS has_role) AND (manager_employee_id = ( SELECT public.my_employee_id() AS my_employee_id)))));


--
-- Name: employee_manager_assignments employee_manager_assignments_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_manager_assignments_upd ON public.employee_manager_assignments FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employee_module_data; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_module_data ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_module_data employee_module_data_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_module_data_read ON public.employee_module_data FOR SELECT TO authenticated USING (((employee_id = ( SELECT public.my_employee_id() AS my_employee_id)) OR ( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role)));


--
-- Name: employee_module_data employee_module_data_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_module_data_write ON public.employee_module_data TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employee_notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_notifications employee_notifications_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_notifications_select ON public.employee_notifications FOR SELECT TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: employee_notifications employee_notifications_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_notifications_update ON public.employee_notifications FOR UPDATE TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: employee_representatives; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_representatives ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_representatives employee_representatives_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_representatives_del ON public.employee_representatives FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employee_representatives employee_representatives_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_representatives_ins ON public.employee_representatives FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employee_representatives employee_representatives_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_representatives_read ON public.employee_representatives FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: employee_representatives employee_representatives_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_representatives_upd ON public.employee_representatives FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employee_request_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_request_history ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_request_history employee_request_history_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_request_history_read ON public.employee_request_history FOR SELECT TO authenticated USING ((( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR (EXISTS ( SELECT 1
   FROM public.employee_requests er
  WHERE ((er.id = employee_request_history.request_id) AND ((er.employee_id = ( SELECT public.my_employee_id() AS my_employee_id)) OR ( SELECT public.manager_has_employee(er.employee_id) AS manager_has_employee)))))));


--
-- Name: employee_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_requests employee_requests_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_requests_ins ON public.employee_requests FOR INSERT TO authenticated WITH CHECK (((employee_id = ( SELECT public.my_employee_id() AS my_employee_id)) AND (status = 'Ouverte'::text) AND (decided_by IS NULL)));


--
-- Name: employee_requests employee_requests_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_requests_read ON public.employee_requests FOR SELECT TO authenticated USING ((( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR (employee_id = ( SELECT public.my_employee_id() AS my_employee_id)) OR ( SELECT public.manager_has_employee(employee_requests.employee_id) AS manager_has_employee)));


--
-- Name: employees; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

--
-- Name: employees employees_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employees_del ON public.employees FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employees employees_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employees_ins ON public.employees FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: employees employees_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employees_select ON public.employees FOR SELECT TO authenticated USING ((( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role) OR (user_id = ( SELECT auth.uid() AS uid)) OR ( SELECT public.manager_has_employee(employees.id) AS manager_has_employee)));


--
-- Name: employees employees_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employees_upd ON public.employees FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: evaluations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.evaluations ENABLE ROW LEVEL SECURITY;

--
-- Name: evaluations evaluations_rh; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY evaluations_rh ON public.evaluations TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: exit_reasons; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.exit_reasons ENABLE ROW LEVEL SECURITY;

--
-- Name: exit_reasons exit_reasons_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY exit_reasons_del ON public.exit_reasons FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: exit_reasons exit_reasons_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY exit_reasons_ins ON public.exit_reasons FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: exit_reasons exit_reasons_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY exit_reasons_read ON public.exit_reasons FOR SELECT TO authenticated USING (true);


--
-- Name: exit_reasons exit_reasons_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY exit_reasons_upd ON public.exit_reasons FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: garnishment_scale; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.garnishment_scale ENABLE ROW LEVEL SECURITY;

--
-- Name: garnishment_scale garnishment_scale_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY garnishment_scale_del ON public.garnishment_scale FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: garnishment_scale garnishment_scale_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY garnishment_scale_ins ON public.garnishment_scale FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: garnishment_scale garnishment_scale_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY garnishment_scale_read ON public.garnishment_scale FOR SELECT TO authenticated USING (true);


--
-- Name: garnishment_scale garnishment_scale_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY garnishment_scale_upd ON public.garnishment_scale FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: ir_family_reductions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ir_family_reductions ENABLE ROW LEVEL SECURITY;

--
-- Name: ir_family_reductions ir_family_reductions_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ir_family_reductions_del ON public.ir_family_reductions FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: ir_family_reductions ir_family_reductions_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ir_family_reductions_ins ON public.ir_family_reductions FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: ir_family_reductions ir_family_reductions_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ir_family_reductions_read ON public.ir_family_reductions FOR SELECT TO authenticated USING (true);


--
-- Name: ir_family_reductions ir_family_reductions_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ir_family_reductions_upd ON public.ir_family_reductions FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: job_postulations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.job_postulations ENABLE ROW LEVEL SECURITY;

--
-- Name: job_postulations job_postulations_rh; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY job_postulations_rh ON public.job_postulations TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: leave_allocations leave_alloc_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_alloc_del ON public.leave_allocations FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: leave_allocations leave_alloc_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_alloc_ins ON public.leave_allocations FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: leave_allocations leave_alloc_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_alloc_select ON public.leave_allocations FOR SELECT TO authenticated USING ((( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role) OR (employee_id = ( SELECT public.my_employee_id() AS my_employee_id))));


--
-- Name: leave_allocations leave_alloc_select_team; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_alloc_select_team ON public.leave_allocations FOR SELECT TO authenticated USING (( SELECT public.can_see_leave(leave_allocations.employee_id, CURRENT_DATE) AS can_see_leave));


--
-- Name: leave_allocations leave_alloc_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_alloc_upd ON public.leave_allocations FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: leave_allocations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_allocations ENABLE ROW LEVEL SECURITY;

--
-- Name: leave_applications leave_app_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_app_del ON public.leave_applications FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: leave_applications leave_app_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_app_ins ON public.leave_applications FOR INSERT TO authenticated WITH CHECK ((( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR ((employee_id = ( SELECT public.my_employee_id() AS my_employee_id)) AND (status = 'Ouverte'::text))));


--
-- Name: leave_applications leave_app_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_app_select ON public.leave_applications FOR SELECT TO authenticated USING ((( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role) OR (employee_id = ( SELECT public.my_employee_id() AS my_employee_id))));


--
-- Name: leave_applications leave_app_select_team; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_app_select_team ON public.leave_applications FOR SELECT TO authenticated USING (( SELECT public.can_see_leave(leave_applications.employee_id, leave_applications.from_date) AS can_see_leave));


--
-- Name: leave_applications leave_app_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_app_upd ON public.leave_applications FOR UPDATE TO authenticated USING ((( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR ((employee_id = ( SELECT public.my_employee_id() AS my_employee_id)) AND (status = 'Ouverte'::text)))) WITH CHECK ((( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR ((employee_id = ( SELECT public.my_employee_id() AS my_employee_id)) AND (status = ANY (ARRAY['Ouverte'::text, 'Annulée'::text])))));


--
-- Name: leave_applications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_applications ENABLE ROW LEVEL SECURITY;

--
-- Name: leave_approval_steps; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_approval_steps ENABLE ROW LEVEL SECURITY;

--
-- Name: leave_approval_steps leave_steps_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_steps_read ON public.leave_approval_steps FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.leave_applications l
  WHERE (l.id = leave_approval_steps.leave_id))));


--
-- Name: leave_types; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_types ENABLE ROW LEVEL SECURITY;

--
-- Name: leave_types leave_types_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_types_del ON public.leave_types FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: leave_types leave_types_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_types_ins ON public.leave_types FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: leave_types leave_types_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_types_read ON public.leave_types FOR SELECT TO authenticated USING (true);


--
-- Name: leave_types leave_types_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_types_upd ON public.leave_types FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: legal_sources; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.legal_sources ENABLE ROW LEVEL SECURITY;

--
-- Name: legal_sources legal_sources_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY legal_sources_del ON public.legal_sources FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: legal_sources legal_sources_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY legal_sources_ins ON public.legal_sources FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: legal_sources legal_sources_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY legal_sources_read ON public.legal_sources FOR SELECT TO authenticated USING (true);


--
-- Name: legal_sources legal_sources_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY legal_sources_upd ON public.legal_sources FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: loan_installments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.loan_installments ENABLE ROW LEVEL SECURITY;

--
-- Name: loan_installments loan_installments_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY loan_installments_read ON public.loan_installments FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: loans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.loans ENABLE ROW LEVEL SECURITY;

--
-- Name: loans loans_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY loans_read ON public.loans FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: module_activation; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.module_activation ENABLE ROW LEVEL SECURITY;

--
-- Name: module_activation module_activation_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY module_activation_read ON public.module_activation FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: module_activation module_activation_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY module_activation_write ON public.module_activation TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: module_manifest; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.module_manifest ENABLE ROW LEVEL SECURITY;

--
-- Name: module_manifest module_manifest_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY module_manifest_read ON public.module_manifest FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: module_manifest module_manifest_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY module_manifest_write ON public.module_manifest TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: module_parameter_value; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.module_parameter_value ENABLE ROW LEVEL SECURITY;

--
-- Name: module_parameter_value module_parameter_value_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY module_parameter_value_read ON public.module_parameter_value FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: module_parameter_value module_parameter_value_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY module_parameter_value_write ON public.module_parameter_value TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: notice_scales; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notice_scales ENABLE ROW LEVEL SECURITY;

--
-- Name: notice_scales notice_scales_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notice_scales_del ON public.notice_scales FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: notice_scales notice_scales_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notice_scales_ins ON public.notice_scales FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: notice_scales notice_scales_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notice_scales_read ON public.notice_scales FOR SELECT TO authenticated USING (true);


--
-- Name: notice_scales notice_scales_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notice_scales_upd ON public.notice_scales FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: notifications_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications_log ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications_log notifications_log_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_log_del ON public.notifications_log FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: notifications_log notifications_log_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_log_ins ON public.notifications_log FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: notifications_log notifications_log_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_log_read ON public.notifications_log FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR ( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role)));


--
-- Name: notifications_log notifications_log_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_log_upd ON public.notifications_log FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: org_positions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.org_positions ENABLE ROW LEVEL SECURITY;

--
-- Name: org_positions org_positions_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_positions_select ON public.org_positions FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: org_relations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.org_relations ENABLE ROW LEVEL SECURITY;

--
-- Name: org_relations org_relations_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_relations_read ON public.org_relations FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: overtime_rates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.overtime_rates ENABLE ROW LEVEL SECURITY;

--
-- Name: overtime_rates overtime_rates_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY overtime_rates_del ON public.overtime_rates FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: overtime_rates overtime_rates_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY overtime_rates_ins ON public.overtime_rates FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: overtime_rates overtime_rates_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY overtime_rates_read ON public.overtime_rates FOR SELECT TO authenticated USING (true);


--
-- Name: overtime_rates overtime_rates_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY overtime_rates_upd ON public.overtime_rates FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: payment_modes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment_modes ENABLE ROW LEVEL SECURITY;

--
-- Name: payment_modes payment_modes_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payment_modes_del ON public.payment_modes FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: payment_modes payment_modes_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payment_modes_ins ON public.payment_modes FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: payment_modes payment_modes_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payment_modes_read ON public.payment_modes FOR SELECT TO authenticated USING (true);


--
-- Name: payment_modes payment_modes_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payment_modes_upd ON public.payment_modes FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: payroll_anomalies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_anomalies ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_anomalies payroll_anomalies_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_anomalies_read ON public.payroll_anomalies FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: payroll_anomalies payroll_anomalies_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_anomalies_write ON public.payroll_anomalies TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: payroll_approvals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_approvals ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_approvals payroll_approvals_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_approvals_insert ON public.payroll_approvals FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: payroll_approvals payroll_approvals_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_approvals_read ON public.payroll_approvals FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: payroll_corrections; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_corrections ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_corrections payroll_corrections_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_corrections_read ON public.payroll_corrections FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: payroll_entries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_entries payroll_entries_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_entries_del ON public.payroll_entries FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: payroll_entries payroll_entries_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_entries_ins ON public.payroll_entries FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: payroll_entries payroll_entries_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_entries_read ON public.payroll_entries FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: payroll_entries payroll_entries_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_entries_upd ON public.payroll_entries FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: payroll_inputs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_inputs ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_inputs payroll_inputs_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_inputs_del ON public.payroll_inputs FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: payroll_inputs payroll_inputs_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_inputs_ins ON public.payroll_inputs FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: payroll_inputs payroll_inputs_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_inputs_read ON public.payroll_inputs FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: payroll_inputs payroll_inputs_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_inputs_upd ON public.payroll_inputs FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: payroll_periods; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_periods ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_periods payroll_periods_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_periods_read ON public.payroll_periods FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: payroll_periods payroll_periods_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_periods_write ON public.payroll_periods TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: payroll_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_settings payroll_settings_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_settings_del ON public.payroll_settings FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: payroll_settings payroll_settings_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_settings_ins ON public.payroll_settings FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: payroll_settings payroll_settings_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_settings_read ON public.payroll_settings FOR SELECT TO authenticated USING (true);


--
-- Name: payroll_settings payroll_settings_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_settings_upd ON public.payroll_settings FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: payroll_snapshots; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_snapshots ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_snapshots payroll_snapshots_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_snapshots_read ON public.payroll_snapshots FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: recurring_pay_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recurring_pay_items ENABLE ROW LEVEL SECURITY;

--
-- Name: recurring_pay_items recurring_pay_items_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY recurring_pay_items_read ON public.recurring_pay_items FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: recurring_pay_items recurring_pay_items_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY recurring_pay_items_write ON public.recurring_pay_items TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: refresh_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.refresh_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: salary_components; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.salary_components ENABLE ROW LEVEL SECURITY;

--
-- Name: salary_components salary_components_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_components_del ON public.salary_components FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: salary_components salary_components_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_components_ins ON public.salary_components FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: salary_components salary_components_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_components_read ON public.salary_components FOR SELECT TO authenticated USING (true);


--
-- Name: salary_components salary_components_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_components_upd ON public.salary_components FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: salary_payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.salary_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: salary_payments salary_payments_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_payments_access ON public.salary_payments TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: salary_payments salary_payments_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_payments_del ON public.salary_payments FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['admin'::text]) AS has_role));


--
-- Name: salary_payments salary_payments_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_payments_ins ON public.salary_payments FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: salary_payments salary_payments_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_payments_read ON public.salary_payments FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: salary_payments salary_payments_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_payments_upd ON public.salary_payments FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: salary_slip_details; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.salary_slip_details ENABLE ROW LEVEL SECURITY;

--
-- Name: salary_slips; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.salary_slips ENABLE ROW LEVEL SECURITY;

--
-- Name: salary_slips salary_slips_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_slips_del ON public.salary_slips FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: salary_slips salary_slips_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_slips_ins ON public.salary_slips FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: salary_slips salary_slips_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_slips_select ON public.salary_slips FOR SELECT TO authenticated USING ((( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role) OR ((employee_id = ( SELECT public.my_employee_id() AS my_employee_id)) AND (status = 'Validé'::text))));


--
-- Name: salary_slips salary_slips_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_slips_upd ON public.salary_slips FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: salary_structure_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.salary_structure_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: salary_structure_assignments salary_structure_assignments_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_structure_assignments_del ON public.salary_structure_assignments FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: salary_structure_assignments salary_structure_assignments_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_structure_assignments_ins ON public.salary_structure_assignments FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: salary_structure_assignments salary_structure_assignments_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_structure_assignments_read ON public.salary_structure_assignments FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: salary_structure_assignments salary_structure_assignments_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_structure_assignments_upd ON public.salary_structure_assignments FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: salary_structure_components; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.salary_structure_components ENABLE ROW LEVEL SECURITY;

--
-- Name: salary_structure_components salary_structure_components_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_structure_components_del ON public.salary_structure_components FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: salary_structure_components salary_structure_components_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_structure_components_ins ON public.salary_structure_components FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: salary_structure_components salary_structure_components_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_structure_components_read ON public.salary_structure_components FOR SELECT TO authenticated USING (true);


--
-- Name: salary_structure_components salary_structure_components_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_structure_components_upd ON public.salary_structure_components FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: salary_structures; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.salary_structures ENABLE ROW LEVEL SECURITY;

--
-- Name: salary_structures salary_structures_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_structures_del ON public.salary_structures FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: salary_structures salary_structures_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_structures_ins ON public.salary_structures FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: salary_structures salary_structures_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_structures_read ON public.salary_structures FOR SELECT TO authenticated USING (true);


--
-- Name: salary_structures salary_structures_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_structures_upd ON public.salary_structures FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: severance_scales; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.severance_scales ENABLE ROW LEVEL SECURITY;

--
-- Name: severance_scales severance_scales_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY severance_scales_del ON public.severance_scales FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: severance_scales severance_scales_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY severance_scales_ins ON public.severance_scales FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: severance_scales severance_scales_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY severance_scales_read ON public.severance_scales FOR SELECT TO authenticated USING (true);


--
-- Name: severance_scales severance_scales_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY severance_scales_upd ON public.severance_scales FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: shift_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shift_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: shift_assignments shift_assignments_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shift_assignments_access ON public.shift_assignments TO authenticated USING ((( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR (employee_id = ( SELECT public.my_employee_id() AS my_employee_id)))) WITH CHECK ((( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR (employee_id = ( SELECT public.my_employee_id() AS my_employee_id))));


--
-- Name: shift_types; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shift_types ENABLE ROW LEVEL SECURITY;

--
-- Name: shift_types shift_types_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shift_types_admin ON public.shift_types TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: shift_types shift_types_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shift_types_read ON public.shift_types FOR SELECT TO authenticated USING (true);


--
-- Name: salary_slip_details slip_details_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY slip_details_del ON public.salary_slip_details FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: salary_slip_details slip_details_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY slip_details_ins ON public.salary_slip_details FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: salary_slip_details slip_details_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY slip_details_select ON public.salary_slip_details FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.salary_slips s
  WHERE (s.id = salary_slip_details.salary_slip_id))));


--
-- Name: salary_slip_details slip_details_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY slip_details_upd ON public.salary_slip_details FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text, 'rh'::text]) AS has_role));


--
-- Name: statutory_notice; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.statutory_notice ENABLE ROW LEVEL SECURITY;

--
-- Name: statutory_notice statutory_notice_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY statutory_notice_del ON public.statutory_notice FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: statutory_notice statutory_notice_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY statutory_notice_ins ON public.statutory_notice FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: statutory_notice statutory_notice_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY statutory_notice_read ON public.statutory_notice FOR SELECT TO authenticated USING (true);


--
-- Name: statutory_notice statutory_notice_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY statutory_notice_upd ON public.statutory_notice FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: tax_slab_brackets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tax_slab_brackets ENABLE ROW LEVEL SECURITY;

--
-- Name: tax_slab_brackets tax_slab_brackets_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tax_slab_brackets_del ON public.tax_slab_brackets FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: tax_slab_brackets tax_slab_brackets_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tax_slab_brackets_ins ON public.tax_slab_brackets FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: tax_slab_brackets tax_slab_brackets_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tax_slab_brackets_read ON public.tax_slab_brackets FOR SELECT TO authenticated USING (true);


--
-- Name: tax_slab_brackets tax_slab_brackets_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tax_slab_brackets_upd ON public.tax_slab_brackets FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: tax_slabs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tax_slabs ENABLE ROW LEVEL SECURITY;

--
-- Name: tax_slabs tax_slabs_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tax_slabs_del ON public.tax_slabs FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: tax_slabs tax_slabs_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tax_slabs_ins ON public.tax_slabs FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: tax_slabs tax_slabs_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tax_slabs_read ON public.tax_slabs FOR SELECT TO authenticated USING (true);


--
-- Name: tax_slabs tax_slabs_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tax_slabs_upd ON public.tax_slabs FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: team_members; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.team_members ENABLE ROW LEVEL SECURITY;

--
-- Name: team_members team_members_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY team_members_read ON public.team_members FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: teams; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;

--
-- Name: teams teams_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY teams_read ON public.teams FOR SELECT TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: trainings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.trainings ENABLE ROW LEVEL SECURITY;

--
-- Name: trainings trainings_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainings_del ON public.trainings FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: trainings trainings_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainings_ins ON public.trainings FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: trainings trainings_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainings_read ON public.trainings FOR SELECT TO authenticated USING (((employee_id = ( SELECT public.my_employee_id() AS my_employee_id)) OR ( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)));


--
-- Name: trainings trainings_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainings_upd ON public.trainings FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: trimf_brackets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.trimf_brackets ENABLE ROW LEVEL SECURITY;

--
-- Name: trimf_brackets trimf_brackets_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trimf_brackets_del ON public.trimf_brackets FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: trimf_brackets trimf_brackets_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trimf_brackets_ins ON public.trimf_brackets FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: trimf_brackets trimf_brackets_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trimf_brackets_read ON public.trimf_brackets FOR SELECT TO authenticated USING (true);


--
-- Name: trimf_brackets trimf_brackets_upd; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trimf_brackets_upd ON public.trimf_brackets FOR UPDATE TO authenticated USING (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['paie'::text]) AS has_role));


--
-- Name: user_roles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

--
-- Name: user_roles user_roles_admin_del; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_roles_admin_del ON public.user_roles FOR DELETE TO authenticated USING (( SELECT public.has_role(ARRAY['admin'::text]) AS has_role));


--
-- Name: user_roles user_roles_admin_ins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_roles_admin_ins ON public.user_roles FOR INSERT TO authenticated WITH CHECK (( SELECT public.has_role(ARRAY['admin'::text]) AS has_role));


--
-- Name: user_roles user_roles_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_roles_select ON public.user_roles FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR ( SELECT public.has_role(ARRAY['admin'::text]) AS has_role)));


--
-- Name: work_posts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_posts ENABLE ROW LEVEL SECURITY;

--
-- Name: work_posts work_posts_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY work_posts_admin ON public.work_posts TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: work_posts work_posts_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY work_posts_read ON public.work_posts FOR SELECT TO authenticated USING (true);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION admin_change_employee_number(p_employee_id uuid, p_new_number text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_change_employee_number(p_employee_id uuid, p_new_number text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_change_employee_number(p_employee_id uuid, p_new_number text, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.admin_change_employee_number(p_employee_id uuid, p_new_number text, p_reason text) TO service_role;


--
-- Name: FUNCTION admin_link_employee(p_user_id uuid, p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_link_employee(p_user_id uuid, p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_link_employee(p_user_id uuid, p_employee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.admin_link_employee(p_user_id uuid, p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION admin_list_users(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_list_users() FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_list_users() TO authenticated;
GRANT ALL ON FUNCTION public.admin_list_users() TO service_role;


--
-- Name: FUNCTION apply_period_adjustments(p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.apply_period_adjustments(p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.apply_period_adjustments(p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.apply_period_adjustments(p_payroll_entry_id uuid) TO service_role;


--
-- Name: TABLE employee_documents; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.employee_documents TO authenticated;


--
-- Name: FUNCTION archive_employee_document(p_document_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.archive_employee_document(p_document_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.archive_employee_document(p_document_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.archive_employee_document(p_document_id uuid) TO service_role;


--
-- Name: FUNCTION assert_declaration_embauche(p_entry uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assert_declaration_embauche(p_entry uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assert_declaration_embauche(p_entry uuid) TO authenticated;


--
-- Name: TABLE employee_manager_assignments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.employee_manager_assignments TO authenticated;


--
-- Name: FUNCTION assign_manager_employee(p_manager_employee_id uuid, p_employee_id uuid, p_valid_from date, p_valid_to date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assign_manager_employee(p_manager_employee_id uuid, p_employee_id uuid, p_valid_from date, p_valid_to date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assign_manager_employee(p_manager_employee_id uuid, p_employee_id uuid, p_valid_from date, p_valid_to date) TO authenticated;
GRANT ALL ON FUNCTION public.assign_manager_employee(p_manager_employee_id uuid, p_employee_id uuid, p_valid_from date, p_valid_to date) TO service_role;


--
-- Name: FUNCTION attendance_touch(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.attendance_touch() FROM PUBLIC;
GRANT ALL ON FUNCTION public.attendance_touch() TO authenticated;
GRANT ALL ON FUNCTION public.attendance_touch() TO service_role;


--
-- Name: FUNCTION audit_events_to_log(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.audit_events_to_log() FROM PUBLIC;
GRANT ALL ON FUNCTION public.audit_events_to_log() TO authenticated;
GRANT ALL ON FUNCTION public.audit_events_to_log() TO service_role;


--
-- Name: FUNCTION audit_log_chain(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.audit_log_chain() FROM PUBLIC;
GRANT ALL ON FUNCTION public.audit_log_chain() TO authenticated;
GRANT ALL ON FUNCTION public.audit_log_chain() TO service_role;


--
-- Name: FUNCTION audit_log_immutable(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.audit_log_immutable() FROM PUBLIC;
GRANT ALL ON FUNCTION public.audit_log_immutable() TO authenticated;
GRANT ALL ON FUNCTION public.audit_log_immutable() TO service_role;


--
-- Name: TABLE audit_log; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.audit_log TO authenticated;


--
-- Name: FUNCTION audit_row_hash(p_prev text, r public.audit_log); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.audit_row_hash(p_prev text, r public.audit_log) FROM PUBLIC;
GRANT ALL ON FUNCTION public.audit_row_hash(p_prev text, r public.audit_log) TO authenticated;
GRANT ALL ON FUNCTION public.audit_row_hash(p_prev text, r public.audit_log) TO service_role;


--
-- Name: FUNCTION audit_verify(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.audit_verify() FROM PUBLIC;
GRANT ALL ON FUNCTION public.audit_verify() TO authenticated;
GRANT ALL ON FUNCTION public.audit_verify() TO service_role;


--
-- Name: FUNCTION business_audit(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.business_audit() FROM PUBLIC;
GRANT ALL ON FUNCTION public.business_audit() TO authenticated;
GRANT ALL ON FUNCTION public.business_audit() TO service_role;


--
-- Name: FUNCTION calculate_salary_slip(p_employee_id uuid, p_period_start date, p_period_end date, p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.calculate_salary_slip(p_employee_id uuid, p_period_start date, p_period_end date, p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.calculate_salary_slip(p_employee_id uuid, p_period_start date, p_period_end date, p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_salary_slip(p_employee_id uuid, p_period_start date, p_period_end date, p_payroll_entry_id uuid) TO service_role;


--
-- Name: FUNCTION can_see_leave(p_employee uuid, p_on date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.can_see_leave(p_employee uuid, p_on date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.can_see_leave(p_employee uuid, p_on date) TO authenticated;
GRANT ALL ON FUNCTION public.can_see_leave(p_employee uuid, p_on date) TO service_role;


--
-- Name: FUNCTION cancel_loan(p_loan_id uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_loan(p_loan_id uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_loan(p_loan_id uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_loan(p_loan_id uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION cancel_my_request(p_request_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_my_request(p_request_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_my_request(p_request_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_my_request(p_request_id uuid) TO service_role;


--
-- Name: FUNCTION cancel_payroll_correction(p_correction_id uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_payroll_correction(p_correction_id uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_payroll_correction(p_correction_id uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_payroll_correction(p_correction_id uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION cancel_payroll_entry(p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_payroll_entry(p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_payroll_entry(p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_payroll_entry(p_payroll_entry_id uuid) TO service_role;


--
-- Name: FUNCTION cash_breakdown(p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cash_breakdown(p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cash_breakdown(p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.cash_breakdown(p_payroll_entry_id uuid) TO service_role;


--
-- Name: FUNCTION certificat_travail(p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.certificat_travail(p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.certificat_travail(p_employee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.certificat_travail(p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION check_journal_imputation(p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.check_journal_imputation(p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.check_journal_imputation(p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.check_journal_imputation(p_payroll_entry_id uuid) TO service_role;


--
-- Name: FUNCTION claim_first_admin(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.claim_first_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION public.claim_first_admin() TO authenticated;
GRANT ALL ON FUNCTION public.claim_first_admin() TO service_role;


--
-- Name: FUNCTION close_manager_assignment(p_assignment_id uuid, p_valid_to date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.close_manager_assignment(p_assignment_id uuid, p_valid_to date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.close_manager_assignment(p_assignment_id uuid, p_valid_to date) TO authenticated;
GRANT ALL ON FUNCTION public.close_manager_assignment(p_assignment_id uuid, p_valid_to date) TO service_role;


--
-- Name: FUNCTION compute_income_tax(p_monthly_gross numeric, p_parts numeric, p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.compute_income_tax(p_monthly_gross numeric, p_parts numeric, p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.compute_income_tax(p_monthly_gross numeric, p_parts numeric, p_date date) TO authenticated;
GRANT ALL ON FUNCTION public.compute_income_tax(p_monthly_gross numeric, p_parts numeric, p_date date) TO service_role;


--
-- Name: FUNCTION compute_salary_slip(p_employee_id uuid, p_period_start date, p_period_end date, p_sursalaire numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.compute_salary_slip(p_employee_id uuid, p_period_start date, p_period_end date, p_sursalaire numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.compute_salary_slip(p_employee_id uuid, p_period_start date, p_period_end date, p_sursalaire numeric) TO authenticated;
GRANT ALL ON FUNCTION public.compute_salary_slip(p_employee_id uuid, p_period_start date, p_period_end date, p_sursalaire numeric) TO service_role;


--
-- Name: FUNCTION compute_trimf(p_monthly_gross numeric, p_parts numeric, p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.compute_trimf(p_monthly_gross numeric, p_parts numeric, p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.compute_trimf(p_monthly_gross numeric, p_parts numeric, p_date date) TO authenticated;
GRANT ALL ON FUNCTION public.compute_trimf(p_monthly_gross numeric, p_parts numeric, p_date date) TO service_role;


--
-- Name: FUNCTION create_loan(p_employee_id uuid, p_label text, p_principal numeric, p_installments integer, p_first_period date, p_request_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_loan(p_employee_id uuid, p_label text, p_principal numeric, p_installments integer, p_first_period date, p_request_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_loan(p_employee_id uuid, p_label text, p_principal numeric, p_installments integer, p_first_period date, p_request_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.create_loan(p_employee_id uuid, p_label text, p_principal numeric, p_installments integer, p_first_period date, p_request_id uuid) TO service_role;


--
-- Name: FUNCTION create_payroll_correction(p_employee_id uuid, p_source_period date, p_kind text, p_amount numeric, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_payroll_correction(p_employee_id uuid, p_source_period date, p_kind text, p_amount numeric, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_payroll_correction(p_employee_id uuid, p_source_period date, p_kind text, p_amount numeric, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.create_payroll_correction(p_employee_id uuid, p_source_period date, p_kind text, p_amount numeric, p_reason text) TO service_role;


--
-- Name: FUNCTION create_payroll_snapshot(p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_payroll_snapshot(p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_payroll_snapshot(p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.create_payroll_snapshot(p_payroll_entry_id uuid) TO service_role;


--
-- Name: TABLE employee_requests; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.employee_requests TO authenticated;


--
-- Name: FUNCTION decide_employee_request(p_request_id uuid, p_status text, p_note text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.decide_employee_request(p_request_id uuid, p_status text, p_note text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.decide_employee_request(p_request_id uuid, p_status text, p_note text) TO authenticated;
GRANT ALL ON FUNCTION public.decide_employee_request(p_request_id uuid, p_status text, p_note text) TO service_role;


--
-- Name: FUNCTION decide_leave(p_leave_id uuid, p_decision text, p_note text, p_step smallint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.decide_leave(p_leave_id uuid, p_decision text, p_note text, p_step smallint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.decide_leave(p_leave_id uuid, p_decision text, p_note text, p_step smallint) TO authenticated;
GRANT ALL ON FUNCTION public.decide_leave(p_leave_id uuid, p_decision text, p_note text, p_step smallint) TO service_role;


--
-- Name: FUNCTION delegate_approvals(p_delegate_user uuid, p_from date, p_to date, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.delegate_approvals(p_delegate_user uuid, p_from date, p_to date, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delegate_approvals(p_delegate_user uuid, p_from date, p_to date, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.delegate_approvals(p_delegate_user uuid, p_from date, p_to date, p_reason text) TO service_role;


--
-- Name: FUNCTION delete_payroll_entry(p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.delete_payroll_entry(p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_payroll_entry(p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_payroll_entry(p_payroll_entry_id uuid) TO service_role;


--
-- Name: FUNCTION deroger_constat(p_id uuid, p_motif text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.deroger_constat(p_id uuid, p_motif text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.deroger_constat(p_id uuid, p_motif text) TO authenticated;


--
-- Name: FUNCTION detecter_conformite(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.detecter_conformite() FROM PUBLIC;
GRANT ALL ON FUNCTION public.detecter_conformite() TO authenticated;


--
-- Name: FUNCTION echeance_cotisations(p_month date, p_headcount integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.echeance_cotisations(p_month date, p_headcount integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.echeance_cotisations(p_month date, p_headcount integer) TO authenticated;
GRANT ALL ON FUNCTION public.echeance_cotisations(p_month date, p_headcount integer) TO service_role;


--
-- Name: FUNCTION employees_assign_number(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.employees_assign_number() FROM PUBLIC;
GRANT ALL ON FUNCTION public.employees_assign_number() TO authenticated;
GRANT ALL ON FUNCTION public.employees_assign_number() TO service_role;


--
-- Name: FUNCTION employees_lock_number(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.employees_lock_number() FROM PUBLIC;
GRANT ALL ON FUNCTION public.employees_lock_number() TO authenticated;
GRANT ALL ON FUNCTION public.employees_lock_number() TO service_role;


--
-- Name: FUNCTION escalate_overdue_leave_steps(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escalate_overdue_leave_steps() FROM PUBLIC;
GRANT ALL ON FUNCTION public.escalate_overdue_leave_steps() TO authenticated;
GRANT ALL ON FUNCTION public.escalate_overdue_leave_steps() TO service_role;


--
-- Name: FUNCTION etat_dgid(p_employee_id uuid, p_period_end date, p_type text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.etat_dgid(p_employee_id uuid, p_period_end date, p_type text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.etat_dgid(p_employee_id uuid, p_period_end date, p_type text) TO authenticated;
GRANT ALL ON FUNCTION public.etat_dgid(p_employee_id uuid, p_period_end date, p_type text) TO service_role;


--
-- Name: FUNCTION excel_datedif(p_start date, p_end date, p_unit text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.excel_datedif(p_start date, p_end date, p_unit text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.excel_datedif(p_start date, p_end date, p_unit text) TO authenticated;
GRANT ALL ON FUNCTION public.excel_datedif(p_start date, p_end date, p_unit text) TO service_role;


--
-- Name: FUNCTION export_ipres_css(p_employee_id uuid, p_period_end date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.export_ipres_css(p_employee_id uuid, p_period_end date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.export_ipres_css(p_employee_id uuid, p_period_end date) TO authenticated;
GRANT ALL ON FUNCTION public.export_ipres_css(p_employee_id uuid, p_period_end date) TO service_role;


--
-- Name: FUNCTION export_payroll_journal(p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.export_payroll_journal(p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.export_payroll_journal(p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.export_payroll_journal(p_payroll_entry_id uuid) TO service_role;


--
-- Name: FUNCTION generate_rotation(p_employee_ids uuid[], p_from date, p_to date, p_pattern text[], p_offset integer, p_post_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.generate_rotation(p_employee_ids uuid[], p_from date, p_to date, p_pattern text[], p_offset integer, p_post_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.generate_rotation(p_employee_ids uuid[], p_from date, p_to date, p_pattern text[], p_offset integer, p_post_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.generate_rotation(p_employee_ids uuid[], p_from date, p_to date, p_pattern text[], p_offset integer, p_post_id uuid) TO service_role;


--
-- Name: FUNCTION get_loan_max_rate(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_loan_max_rate() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_loan_max_rate() TO authenticated;
GRANT ALL ON FUNCTION public.get_loan_max_rate() TO service_role;


--
-- Name: FUNCTION guard_payroll_status_transition(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.guard_payroll_status_transition() FROM PUBLIC;
GRANT ALL ON FUNCTION public.guard_payroll_status_transition() TO authenticated;
GRANT ALL ON FUNCTION public.guard_payroll_status_transition() TO service_role;


--
-- Name: FUNCTION guard_payroll_validation(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.guard_payroll_validation() FROM PUBLIC;
GRANT ALL ON FUNCTION public.guard_payroll_validation() TO authenticated;
GRANT ALL ON FUNCTION public.guard_payroll_validation() TO service_role;


--
-- Name: FUNCTION has_role(p_roles text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.has_role(p_roles text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.has_role(p_roles text[]) TO authenticated;
GRANT ALL ON FUNCTION public.has_role(p_roles text[]) TO service_role;


--
-- Name: FUNCTION hr_analytics(p_months integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.hr_analytics(p_months integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.hr_analytics(p_months integer) TO authenticated;
GRANT ALL ON FUNCTION public.hr_analytics(p_months integer) TO service_role;


--
-- Name: FUNCTION hr_dashboard(p_period date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.hr_dashboard(p_period date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.hr_dashboard(p_period date) TO authenticated;
GRANT ALL ON FUNCTION public.hr_dashboard(p_period date) TO service_role;


--
-- Name: FUNCTION hr_dashboard_year(p_year integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.hr_dashboard_year(p_year integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.hr_dashboard_year(p_year integer) TO authenticated;
GRANT ALL ON FUNCTION public.hr_dashboard_year(p_year integer) TO service_role;


--
-- Name: FUNCTION hs_majoration(p_code text, p_fallback numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.hs_majoration(p_code text, p_fallback numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.hs_majoration(p_code text, p_fallback numeric) TO authenticated;


--
-- Name: FUNCTION leave_decision_guard(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.leave_decision_guard() FROM PUBLIC;
GRANT ALL ON FUNCTION public.leave_decision_guard() TO authenticated;
GRANT ALL ON FUNCTION public.leave_decision_guard() TO service_role;


--
-- Name: FUNCTION leave_steps_init(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.leave_steps_init() FROM PUBLIC;
GRANT ALL ON FUNCTION public.leave_steps_init() TO authenticated;
GRANT ALL ON FUNCTION public.leave_steps_init() TO service_role;


--
-- Name: FUNCTION legal_alerts(p_as_of date, p_horizon_days integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.legal_alerts(p_as_of date, p_horizon_days integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.legal_alerts(p_as_of date, p_horizon_days integer) TO authenticated;
GRANT ALL ON FUNCTION public.legal_alerts(p_as_of date, p_horizon_days integer) TO service_role;


--
-- Name: FUNCTION load_module_manifest(p_manifest jsonb, p_hash text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.load_module_manifest(p_manifest jsonb, p_hash text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.load_module_manifest(p_manifest jsonb, p_hash text) TO authenticated;


--
-- Name: TABLE employee_document_access_log; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.employee_document_access_log TO authenticated;


--
-- Name: FUNCTION log_employee_document_access(p_document_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.log_employee_document_access(p_document_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.log_employee_document_access(p_document_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.log_employee_document_access(p_document_id uuid) TO service_role;


--
-- Name: FUNCTION majoration_retard_cotisations(p_amount numeric, p_due_date date, p_paid_on date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.majoration_retard_cotisations(p_amount numeric, p_due_date date, p_paid_on date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.majoration_retard_cotisations(p_amount numeric, p_due_date date, p_paid_on date) TO authenticated;
GRANT ALL ON FUNCTION public.majoration_retard_cotisations(p_amount numeric, p_due_date date, p_paid_on date) TO service_role;


--
-- Name: FUNCTION manager_has_employee(p_employee_id uuid, p_on_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.manager_has_employee(p_employee_id uuid, p_on_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.manager_has_employee(p_employee_id uuid, p_on_date date) TO authenticated;
GRANT ALL ON FUNCTION public.manager_has_employee(p_employee_id uuid, p_on_date date) TO service_role;


--
-- Name: TABLE employee_notifications; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.employee_notifications TO authenticated;


--
-- Name: FUNCTION mark_employee_notification_read(p_notification_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.mark_employee_notification_read(p_notification_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.mark_employee_notification_read(p_notification_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.mark_employee_notification_read(p_notification_id uuid) TO service_role;


--
-- Name: FUNCTION module_activation_stamp(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.module_activation_stamp() FROM PUBLIC;


--
-- Name: FUNCTION my_employee_id(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.my_employee_id() FROM PUBLIC;
GRANT ALL ON FUNCTION public.my_employee_id() TO authenticated;
GRANT ALL ON FUNCTION public.my_employee_id() TO service_role;


--
-- Name: FUNCTION my_leave_approvals(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.my_leave_approvals() FROM PUBLIC;
GRANT ALL ON FUNCTION public.my_leave_approvals() TO authenticated;
GRANT ALL ON FUNCTION public.my_leave_approvals() TO service_role;


--
-- Name: FUNCTION next_employee_number(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.next_employee_number() FROM PUBLIC;
GRANT ALL ON FUNCTION public.next_employee_number() TO authenticated;
GRANT ALL ON FUNCTION public.next_employee_number() TO service_role;


--
-- Name: TABLE leave_applications; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.leave_applications TO authenticated;


--
-- Name: FUNCTION notify_leave_approvers(p_leave public.leave_applications, p_level text, p_text text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_leave_approvers(p_leave public.leave_applications, p_level text, p_text text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_leave_approvers(p_leave public.leave_applications, p_level text, p_text text) TO authenticated;
GRANT ALL ON FUNCTION public.notify_leave_approvers(p_leave public.leave_applications, p_level text, p_text text) TO service_role;


--
-- Name: FUNCTION notify_user(p_user uuid, p_title text, p_message text, p_key text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_user(p_user uuid, p_title text, p_message text, p_key text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_user(p_user uuid, p_title text, p_message text, p_key text) TO authenticated;
GRANT ALL ON FUNCTION public.notify_user(p_user uuid, p_title text, p_message text, p_key text) TO service_role;


--
-- Name: FUNCTION org_apply_reorg(p_moves jsonb, p_from date, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_apply_reorg(p_moves jsonb, p_from date, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_apply_reorg(p_moves jsonb, p_from date, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.org_apply_reorg(p_moves jsonb, p_from date, p_reason text) TO service_role;


--
-- Name: FUNCTION org_attach_to_unit(p_employee uuid, p_unit uuid, p_link_head boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_attach_to_unit(p_employee uuid, p_unit uuid, p_link_head boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_attach_to_unit(p_employee uuid, p_unit uuid, p_link_head boolean) TO authenticated;
GRANT ALL ON FUNCTION public.org_attach_to_unit(p_employee uuid, p_unit uuid, p_link_head boolean) TO service_role;


--
-- Name: FUNCTION org_chart(p_on date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_chart(p_on date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_chart(p_on date) TO authenticated;
GRANT ALL ON FUNCTION public.org_chart(p_on date) TO service_role;


--
-- Name: FUNCTION org_delete_position(p_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_delete_position(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_delete_position(p_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.org_delete_position(p_id uuid) TO service_role;


--
-- Name: FUNCTION org_delete_unit(p_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_delete_unit(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_delete_unit(p_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.org_delete_unit(p_id uuid) TO service_role;


--
-- Name: FUNCTION org_end_relation(p_id uuid, p_end date, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_end_relation(p_id uuid, p_end date, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_end_relation(p_id uuid, p_end date, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.org_end_relation(p_id uuid, p_end date, p_reason text) TO service_role;


--
-- Name: FUNCTION org_log(p_table text, p_record uuid, p_action text, p_reason text, p_data jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_log(p_table text, p_record uuid, p_action text, p_reason text, p_data jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_log(p_table text, p_record uuid, p_action text, p_reason text, p_data jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.org_log(p_table text, p_record uuid, p_action text, p_reason text, p_data jsonb) TO service_role;


--
-- Name: FUNCTION org_log_export(p_format text, p_rows integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_log_export(p_format text, p_rows integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_log_export(p_format text, p_rows integer) TO authenticated;
GRANT ALL ON FUNCTION public.org_log_export(p_format text, p_rows integer) TO service_role;


--
-- Name: FUNCTION org_prevent_cycle(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_prevent_cycle() FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_prevent_cycle() TO authenticated;
GRANT ALL ON FUNCTION public.org_prevent_cycle() TO service_role;


--
-- Name: FUNCTION org_relations_no_overlap(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_relations_no_overlap() FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_relations_no_overlap() TO authenticated;
GRANT ALL ON FUNCTION public.org_relations_no_overlap() TO service_role;


--
-- Name: FUNCTION org_remove_team_member(p_team uuid, p_employee uuid, p_note text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_remove_team_member(p_team uuid, p_employee uuid, p_note text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_remove_team_member(p_team uuid, p_employee uuid, p_note text) TO authenticated;
GRANT ALL ON FUNCTION public.org_remove_team_member(p_team uuid, p_employee uuid, p_note text) TO service_role;


--
-- Name: FUNCTION org_require_hr(p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_require_hr(p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_require_hr(p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.org_require_hr(p_reason text) TO service_role;


--
-- Name: FUNCTION org_save_position(p_unit uuid, p_post uuid, p_headcount integer, p_note text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_save_position(p_unit uuid, p_post uuid, p_headcount integer, p_note text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_save_position(p_unit uuid, p_post uuid, p_headcount integer, p_note text) TO authenticated;
GRANT ALL ON FUNCTION public.org_save_position(p_unit uuid, p_post uuid, p_headcount integer, p_note text) TO service_role;


--
-- Name: FUNCTION org_save_post(p_name text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_save_post(p_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_save_post(p_name text) TO authenticated;
GRANT ALL ON FUNCTION public.org_save_post(p_name text) TO service_role;


--
-- Name: FUNCTION org_save_relation(p_id uuid, p_employee uuid, p_related uuid, p_type text, p_start date, p_end date, p_pct numeric, p_note text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_save_relation(p_id uuid, p_employee uuid, p_related uuid, p_type text, p_start date, p_end date, p_pct numeric, p_note text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_save_relation(p_id uuid, p_employee uuid, p_related uuid, p_type text, p_start date, p_end date, p_pct numeric, p_note text, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.org_save_relation(p_id uuid, p_employee uuid, p_related uuid, p_type text, p_start date, p_end date, p_pct numeric, p_note text, p_reason text) TO service_role;


--
-- Name: FUNCTION org_save_team(p_id uuid, p_name text, p_kind text, p_lead uuid, p_start date, p_end date, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_save_team(p_id uuid, p_name text, p_kind text, p_lead uuid, p_start date, p_end date, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_save_team(p_id uuid, p_name text, p_kind text, p_lead uuid, p_start date, p_end date, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.org_save_team(p_id uuid, p_name text, p_kind text, p_lead uuid, p_start date, p_end date, p_reason text) TO service_role;


--
-- Name: FUNCTION org_save_unit(p_id uuid, p_name text, p_kind text, p_parent uuid, p_head uuid, p_note text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_save_unit(p_id uuid, p_name text, p_kind text, p_parent uuid, p_head uuid, p_note text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_save_unit(p_id uuid, p_name text, p_kind text, p_parent uuid, p_head uuid, p_note text) TO authenticated;
GRANT ALL ON FUNCTION public.org_save_unit(p_id uuid, p_name text, p_kind text, p_parent uuid, p_head uuid, p_note text) TO service_role;


--
-- Name: FUNCTION org_set_employee_post(p_employee uuid, p_post uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_set_employee_post(p_employee uuid, p_post uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_set_employee_post(p_employee uuid, p_post uuid) TO authenticated;
GRANT ALL ON FUNCTION public.org_set_employee_post(p_employee uuid, p_post uuid) TO service_role;


--
-- Name: FUNCTION org_set_employee_unit(p_employee uuid, p_unit uuid, p_note text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_set_employee_unit(p_employee uuid, p_unit uuid, p_note text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_set_employee_unit(p_employee uuid, p_unit uuid, p_note text) TO authenticated;
GRANT ALL ON FUNCTION public.org_set_employee_unit(p_employee uuid, p_unit uuid, p_note text) TO service_role;


--
-- Name: FUNCTION org_set_manager(p_employee uuid, p_manager uuid, p_from date, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_set_manager(p_employee uuid, p_manager uuid, p_from date, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_set_manager(p_employee uuid, p_manager uuid, p_from date, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.org_set_manager(p_employee uuid, p_manager uuid, p_from date, p_reason text) TO service_role;


--
-- Name: FUNCTION org_set_team_member(p_team uuid, p_employee uuid, p_role text, p_pct numeric, p_start date, p_end date, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_set_team_member(p_team uuid, p_employee uuid, p_role text, p_pct numeric, p_start date, p_end date, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_set_team_member(p_team uuid, p_employee uuid, p_role text, p_pct numeric, p_start date, p_end date, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.org_set_team_member(p_team uuid, p_employee uuid, p_role text, p_pct numeric, p_start date, p_end date, p_reason text) TO service_role;


--
-- Name: FUNCTION org_set_unit_head(p_unit uuid, p_employee uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_set_unit_head(p_unit uuid, p_employee uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_set_unit_head(p_unit uuid, p_employee uuid) TO authenticated;
GRANT ALL ON FUNCTION public.org_set_unit_head(p_unit uuid, p_employee uuid) TO service_role;


--
-- Name: FUNCTION org_unit_no_cycle(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_unit_no_cycle() FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_unit_no_cycle() TO authenticated;
GRANT ALL ON FUNCTION public.org_unit_no_cycle() TO service_role;


--
-- Name: FUNCTION payment_export(p_payroll_entry_id uuid, p_mode text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payment_export(p_payroll_entry_id uuid, p_mode text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payment_export(p_payroll_entry_id uuid, p_mode text) TO authenticated;
GRANT ALL ON FUNCTION public.payment_export(p_payroll_entry_id uuid, p_mode text) TO service_role;


--
-- Name: FUNCTION payment_orders(p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payment_orders(p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payment_orders(p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.payment_orders(p_payroll_entry_id uuid) TO service_role;


--
-- Name: FUNCTION payment_summary(p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payment_summary(p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payment_summary(p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.payment_summary(p_payroll_entry_id uuid) TO service_role;


--
-- Name: TABLE payroll_entries; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payroll_entries TO authenticated;


--
-- Name: FUNCTION payroll_assert_separation(p_entry public.payroll_entries, p_action text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_assert_separation(p_entry public.payroll_entries, p_action text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_assert_separation(p_entry public.payroll_entries, p_action text, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.payroll_assert_separation(p_entry public.payroll_entries, p_action text, p_reason text) TO service_role;


--
-- Name: FUNCTION payroll_closing_report(p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_closing_report(p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_closing_report(p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.payroll_closing_report(p_payroll_entry_id uuid) TO service_role;


--
-- Name: FUNCTION payroll_entry_checks(p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_entry_checks(p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_entry_checks(p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.payroll_entry_checks(p_payroll_entry_id uuid) TO service_role;


--
-- Name: FUNCTION payroll_entry_comparison(p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_entry_comparison(p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_entry_comparison(p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.payroll_entry_comparison(p_payroll_entry_id uuid) TO service_role;


--
-- Name: FUNCTION payroll_entry_period_guard(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_entry_period_guard() FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_entry_period_guard() TO authenticated;
GRANT ALL ON FUNCTION public.payroll_entry_period_guard() TO service_role;


--
-- Name: TABLE payroll_settings; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payroll_settings TO authenticated;


--
-- Name: FUNCTION payroll_settings_at(p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_settings_at(p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_settings_at(p_date date) TO authenticated;
GRANT ALL ON FUNCTION public.payroll_settings_at(p_date date) TO service_role;


--
-- Name: FUNCTION payroll_snapshots_verify(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_snapshots_verify() FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_snapshots_verify() TO authenticated;
GRANT ALL ON FUNCTION public.payroll_snapshots_verify() TO service_role;


--
-- Name: FUNCTION plafond_retenues(p_assiette numeric, p_cap numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.plafond_retenues(p_assiette numeric, p_cap numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.plafond_retenues(p_assiette numeric, p_cap numeric) TO authenticated;
GRANT ALL ON FUNCTION public.plafond_retenues(p_assiette numeric, p_cap numeric) TO service_role;


--
-- Name: FUNCTION preavis_mois(p_employee_id uuid, p_on date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.preavis_mois(p_employee_id uuid, p_on date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.preavis_mois(p_employee_id uuid, p_on date) TO authenticated;


--
-- Name: FUNCTION prevent_closed_payroll_mutation(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.prevent_closed_payroll_mutation() FROM PUBLIC;
GRANT ALL ON FUNCTION public.prevent_closed_payroll_mutation() TO authenticated;
GRANT ALL ON FUNCTION public.prevent_closed_payroll_mutation() TO service_role;


--
-- Name: FUNCTION prevent_closed_period_data_mutation(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.prevent_closed_period_data_mutation() FROM PUBLIC;
GRANT ALL ON FUNCTION public.prevent_closed_period_data_mutation() TO authenticated;
GRANT ALL ON FUNCTION public.prevent_closed_period_data_mutation() TO service_role;


--
-- Name: FUNCTION prevent_manager_assignment_overlap(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.prevent_manager_assignment_overlap() FROM PUBLIC;
GRANT ALL ON FUNCTION public.prevent_manager_assignment_overlap() TO authenticated;
GRANT ALL ON FUNCTION public.prevent_manager_assignment_overlap() TO service_role;


--
-- Name: FUNCTION preview_employee_number(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.preview_employee_number() FROM PUBLIC;
GRANT ALL ON FUNCTION public.preview_employee_number() TO authenticated;
GRANT ALL ON FUNCTION public.preview_employee_number() TO service_role;


--
-- Name: FUNCTION quotite_cessible(p_assiette numeric, p_kind text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.quotite_cessible(p_assiette numeric, p_kind text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.quotite_cessible(p_assiette numeric, p_kind text) TO authenticated;
GRANT ALL ON FUNCTION public.quotite_cessible(p_assiette numeric, p_kind text) TO service_role;


--
-- Name: FUNCTION reference_audit(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reference_audit() FROM PUBLIC;
GRANT ALL ON FUNCTION public.reference_audit() TO authenticated;
GRANT ALL ON FUNCTION public.reference_audit() TO service_role;


--
-- Name: FUNCTION reference_guard_delete(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reference_guard_delete() FROM PUBLIC;
GRANT ALL ON FUNCTION public.reference_guard_delete() TO authenticated;
GRANT ALL ON FUNCTION public.reference_guard_delete() TO service_role;


--
-- Name: FUNCTION reference_touch(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reference_touch() FROM PUBLIC;
GRANT ALL ON FUNCTION public.reference_touch() TO authenticated;
GRANT ALL ON FUNCTION public.reference_touch() TO service_role;


--
-- Name: FUNCTION reference_usage(p_table text, p_key text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reference_usage(p_table text, p_key text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reference_usage(p_table text, p_key text) TO authenticated;
GRANT ALL ON FUNCTION public.reference_usage(p_table text, p_key text) TO service_role;


--
-- Name: FUNCTION reopen_payroll_entry(p_payroll_entry_id uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reopen_payroll_entry(p_payroll_entry_id uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reopen_payroll_entry(p_payroll_entry_id uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.reopen_payroll_entry(p_payroll_entry_id uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION revert_payroll_entry(p_payroll_entry_id uuid, p_reason text, p_cancel_payments boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.revert_payroll_entry(p_payroll_entry_id uuid, p_reason text, p_cancel_payments boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.revert_payroll_entry(p_payroll_entry_id uuid, p_reason text, p_cancel_payments boolean) TO authenticated;
GRANT ALL ON FUNCTION public.revert_payroll_entry(p_payroll_entry_id uuid, p_reason text, p_cancel_payments boolean) TO service_role;


--
-- Name: FUNCTION review_employee_document(p_document_id uuid, p_status text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.review_employee_document(p_document_id uuid, p_status text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.review_employee_document(p_document_id uuid, p_status text, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.review_employee_document(p_document_id uuid, p_status text, p_reason text) TO service_role;


--
-- Name: FUNCTION revoke_delegation(p_delegation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.revoke_delegation(p_delegation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.revoke_delegation(p_delegation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.revoke_delegation(p_delegation_id uuid) TO service_role;


--
-- Name: FUNCTION run_payroll_batch(p_payroll_entry_id uuid, p_employment_type text, p_employee_ids uuid[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.run_payroll_batch(p_payroll_entry_id uuid, p_employment_type text, p_employee_ids uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.run_payroll_batch(p_payroll_entry_id uuid, p_employment_type text, p_employee_ids uuid[]) TO authenticated;
GRANT ALL ON FUNCTION public.run_payroll_batch(p_payroll_entry_id uuid, p_employment_type text, p_employee_ids uuid[]) TO service_role;


--
-- Name: FUNCTION run_payroll_entry(p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.run_payroll_entry(p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.run_payroll_entry(p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.run_payroll_entry(p_payroll_entry_id uuid) TO service_role;


--
-- Name: FUNCTION salary_payments_audit(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.salary_payments_audit() FROM PUBLIC;
GRANT ALL ON FUNCTION public.salary_payments_audit() TO authenticated;
GRANT ALL ON FUNCTION public.salary_payments_audit() TO service_role;


--
-- Name: FUNCTION salary_payments_touch(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.salary_payments_touch() FROM PUBLIC;
GRANT ALL ON FUNCTION public.salary_payments_touch() TO authenticated;
GRANT ALL ON FUNCTION public.salary_payments_touch() TO service_role;


--
-- Name: FUNCTION salary_slip_explained(p_slip_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.salary_slip_explained(p_slip_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.salary_slip_explained(p_slip_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.salary_slip_explained(p_slip_id uuid) TO service_role;


--
-- Name: FUNCTION salary_slip_non_negative_net(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.salary_slip_non_negative_net() FROM PUBLIC;
GRANT ALL ON FUNCTION public.salary_slip_non_negative_net() TO authenticated;
GRANT ALL ON FUNCTION public.salary_slip_non_negative_net() TO service_role;


--
-- Name: FUNCTION set_loan_max_rate(p_rate numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_loan_max_rate(p_rate numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_loan_max_rate(p_rate numeric) TO authenticated;
GRANT ALL ON FUNCTION public.set_loan_max_rate(p_rate numeric) TO service_role;


--
-- Name: FUNCTION set_updated_at(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_updated_at() FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_updated_at() TO authenticated;
GRANT ALL ON FUNCTION public.set_updated_at() TO service_role;


--
-- Name: FUNCTION severance_coefficient(p_entry date, p_exit date, p_kind text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.severance_coefficient(p_entry date, p_exit date, p_kind text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.severance_coefficient(p_entry date, p_exit date, p_kind text) TO authenticated;
GRANT ALL ON FUNCTION public.severance_coefficient(p_entry date, p_exit date, p_kind text) TO service_role;


--
-- Name: FUNCTION solde_tout_compte(p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.solde_tout_compte(p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.solde_tout_compte(p_employee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.solde_tout_compte(p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION solve_sursalaire_for_net(p_employee_id uuid, p_period_start date, p_period_end date, p_target_net numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.solve_sursalaire_for_net(p_employee_id uuid, p_period_start date, p_period_end date, p_target_net numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.solve_sursalaire_for_net(p_employee_id uuid, p_period_start date, p_period_end date, p_target_net numeric) TO authenticated;
GRANT ALL ON FUNCTION public.solve_sursalaire_for_net(p_employee_id uuid, p_period_start date, p_period_end date, p_target_net numeric) TO service_role;


--
-- Name: FUNCTION sortie_salarie(p_employee_id uuid, p_exit_date date, p_exit_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sortie_salarie(p_employee_id uuid, p_exit_date date, p_exit_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sortie_salarie(p_employee_id uuid, p_exit_date date, p_exit_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.sortie_salarie(p_employee_id uuid, p_exit_date date, p_exit_reason text) TO service_role;


--
-- Name: FUNCTION submit_payroll_entry(p_payroll_entry_id uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.submit_payroll_entry(p_payroll_entry_id uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.submit_payroll_entry(p_payroll_entry_id uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.submit_payroll_entry(p_payroll_entry_id uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION sync_attendance_to_payroll_inputs(p_period date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sync_attendance_to_payroll_inputs(p_period date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sync_attendance_to_payroll_inputs(p_period date) TO authenticated;
GRANT ALL ON FUNCTION public.sync_attendance_to_payroll_inputs(p_period date) TO service_role;


--
-- Name: FUNCTION tax_slab_at(p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tax_slab_at(p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.tax_slab_at(p_date date) TO authenticated;
GRANT ALL ON FUNCTION public.tax_slab_at(p_date date) TO service_role;


--
-- Name: FUNCTION transition_payroll_entry(p_payroll_entry_id uuid, p_target_status text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.transition_payroll_entry(p_payroll_entry_id uuid, p_target_status text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.transition_payroll_entry(p_payroll_entry_id uuid, p_target_status text, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.transition_payroll_entry(p_payroll_entry_id uuid, p_target_status text, p_reason text) TO service_role;


--
-- Name: FUNCTION try_transition_payroll_entry(p_payroll_entry_id uuid, p_target_status text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.try_transition_payroll_entry(p_payroll_entry_id uuid, p_target_status text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.try_transition_payroll_entry(p_payroll_entry_id uuid, p_target_status text, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.try_transition_payroll_entry(p_payroll_entry_id uuid, p_target_status text, p_reason text) TO service_role;


--
-- Name: FUNCTION user_emails(p_ids uuid[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.user_emails(p_ids uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.user_emails(p_ids uuid[]) TO authenticated;
GRANT ALL ON FUNCTION public.user_emails(p_ids uuid[]) TO service_role;


--
-- Name: FUNCTION user_manages_employee(p_user uuid, p_employee uuid, p_on date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.user_manages_employee(p_user uuid, p_employee uuid, p_on date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.user_manages_employee(p_user uuid, p_employee uuid, p_on date) TO authenticated;
GRANT ALL ON FUNCTION public.user_manages_employee(p_user uuid, p_employee uuid, p_on date) TO service_role;


--
-- Name: FUNCTION validate_employee_document_family_slot(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.validate_employee_document_family_slot() FROM PUBLIC;
GRANT ALL ON FUNCTION public.validate_employee_document_family_slot() TO authenticated;
GRANT ALL ON FUNCTION public.validate_employee_document_family_slot() TO service_role;


--
-- Name: FUNCTION validate_journal_balance(p_payroll_entry_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.validate_journal_balance(p_payroll_entry_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.validate_journal_balance(p_payroll_entry_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.validate_journal_balance(p_payroll_entry_id uuid) TO service_role;


--
-- Name: TABLE additional_salaries; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.additional_salaries TO authenticated;


--
-- Name: TABLE app_parameters; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.app_parameters TO authenticated;


--
-- Name: TABLE approval_delegations; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.approval_delegations TO authenticated;


--
-- Name: TABLE attendance; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.attendance TO authenticated;


--
-- Name: TABLE audit_events; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.audit_events TO authenticated;


--
-- Name: SEQUENCE audit_log_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.audit_log_id_seq TO authenticated;


--
-- Name: TABLE candidatures; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.candidatures TO authenticated;


--
-- Name: TABLE collective_agreements; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.collective_agreements TO authenticated;


--
-- Name: TABLE companies; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.companies TO authenticated;


--
-- Name: TABLE compliance_findings; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.compliance_findings TO authenticated;


--
-- Name: TABLE contract_types; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.contract_types TO authenticated;


--
-- Name: TABLE contribution_payments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.contribution_payments TO authenticated;


--
-- Name: TABLE delegate_seats; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.delegate_seats TO authenticated;


--
-- Name: TABLE departments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.departments TO authenticated;


--
-- Name: TABLE designations; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.designations TO authenticated;


--
-- Name: TABLE document_requirements; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.document_requirements TO authenticated;


--
-- Name: TABLE document_reviews; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.document_reviews TO authenticated;


--
-- Name: TABLE document_versions; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.document_versions TO authenticated;


--
-- Name: TABLE email_outbox; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.email_outbox TO authenticated;


--
-- Name: TABLE employee_grades; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.employee_grades TO authenticated;


--
-- Name: TABLE employee_module_data; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.employee_module_data TO authenticated;


--
-- Name: SEQUENCE employee_number_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.employee_number_seq TO authenticated;


--
-- Name: TABLE employee_representatives; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.employee_representatives TO authenticated;


--
-- Name: TABLE employee_request_history; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.employee_request_history TO authenticated;


--
-- Name: TABLE employees; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.employees TO authenticated;


--
-- Name: TABLE evaluations; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.evaluations TO authenticated;


--
-- Name: TABLE exit_reasons; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.exit_reasons TO authenticated;


--
-- Name: TABLE garnishment_scale; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.garnishment_scale TO authenticated;


--
-- Name: TABLE ir_family_reductions; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.ir_family_reductions TO authenticated;


--
-- Name: TABLE job_postulations; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.job_postulations TO authenticated;


--
-- Name: TABLE leave_allocations; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.leave_allocations TO authenticated;


--
-- Name: TABLE leave_approval_steps; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.leave_approval_steps TO authenticated;


--
-- Name: TABLE leave_types; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.leave_types TO authenticated;


--
-- Name: TABLE legal_sources; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.legal_sources TO authenticated;


--
-- Name: TABLE loan_balances; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.loan_balances TO authenticated;


--
-- Name: TABLE loan_installments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.loan_installments TO authenticated;


--
-- Name: TABLE loans; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.loans TO authenticated;


--
-- Name: TABLE module_activation; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.module_activation TO authenticated;


--
-- Name: TABLE module_manifest; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.module_manifest TO authenticated;


--
-- Name: TABLE module_parameter_value; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.module_parameter_value TO authenticated;


--
-- Name: TABLE notice_scales; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.notice_scales TO authenticated;


--
-- Name: TABLE notifications_log; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.notifications_log TO authenticated;


--
-- Name: TABLE org_positions; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.org_positions TO authenticated;


--
-- Name: TABLE org_relations; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.org_relations TO authenticated;


--
-- Name: TABLE overtime_rates; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.overtime_rates TO authenticated;


--
-- Name: TABLE payment_modes; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payment_modes TO authenticated;


--
-- Name: TABLE payroll_anomalies; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payroll_anomalies TO authenticated;


--
-- Name: TABLE payroll_approvals; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payroll_approvals TO authenticated;


--
-- Name: TABLE payroll_corrections; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.payroll_corrections TO authenticated;


--
-- Name: TABLE payroll_inputs; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payroll_inputs TO authenticated;


--
-- Name: TABLE payroll_periods; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payroll_periods TO authenticated;


--
-- Name: TABLE payroll_snapshots; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payroll_snapshots TO authenticated;


--
-- Name: TABLE recurring_pay_items; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.recurring_pay_items TO authenticated;


--
-- Name: TABLE salary_components; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.salary_components TO authenticated;


--
-- Name: TABLE salary_payments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.salary_payments TO authenticated;


--
-- Name: TABLE salary_slip_details; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.salary_slip_details TO authenticated;


--
-- Name: TABLE salary_slips; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.salary_slips TO authenticated;


--
-- Name: TABLE salary_structure_assignments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.salary_structure_assignments TO authenticated;


--
-- Name: TABLE salary_structure_components; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.salary_structure_components TO authenticated;


--
-- Name: TABLE salary_structures; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.salary_structures TO authenticated;


--
-- Name: TABLE severance_scales; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.severance_scales TO authenticated;


--
-- Name: TABLE shift_assignments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.shift_assignments TO authenticated;


--
-- Name: TABLE shift_types; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.shift_types TO authenticated;


--
-- Name: TABLE statutory_notice; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.statutory_notice TO authenticated;


--
-- Name: TABLE tax_slab_brackets; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.tax_slab_brackets TO authenticated;


--
-- Name: TABLE tax_slabs; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.tax_slabs TO authenticated;


--
-- Name: TABLE team_members; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.team_members TO authenticated;


--
-- Name: TABLE teams; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.teams TO authenticated;


--
-- Name: TABLE trainings; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.trainings TO authenticated;


--
-- Name: TABLE trimf_brackets; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.trimf_brackets TO authenticated;


--
-- Name: TABLE user_roles; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.user_roles TO authenticated;


--
-- Name: TABLE v_payroll_register; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_payroll_register TO authenticated;


--
-- Name: TABLE v_accounting_journal; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_accounting_journal TO authenticated;


--
-- Name: TABLE v_conformite_embauche; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_conformite_embauche TO authenticated;


--
-- Name: TABLE v_conformite_retenues; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_conformite_retenues TO authenticated;


--
-- Name: TABLE v_contribution_summary; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_contribution_summary TO authenticated;


--
-- Name: TABLE v_echeancier_cotisations; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_echeancier_cotisations TO authenticated;


--
-- Name: TABLE v_leave_balances; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_leave_balances TO authenticated;


--
-- Name: TABLE v_payroll_entry_payments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_payroll_entry_payments TO authenticated;


--
-- Name: TABLE v_salary_slip_ytd; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_salary_slip_ytd TO authenticated;


--
-- Name: TABLE v_slip_payment_status; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_slip_payment_status TO authenticated;


--
-- Name: TABLE work_posts; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.work_posts TO authenticated;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE soma IN SCHEMA public GRANT SELECT,USAGE ON SEQUENCES TO authenticated;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE soma IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE soma IN SCHEMA public GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO authenticated;


--
-- PostgreSQL database dump complete
--

\unrestrict H4pLm6GqmLNdpQIRnox9gEgKnZCxIdP9kGGCrJXQ9skmJ3JJiaEOhBh2PieRGL2

