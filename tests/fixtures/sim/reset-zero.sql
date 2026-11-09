-- Remise a zero de la base de SIMULATION : supprime tous les salaries, la paie, les conges, les presences, les documents,
-- l'organisation (departements, postes, equipes), le journal d'audit et tous les comptes SAUF mdiene@gmail.com.
-- Conserve le referentiel du produit (taux, baremes, rubriques, conventions, grilles, structures, parametres, modules,
-- societe) et le compte mdiene avec le role admin.
-- Usage : via scripts/sim-reset-zero.ps1 (sauvegarde obligatoire avant). Tout est annule en cas d'erreur.
\set ON_ERROR_STOP on
begin;
set local session_replication_role = replica;

do $$
declare
  v_names text[] := array[
    'additional_salaries','approval_delegations','approval_requests','attendance','audit_events','audit_log',
    'candidatures','compliance_findings','compliance_scans','compliance_waivers','contribution_payments','delegate_seats',
    'departments','designations','document_reviews','document_versions','email_outbox','employee_document_access_log',
    'employee_documents','employee_manager_assignments','employee_module_data','employee_notifications',
    'employee_representatives','employee_request_history','employee_requests','employees','evaluations',
    'job_postulations','leave_allocations','leave_applications','leave_approval_steps','leave_ledger',
    'loan_installments','loans','notifications_log','org_positions','org_relations','payroll_anomalies',
    'payroll_approvals','payroll_corrections','payroll_entries','payroll_inputs','payroll_periods','payroll_snapshots',
    'recurring_pay_items','salary_payments','salary_slip_details','salary_slips','salary_structure_assignments',
    'shift_assignments','team_members','teams','trainings',
    'employee_job_history','module_payroll_input','module_shift'];
  v_present text[];
  v_oids oid[];
  v_bad text;
  v_super boolean;
  v_me uuid;
begin
  select rolsuper into v_super from pg_roles where rolname = current_user;
  if not v_super then raise exception 'Superutilisateur requis (utilisateur courant : %)', current_user; end if;

  select id into v_me from auth.users where lower(email) = 'mdiene@gmail.com';
  if v_me is null then raise exception 'Compte mdiene@gmail.com introuvable : remise a zero annulee'; end if;

  select array_agg(n), array_agg(to_regclass('public.' || n)::oid)
    into v_present, v_oids
    from unnest(v_names) n where to_regclass('public.' || n) is not null;

  -- Garde-fou : aucune table conservee ne doit dependre d'une table videe (sinon elle serait videe a son tour).
  select string_agg(distinct format('%s -> %s', c.conrelid::regclass, c.confrelid::regclass), ', ')
    into v_bad
    from pg_constraint c
   where c.contype = 'f' and c.confrelid = any (v_oids) and not (c.conrelid = any (v_oids));
  if v_bad is not null then
    raise exception 'Tables conservees dependantes de tables videes : %. Ajouter ces tables a la liste ou les retirer.', v_bad;
  end if;

  execute 'truncate table ' || (select string_agg(format('public.%I', n), ', ') from unnest(v_present) n) || ' restart identity';

  delete from public.user_roles where user_id <> v_me;
  delete from auth.users where id <> v_me;
  insert into public.user_roles (user_id, role) values (v_me, 'admin') on conflict do nothing;

  raise notice 'Remise a zero : % tables videes, compte mdiene conserve', array_length(v_present, 1);
end $$;

select 'employees' as table_name, count(*) from public.employees
union all select 'payroll_entries', count(*) from public.payroll_entries
union all select 'users', count(*) from auth.users
union all select 'user_roles', count(*) from public.user_roles
union all select 'payroll_settings (conserve)', count(*) from public.payroll_settings
union all select 'tax_slab_brackets (conserve)', count(*) from public.tax_slab_brackets
union all select 'salary_components (conserve)', count(*) from public.salary_components
union all select 'collective_agreements (conserve)', count(*) from public.collective_agreements;
commit;
