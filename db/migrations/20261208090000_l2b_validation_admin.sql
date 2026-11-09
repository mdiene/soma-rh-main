-- =============================================================================
-- Centre de conformité, lot L2b : le RH (ou la paie) saisit, l'administrateur valide.
-- Cadrage : docs/CADRAGE_CENTRE_CONFORMITE.md (§8-1).
--   approval_requests            demandes de dérogation, de modification ou de réinitialisation de constante ou de barème
--   request_waiver / request_parameter_change / request_parameter_reset / request_scale_change / request_scale_reset
--                                point d'entrée unique : rh et paie créent une demande « en attente » sans aucun effet ;
--                                l'administrateur qui saisit lui-même est approuvé d'office (la trace garde l'auteur)
--   decide_request(id, approuver, note)   admin : approuve (exécute grant_waiver / set_parameter / scale_save ... ) ou refuse (motif obligatoire)
--   cancel_request(id)           le demandeur retire sa demande tant qu'elle est en attente
--   approval_requests_overview / approval_pending_count   file de validation et compteur (menu, tableau de bord)
--   deroger_constat              ne déroge plus directement : crée une demande (le rh passe par la validation de l'admin)
-- Les écritures directes sur payroll_settings, barèmes et app_parameters par rh / paie (politiques RLS existantes) ne sont PAS encore retirées :
-- elles le seront avec l'écran des constantes (lot L3), qui les remplace.
-- Retour : db/rollback/20261208090000_l2b_validation_admin_down.sql
-- =============================================================================

alter table public.compliance_waivers add column if not exists requested_by uuid references auth.users(id) on delete set null;
create index if not exists compliance_waivers_requested_by_idx on public.compliance_waivers (requested_by);

create table if not exists public.approval_requests (
  id            uuid primary key default gen_random_uuid(),
  kind          text not null check (kind in ('derogation', 'constante', 'bareme')),
  target        text not null,
  summary       text not null,
  payload       jsonb not null,
  status        text not null default 'en_attente' check (status in ('en_attente', 'approuvée', 'refusée', 'annulée')),
  requested_by  uuid references auth.users(id) on delete set null default auth.uid(),
  requested_at  timestamptz not null default now(),
  decided_by    uuid references auth.users(id) on delete set null,
  decided_at    timestamptz,
  decision_note text,
  check ((status = 'en_attente') = (decided_at is null))
);
create unique index if not exists approval_requests_pending_uniq on public.approval_requests (kind, target) where status = 'en_attente';
create index if not exists approval_requests_requested_by_idx on public.approval_requests (requested_by);
create index if not exists approval_requests_decided_by_idx on public.approval_requests (decided_by);
create index if not exists approval_requests_status_idx on public.approval_requests (status, requested_at desc);
alter table public.approval_requests enable row level security;
drop policy if exists approval_requests_read on public.approval_requests;
create policy approval_requests_read on public.approval_requests for select to authenticated
  using (requested_by = (select auth.uid()) or (select public.has_role(array['admin'])));
revoke insert, update, delete on public.approval_requests from anon, authenticated;
grant select on public.approval_requests to authenticated;
drop trigger if exists approval_requests_audit on public.approval_requests;
create trigger approval_requests_audit after insert or update or delete on public.approval_requests
  for each row execute function public.business_audit();

-- ------------------------------------------------------------ contrôle d'une constante (sans l'appliquer)
create or replace function public.parameter_check(p_code text, p_value numeric, p_eff date)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c public.parameter_catalog;
  v_floor date := public.parameters_min_effective_date();
  v_type text;
begin
  select * into c from public.parameter_catalog where code = p_code;
  if not found then raise exception 'Constante inconnue : %', p_code; end if;
  if p_value is null then raise exception 'Une valeur est obligatoire'; end if;
  if c.min_value is not null and p_value < c.min_value then
    raise exception '« % » : la valeur % est inférieure au minimum autorisé (%)', c.label, p_value, c.min_value;
  end if;
  if c.max_value is not null and p_value > c.max_value then
    raise exception '« % » : la valeur % dépasse le maximum autorisé (%)', c.label, p_value, c.max_value;
  end if;
  if c.store = 'payroll_settings' then
    select data_type into v_type from information_schema.columns
     where table_schema = 'public' and table_name = 'payroll_settings' and column_name = c.column_name;
    if v_type in ('integer', 'smallint', 'bigint') and p_value <> trunc(p_value) then
      raise exception '« % » doit être un nombre entier', c.label;
    end if;
    if p_eff is not null and p_eff <> date_trunc('month', p_eff)::date then
      raise exception 'La date d''effet doit être le premier jour d''un mois (reçu : %)', p_eff;
    end if;
    if p_eff is not null and v_floor is not null and p_eff < v_floor then
      raise exception 'Date d''effet % refusée : des paies sont déjà calculées. Première date possible : %', p_eff, v_floor;
    end if;
  end if;
end $$;

-- ------------------------------------------------------------ exécution d'une demande approuvée
create or replace function public.apply_request(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare q public.approval_requests; v_wid uuid;
begin
  select * into q from public.approval_requests where id = p_id;
  if not found then raise exception 'Demande introuvable'; end if;
  case q.kind
    when 'derogation' then
      v_wid := public.grant_waiver(q.payload ->> 'rule_id', (q.payload ->> 'entity_id')::uuid, q.payload ->> 'reason', q.payload ->> 'parameter_code');
      update public.compliance_waivers set requested_by = q.requested_by where id = v_wid;
    when 'constante' then
      if coalesce((q.payload ->> 'reset')::boolean, false) then
        perform public.reset_parameter(q.payload ->> 'code', nullif(q.payload ->> 'effective_from', '')::date);
      else
        perform public.set_parameter(q.payload ->> 'code', (q.payload ->> 'value')::numeric, nullif(q.payload ->> 'effective_from', '')::date);
      end if;
    when 'bareme' then
      if coalesce((q.payload ->> 'reset')::boolean, false) then
        perform public.scale_reset(q.payload ->> 'code', (q.payload ->> 'effective_from')::date);
      else
        perform public.scale_save(q.payload ->> 'code', (q.payload ->> 'effective_from')::date, q.payload -> 'lines');
      end if;
  end case;
end $$;

-- Crée la demande ; l'administrateur est approuvé d'office
create or replace function public.create_request(p_kind text, p_target text, p_summary text, p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if exists (select 1 from public.approval_requests where kind = p_kind and target = p_target and status = 'en_attente') then
    raise exception 'Une demande est déjà en attente pour cet élément : attendez la décision de l''administrateur ou retirez-la';
  end if;
  insert into public.approval_requests (kind, target, summary, payload) values (p_kind, p_target, p_summary, p_payload) returning id into v_id;
  if public.has_role(array['admin']) then
    perform public.apply_request(v_id);
    update public.approval_requests
       set status = 'approuvée', decided_by = auth.uid(), decided_at = now(), decision_note = 'Saisie directe par l''administrateur'
     where id = v_id;
  end if;
  return v_id;
end $$;

-- ------------------------------------------------------------ demandes
create or replace function public.request_waiver(p_rule_id text, p_entity_id uuid, p_reason text, p_parameter_code text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare f public.compliance_findings; v_label text;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh », « paie » ou « admin » requis';
  end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'Un motif écrit est obligatoire pour déroger'; end if;
  select * into f from public.compliance_findings where rule_id = p_rule_id and entity_id = p_entity_id and resolved_on is null;
  if not found then raise exception 'Aucun écart ouvert pour cette règle et cette entité'; end if;
  select coalesce((select r.label from public.compliance_rules r where r.rule_id = p_rule_id), p_rule_id) into v_label;
  return public.create_request('derogation', p_rule_id || ':' || p_entity_id::text,
    'Dérogation « ' || v_label || ' » : ' || f.message,
    jsonb_build_object('rule_id', p_rule_id, 'entity_id', p_entity_id, 'reason', btrim(p_reason), 'parameter_code', p_parameter_code));
end $$;

create or replace function public.request_parameter_change(p_code text, p_value numeric, p_effective_from date default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare c public.parameter_catalog; v_cur numeric;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh », « paie » ou « admin » requis';
  end if;
  perform public.parameter_check(p_code, p_value, p_effective_from);
  select * into c from public.parameter_catalog where code = p_code;
  select o.current_value into v_cur from public.parameter_overview(coalesce(p_effective_from, current_date)) o where o.code = p_code;
  return public.create_request('constante', p_code,
    c.label || ' : ' || v_cur || ' -> ' || p_value || coalesce(' à partir du ' || to_char(p_effective_from, 'DD/MM/YYYY'), ''),
    jsonb_build_object('code', p_code, 'value', p_value, 'effective_from', p_effective_from, 'reset', false));
end $$;

create or replace function public.request_parameter_reset(p_code text, p_effective_from date default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare c public.parameter_catalog;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh », « paie » ou « admin » requis';
  end if;
  select * into c from public.parameter_catalog where code = p_code;
  if not found then raise exception 'Constante inconnue : %', p_code; end if;
  perform public.parameter_check(p_code, c.default_value, p_effective_from);
  return public.create_request('constante', p_code,
    c.label || ' : retour à la valeur d''origine (' || c.default_value || ')' || coalesce(' à partir du ' || to_char(p_effective_from, 'DD/MM/YYYY'), ''),
    jsonb_build_object('code', p_code, 'effective_from', p_effective_from, 'reset', true));
end $$;

create or replace function public.scale_check_request(p_code text, p_effective_from date)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_floor date := public.parameters_min_effective_date();
begin
  if not exists (select 1 from public.scale_catalog where code = p_code) then raise exception 'Barème inconnu : %', p_code; end if;
  if p_effective_from is null then raise exception 'Une date d''effet est obligatoire'; end if;
  if p_effective_from <> date_trunc('month', p_effective_from)::date then
    raise exception 'La date d''effet doit être le premier jour d''un mois (reçu : %)', p_effective_from;
  end if;
  if v_floor is not null and p_effective_from < v_floor then
    raise exception 'Date d''effet % refusée : des paies sont déjà calculées. Première date possible : %', p_effective_from, v_floor;
  end if;
end $$;

create or replace function public.request_scale_change(p_code text, p_effective_from date, p_lines jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_label text;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh », « paie » ou « admin » requis';
  end if;
  perform public.scale_check_request(p_code, p_effective_from);
  perform public.scale_validate(p_code, p_lines);
  select label into v_label from public.scale_catalog where code = p_code;
  return public.create_request('bareme', p_code, v_label || ' : nouvelle version à partir du ' || to_char(p_effective_from, 'DD/MM/YYYY'),
    jsonb_build_object('code', p_code, 'effective_from', p_effective_from, 'lines', p_lines, 'reset', false));
end $$;

create or replace function public.request_scale_reset(p_code text, p_effective_from date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_label text;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh », « paie » ou « admin » requis';
  end if;
  perform public.scale_check_request(p_code, p_effective_from);
  select label into v_label from public.scale_catalog where code = p_code;
  return public.create_request('bareme', p_code, v_label || ' : retour au jeu d''origine à partir du ' || to_char(p_effective_from, 'DD/MM/YYYY'),
    jsonb_build_object('code', p_code, 'effective_from', p_effective_from, 'reset', true));
end $$;

-- ------------------------------------------------------------ décision, retrait, lecture
create or replace function public.decide_request(p_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare q public.approval_requests;
begin
  if not public.has_role(array['admin']) then
    raise exception 'Droits insuffisants : rôle « admin » requis pour valider une demande';
  end if;
  select * into q from public.approval_requests where id = p_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if q.status <> 'en_attente' then raise exception 'Cette demande a déjà été traitée (%)', q.status; end if;
  if not p_approve and nullif(btrim(p_note), '') is null then raise exception 'Un motif est obligatoire pour refuser une demande'; end if;
  if p_approve then
    perform public.apply_request(p_id);   -- toute erreur annule la décision : la demande reste en attente
  end if;
  update public.approval_requests
     set status = case when p_approve then 'approuvée' else 'refusée' end,
         decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(p_note), '')
   where id = p_id;
  if q.requested_by is not null and q.requested_by is distinct from auth.uid() then
    perform public.notify_user(q.requested_by,
      case when p_approve then 'Demande approuvée' else 'Demande refusée' end,
      q.summary || case when p_approve then ' : approuvée par l''administrateur.' else ' : refusée. Motif : ' || btrim(p_note) end,
      'approval:' || p_id::text);
  end if;
end $$;

create or replace function public.cancel_request(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.approval_requests
     set status = 'annulée', decided_by = auth.uid(), decided_at = now(), decision_note = 'Retirée par le demandeur'
   where id = p_id and status = 'en_attente' and requested_by = auth.uid();
  if not found then raise exception 'Demande introuvable, déjà traitée ou non déposée par vous'; end if;
end $$;

create or replace function public.approval_requests_overview(p_status text default null)
returns table (
  id uuid, kind text, target text, summary text, payload jsonb, status text,
  requested_by uuid, requested_by_email text, requested_at timestamptz,
  decided_by uuid, decided_by_email text, decided_at timestamptz, decision_note text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh », « paie » ou « admin » requis';
  end if;
  return query
  select a.id, a.kind, a.target, a.summary, a.payload, a.status,
         a.requested_by, ru.email::text, a.requested_at, a.decided_by, du.email::text, a.decided_at, a.decision_note
    from public.approval_requests a
    left join auth.users ru on ru.id = a.requested_by
    left join auth.users du on du.id = a.decided_by
   where (p_status is null or a.status = p_status)
     and (a.requested_by = auth.uid() or public.has_role(array['admin']))
   order by (a.status = 'en_attente') desc, a.requested_at desc;
end $$;

-- Compteur : toutes les demandes en attente pour l'administrateur, les siennes pour les autres
create or replace function public.approval_pending_count()
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh », « paie » ou « admin » requis';
  end if;
  return (select count(*)::integer from public.approval_requests a
           where a.status = 'en_attente' and (a.requested_by = auth.uid() or public.has_role(array['admin'])));
end $$;

-- ------------------------------------------------------------ ancien circuit : plus de dérogation directe par le rh
create or replace function public.deroger_constat(p_id uuid, p_motif text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare f public.compliance_findings;
begin
  if not public.has_role(array['rh']) then
    raise exception 'Droits insuffisants : seul le rôle « rh » peut accorder une dérogation';
  end if;
  if nullif(trim(p_motif), '') is null then
    raise exception 'Un motif écrit est obligatoire pour déroger';
  end if;
  select * into f from public.compliance_findings where id = p_id and resolved_on is null and waived_by is null;
  if not found then raise exception 'Constat introuvable, déjà résolu ou déjà dérogé'; end if;
  perform public.request_waiver(f.rule_id, f.entity_id, p_motif);   -- demande validée par l'administrateur (approuvée d'office s'il saisit lui-même)
end $$;

revoke all on function public.parameter_check(text, numeric, date) from public, anon, authenticated;
revoke all on function public.apply_request(uuid) from public, anon, authenticated;
revoke all on function public.create_request(text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.scale_check_request(text, date) from public, anon, authenticated;
revoke all on function public.request_waiver(text, uuid, text, text) from public, anon;
revoke all on function public.request_parameter_change(text, numeric, date) from public, anon;
revoke all on function public.request_parameter_reset(text, date) from public, anon;
revoke all on function public.request_scale_change(text, date, jsonb) from public, anon;
revoke all on function public.request_scale_reset(text, date) from public, anon;
revoke all on function public.decide_request(uuid, boolean, text) from public, anon;
revoke all on function public.cancel_request(uuid) from public, anon;
revoke all on function public.approval_requests_overview(text) from public, anon;
revoke all on function public.approval_pending_count() from public, anon;
revoke all on function public.deroger_constat(uuid, text) from public, anon;
grant execute on function public.request_waiver(text, uuid, text, text) to authenticated;
grant execute on function public.request_parameter_change(text, numeric, date) to authenticated;
grant execute on function public.request_parameter_reset(text, date) to authenticated;
grant execute on function public.request_scale_change(text, date, jsonb) to authenticated;
grant execute on function public.request_scale_reset(text, date) to authenticated;
grant execute on function public.decide_request(uuid, boolean, text) to authenticated;
grant execute on function public.cancel_request(uuid) to authenticated;
grant execute on function public.approval_requests_overview(text) to authenticated;
grant execute on function public.approval_pending_count() to authenticated;
grant execute on function public.deroger_constat(uuid, text) to authenticated;

notify pgrst, 'reload schema';
