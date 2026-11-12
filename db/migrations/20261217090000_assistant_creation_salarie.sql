-- Assistant de création d'un salarié (wizard) :
--  1. pièces du dossier « reçues » (liste cochable, le téléversement reste dans Dossiers administratifs) ;
--  2. création en une seule opération : fiche + structure salariale (si rôle paie) + pièces reçues, tout ou rien ;
--  3. simulation du net avant création (fenêtre de calcul du salaire) : écrit puis annule, sans consommer de matricule.

-- 1. Pièces reçues ---------------------------------------------------------------------------------------------
create table public.employee_document_receipts (
  employee_id      uuid not null references public.employees(id) on delete cascade,
  requirement_code text not null references public.document_requirements(code),
  received_on      date not null default current_date,
  noted_by         uuid default auth.uid(),
  created_at       timestamptz not null default now(),
  primary key (employee_id, requirement_code)
);
create index employee_document_receipts_code_idx on public.employee_document_receipts(requirement_code);

alter table public.employee_document_receipts enable row level security;
create policy employee_document_receipts_read on public.employee_document_receipts for select to authenticated
  using ((select public.has_role(array['rh', 'paie'])));
create policy employee_document_receipts_ins on public.employee_document_receipts for insert to authenticated
  with check ((select public.has_role(array['rh'])));
create policy employee_document_receipts_upd on public.employee_document_receipts for update to authenticated
  using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));
create policy employee_document_receipts_del on public.employee_document_receipts for delete to authenticated
  using ((select public.has_role(array['rh'])));
revoke all on public.employee_document_receipts from anon;

-- 2. Insertion commune (interne, non exposée) -------------------------------------------------------------------
create or replace function public.wizard_insert_employee(p_employee jsonb, p_assignment jsonb, p_receipts text[], p_period_start date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.employees;
  v_emp public.employees;
  a public.salary_structure_assignments;
  v_target numeric;
  v_start date;
  v_end date;
  v_sur numeric;
  v_slip jsonb;
  v_code text;
begin
  r := jsonb_populate_record(null::public.employees, p_employee);
  if coalesce(trim(r.first_name), '') = '' then raise exception 'Le prénom est obligatoire'; end if;
  if coalesce(trim(r.last_name), '') = '' then raise exception 'Le nom est obligatoire'; end if;
  if r.employment_type is null then raise exception 'Le type de contrat est obligatoire'; end if;
  if r.date_of_joining is null then raise exception 'La date d''entrée est obligatoire'; end if;
  r.id := gen_random_uuid();
  r.employee_number := '';                       -- attribué par le déclencheur
  r.created_at := now();
  r.updated_at := now();
  r.spouses_count := coalesce(r.spouses_count, 0);
  r.children_count := coalesce(r.children_count, 0);
  r.trimf_parts := coalesce(r.trimf_parts, 1);
  r.ir_parts := coalesce(r.ir_parts, 1);
  r.payment_mode := coalesce(r.payment_mode, 'espèces');
  r.status := coalesce(r.status, 'Active');
  if r.company_id is null then select c.id into r.company_id from public.companies c order by c.created_at limit 1; end if;
  insert into public.employees select (r).* returning * into v_emp;

  if p_assignment is not null then
    a := jsonb_populate_record(null::public.salary_structure_assignments, p_assignment);
    v_target := a.target_net;
    a.id := gen_random_uuid();
    a.employee_id := v_emp.id;
    a.structure_id := coalesce(a.structure_id, (select s.id from public.salary_structures s order by s.created_at, s.id limit 1));
    if a.structure_id is null then raise exception 'Aucune structure salariale de référence n''est définie'; end if;
    a.from_date := coalesce(a.from_date, v_emp.date_of_joining);
    a.sursalaire := coalesce(a.sursalaire, 0);
    a.fees := coalesce(a.fees, 0);
    a.other_fixed := coalesce(a.other_fixed, 0);
    a.transport_mode := coalesce(a.transport_mode, 'Prime de transport');
    a.leave_paid_monthly := coalesce(a.leave_paid_monthly, true);
    a.created_at := now();
    a.updated_at := now();
    insert into public.salary_structure_assignments select (a).*;

    v_start := coalesce(p_period_start, date_trunc('month', a.from_date)::date);
    v_end := (date_trunc('month', v_start) + interval '1 month - 1 day')::date;
    if v_target is not null and v_target > 0 and coalesce((p_assignment->>'sursalaire'), '') = '' then
      v_sur := round(public.solve_sursalaire_for_net(v_emp.id, v_start, v_end, v_target), 2);
      update public.salary_structure_assignments set sursalaire = v_sur where id = a.id;
    else
      v_sur := a.sursalaire;
    end if;
    v_slip := public.compute_salary_slip(v_emp.id, v_start, v_end, v_sur)->'totals';
  end if;

  foreach v_code in array coalesce(p_receipts, '{}'::text[]) loop
    insert into public.employee_document_receipts (employee_id, requirement_code) values (v_emp.id, v_code)
    on conflict do nothing;
  end loop;

  return jsonb_build_object(
    'id', v_emp.id, 'employee_number', v_emp.employee_number,
    'structure_assigned', p_assignment is not null,
    'sursalaire', v_sur,
    'gross_pay', v_slip->>'gross_pay', 'net_pay', v_slip->>'net_pay');
end;
$$;
revoke all on function public.wizard_insert_employee(jsonb, jsonb, text[], date) from public, anon, authenticated;

-- 3. Création atomique -------------------------------------------------------------------------------------------
create or replace function public.create_employee_from_wizard(p_employee jsonb, p_assignment jsonb default null, p_receipts text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v jsonb;
begin
  if not public.has_role(array['rh']) then
    raise exception 'Droits insuffisants : administrateur ou RH requis pour créer un salarié';
  end if;
  if p_assignment is not null and not public.has_role(array['paie']) then
    raise exception 'Droits insuffisants : l''affectation de la structure salariale relève de la paie ou d''un administrateur';
  end if;
  perform pg_advisory_xact_lock(hashtext('employee_number_seq'));
  v := public.wizard_insert_employee(p_employee, p_assignment, p_receipts);
  insert into public.audit_events (actor_id, action, resource_type, resource_id, after_data, reason)
  values (auth.uid(), 'creation_salarie_assistant', 'employee', (v->>'id')::uuid,
          jsonb_build_object('employee_number', v->>'employee_number', 'structure_assigned', v->'structure_assigned', 'pieces_recues', coalesce(array_length(p_receipts, 1), 0)),
          'Création par l''assistant de saisie');
  return v;
end;
$$;
revoke all on function public.create_employee_from_wizard(jsonb, jsonb, text[]) from public, anon;
grant execute on function public.create_employee_from_wizard(jsonb, jsonb, text[]) to authenticated;

-- 4. Simulation du net avant création (rien n'est conservé, le matricule n'est pas consommé) ---------------------
create or replace function public.simulate_net_for_draft(p_employee jsonb, p_assignment jsonb, p_target_net numeric, p_period_start date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_last bigint; v_called boolean; v_result jsonb; v_detail text; v jsonb;
begin
  if not public.has_role(array['paie']) then
    raise exception 'Droits insuffisants : le calcul du salaire relève de la paie ou d''un administrateur';
  end if;
  if p_target_net is null or p_target_net <= 0 then raise exception 'Net cible invalide'; end if;
  perform pg_advisory_xact_lock(hashtext('employee_number_seq'));
  select s.last_value, s.is_called into v_last, v_called from public.employee_number_seq s;
  begin
    v := public.wizard_insert_employee(
      p_employee, coalesce(p_assignment, '{}'::jsonb) || jsonb_build_object('target_net', p_target_net, 'sursalaire', null), null, p_period_start);
    raise exception 'WIZARD_DRYRUN' using detail = v::text;
  exception when others then
    if sqlerrm = 'WIZARD_DRYRUN' then
      get stacked diagnostics v_detail = pg_exception_detail;
      v_result := v_detail::jsonb;
    else
      raise;
    end if;
  end;
  perform setval('public.employee_number_seq', v_last, v_called);
  return v_result;
end;
$$;
revoke all on function public.simulate_net_for_draft(jsonb, jsonb, numeric, date) from public, anon;
grant execute on function public.simulate_net_for_draft(jsonb, jsonb, numeric, date) to authenticated;

notify pgrst, 'reload schema';
