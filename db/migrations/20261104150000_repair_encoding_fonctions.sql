-- =============================================================================
-- D-009 (QA) : réparation de 11 fonctions dont les littéraux accentués avaient été corrompus
-- (« Validée » stocké « Valid??e ») par une application des migrations avec un mauvais encodage.
-- Conséquences corrigées : garde de période inopérante (mois futur et mois précédent), actions d'audit
-- « cr??ation », messages d'erreur illisibles. Les définitions sont reprises à l'identique des
-- migrations d'origine (UTF-8) ; seule la corruption des accents disparaît.
-- Rappel : appliquer les migrations avec `docker exec -i ... psql < fichier` (jamais via un pipe PowerShell).
-- Retour arrière : sans objet (rétablir la corruption n'a aucun intérêt).
-- =============================================================================
-- admin_list_users (source 20261031185300_local_auth_compatibility.sql)
create or replace function public.admin_list_users()
returns table (user_id uuid, email text, created_at timestamptz, last_sign_in_at timestamptz,
               roles text[], employee_id uuid, employee_number text)
language plpgsql
stable
security definer
set search_path = ''
as $$
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

-- business_audit (source 20261030150000_lot0_audit_et_garde_periodes.sql)
create or replace function public.business_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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

-- generate_rotation (source 20261031191500_feature_compatibility.sql)
create or replace function public.generate_rotation(
  p_employee_ids uuid[], p_from date, p_to date, p_pattern text[],
  p_offset integer default 0, p_post_id uuid default null)
returns integer
language plpgsql
set search_path = ''
as $$
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

-- guard_payroll_validation (source 20261102201000_payroll_validation_guard.sql)
create or replace function public.guard_payroll_validation()
returns trigger
language plpgsql
set search_path = ''
as $$
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

-- mark_employee_notification_read (source 20261102134500_phase3_notification_read_status.sql)
create or replace function public.mark_employee_notification_read(
  p_notification_id uuid
)
returns public.employee_notifications
language plpgsql
security definer
set search_path = ''
as $$
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

-- payroll_entry_comparison (source 20261030210000_lot1_reouverture_comparaison.sql)
create or replace function public.payroll_entry_comparison(p_payroll_entry_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
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
   where period_start < pe.period_start and status = 'Validée'
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

-- payroll_entry_period_guard (source 20261030150000_lot0_audit_et_garde_periodes.sql)
create or replace function public.payroll_entry_period_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
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

-- prevent_manager_assignment_overlap (source 20261102140000_phase3_manager_team_scope.sql)
create or replace function public.prevent_manager_assignment_overlap()
returns trigger
language plpgsql
set search_path = ''
as $$
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

-- reopen_payroll_entry (source 20261030210000_lot1_reouverture_comparaison.sql)
create or replace function public.reopen_payroll_entry(p_payroll_entry_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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

-- salary_payments_audit (source 20261030230000_lot3_suivi_paiements.sql)
create or replace function public.salary_payments_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.audit_log (table_name, record_id, record_key, action, old_data, new_data)
  values ('salary_payments', null, coalesce(new.slip_id, old.slip_id)::text,
          case tg_op when 'INSERT' then 'création' when 'UPDATE' then 'modification' else 'suppression' end,
          case when tg_op <> 'INSERT' then to_jsonb(old) - 'updated_at' end,
          case when tg_op <> 'DELETE' then to_jsonb(new) - 'updated_at' end);
  return null;
end;
$$;

-- validate_employee_document_family_slot (source 20261102193000_document_family_slots.sql)
create or replace function public.validate_employee_document_family_slot()
returns trigger
language plpgsql
set search_path = ''
as $$
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

notify pgrst, 'reload schema';
