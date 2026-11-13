-- Saisie des salariés : nom de jeune fille, nom et prénom de la mère, mise en forme des noms, CNI/passeport obligatoire et unique,
-- brouillons de saisie enregistrés en base (reprise depuis n'importe quel poste).

alter table public.employees
  add column if not exists maiden_name       text,
  add column if not exists mother_first_name text,
  add column if not exists mother_last_name  text;
comment on column public.employees.maiden_name is 'Nom de jeune fille (salariées)';
comment on column public.employees.mother_first_name is 'Prénom de la mère';
comment on column public.employees.mother_last_name is 'Nom de la mère';

-- Nom de personne : première lettre de chaque mot en majuscule, le reste en minuscule, espaces superflus retirés
create or replace function public.person_name(p text)
returns text language sql immutable set search_path = '' as $$
  select nullif(initcap(regexp_replace(btrim(lower(p)), '\s+', ' ', 'g')), '')
$$;

-- Appliqué à la création et à chaque modification du champ (les fiches anciennes ne sont pas touchées par une autre modification)
create or replace function public.employees_normalize_names()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.first_name is distinct from old.first_name then new.first_name := coalesce(public.person_name(new.first_name), new.first_name); end if;
  if tg_op = 'INSERT' or new.last_name is distinct from old.last_name then new.last_name := coalesce(public.person_name(new.last_name), new.last_name); end if;
  if tg_op = 'INSERT' or new.maiden_name is distinct from old.maiden_name then new.maiden_name := public.person_name(new.maiden_name); end if;
  if tg_op = 'INSERT' or new.mother_first_name is distinct from old.mother_first_name then new.mother_first_name := public.person_name(new.mother_first_name); end if;
  if tg_op = 'INSERT' or new.mother_last_name is distinct from old.mother_last_name then new.mother_last_name := public.person_name(new.mother_last_name); end if;
  if tg_op = 'INSERT' or new.father_name is distinct from old.father_name then new.father_name := public.person_name(new.father_name); end if;
  if tg_op = 'INSERT' or new.mother_name is distinct from old.mother_name then new.mother_name := public.person_name(new.mother_name); end if;
  return new;
end $$;
create trigger employees_normalize_names before insert or update on public.employees
  for each row execute function public.employees_normalize_names();
revoke execute on function public.person_name(text) from public, anon;
revoke execute on function public.employees_normalize_names() from public, anon, authenticated;

-- Unicité du n° de CNI ou de passeport (espaces et casse ignorés) ; les fiches sans numéro ne sont pas concernées
create unique index if not exists employees_id_document_uidx
  on public.employees ((lower(regexp_replace(id_document_number, '\s', '', 'g'))))
  where btrim(coalesce(id_document_number, '')) <> '';

-- Création par l'assistant : n° de CNI ou de passeport obligatoire et non déjà attribué
CREATE OR REPLACE FUNCTION public.create_employee_from_wizard(p_employee jsonb, p_assignment jsonb DEFAULT NULL::jsonb, p_receipts text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; v_dup text;
begin
  if not public.has_role(array['rh']) then
    raise exception 'Droits insuffisants : administrateur ou RH requis pour créer un salarié';
  end if;
  if p_assignment is not null and not public.has_role(array['paie']) then
    raise exception 'Droits insuffisants : l''affectation de la structure salariale relève de la paie ou d''un administrateur';
  end if;
  -- N° de CNI ou de passeport : obligatoire à la création par l'assistant, et unique (espaces et casse ignorés)
  if btrim(coalesce(p_employee->>'id_document_number', '')) = '' then
    raise exception 'Le numéro de CNI ou de passeport est obligatoire';
  end if;
  select e.employee_number || ' ' || e.last_name into v_dup from public.employees e
   where lower(regexp_replace(e.id_document_number, '\s', '', 'g')) = lower(regexp_replace(p_employee->>'id_document_number', '\s', '', 'g')) limit 1;
  if v_dup is not null then
    raise exception 'Ce numéro de CNI ou de passeport est déjà attribué au salarié %', v_dup;
  end if;
  perform pg_advisory_xact_lock(hashtext('employee_number_seq'));
  v := public.wizard_insert_employee(p_employee, p_assignment, p_receipts);
  insert into public.audit_events (actor_id, action, resource_type, resource_id, after_data, reason)
  values (auth.uid(), 'creation_salarie_assistant', 'employee', (v->>'id')::uuid,
          jsonb_build_object('employee_number', v->>'employee_number', 'structure_assigned', v->'structure_assigned', 'pieces_recues', coalesce(array_length(p_receipts, 1), 0)),
          'Création par l''assistant de saisie');
  return v;
end;
$function$;

revoke all on function public.create_employee_from_wizard(jsonb, jsonb, text[]) from public, anon;
grant execute on function public.create_employee_from_wizard(jsonb, jsonb, text[]) to authenticated, service_role;


-- Brouillons de saisie : un par salarié en cours de création, visibles de leur auteur (et de l'administrateur)
create table public.employee_drafts (
  id         uuid primary key default gen_random_uuid(),
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  data       jsonb not null check (jsonb_typeof(data) = 'object' and pg_column_size(data) < 200000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index employee_drafts_author_idx on public.employee_drafts (created_by, updated_at desc);
create trigger employee_drafts_updated_at before update on public.employee_drafts for each row execute function public.set_updated_at();
alter table public.employee_drafts enable row level security;
create policy employee_drafts_select on public.employee_drafts for select to authenticated
  using ((select public.has_role(array['rh'])) and (created_by = (select auth.uid()) or (select public.has_role(array['admin']))));
create policy employee_drafts_insert on public.employee_drafts for insert to authenticated
  with check ((select public.has_role(array['rh'])) and created_by = (select auth.uid()));
create policy employee_drafts_update on public.employee_drafts for update to authenticated
  using ((select public.has_role(array['rh'])) and (created_by = (select auth.uid()) or (select public.has_role(array['admin']))))
  with check ((select public.has_role(array['rh'])) and (created_by = (select auth.uid()) or (select public.has_role(array['admin']))));
create policy employee_drafts_delete on public.employee_drafts for delete to authenticated
  using ((select public.has_role(array['rh'])) and (created_by = (select auth.uid()) or (select public.has_role(array['admin']))));
revoke all on public.employee_drafts from public, anon;
grant select, insert, update, delete on public.employee_drafts to authenticated;

notify pgrst, 'reload schema';
