-- =============================================================================
-- C26 (3/3) : conformité sociale — embauche, affiliation, cotisations, délégués, suivi des écarts
-- Tickets : C26-09 / C26-31 (déclaration d'embauche, affiliation sous 2 mois), C26-30 (échéancier et majoration de retard),
--           C26-15 / C26-36 à 38 (représentants et sièges), C26-17 / C26-35 (compliance_findings)
-- Aucun blocage n'est activé ici : la vue v_conformite_embauche liste les écarts, la paie n'est pas encore bloquée
-- (le blocage [B] est un ticket applicatif, voir le cadrage).
-- Application : docker exec -i soma-rh-local-postgres-1 psql -U soma -d soma_rh -v ON_ERROR_STOP=1 < ce fichier
-- Retour : db/rollback/20261109110000_c26_conformite_down.sql
-- =============================================================================

-- ------------------------------------------------------------ embauche et affiliation
alter table public.employees
  add column if not exists hire_declaration_ref text,
  add column if not exists hire_declared_on     date,
  add column if not exists affiliation_date     date;
comment on column public.employees.hire_declaration_ref is 'Référence de la déclaration d''embauche à l''inspection du travail (Code du Travail art. 363).';
comment on column public.employees.affiliation_date     is 'Date d''affiliation à la sécurité sociale ; au plus tard 2 mois après l''embauche (CSS art. 89-90).';

-- écarts d'embauche (security_invoker : la politique RLS de employees s'applique à l'appelant)
create or replace view public.v_conformite_embauche
with (security_invoker = true) as
select e.id as employee_id,
       e.employee_number,
       e.date_of_joining,
       (e.hire_declaration_ref is null)                                           as declaration_manquante,
       (e.affiliation_date is null and current_date > (e.date_of_joining + interval '2 months')::date)
         or (e.affiliation_date is not null and e.affiliation_date > (e.date_of_joining + interval '2 months')::date)
                                                                                   as affiliation_hors_delai
  from public.employees e
 where e.status <> 'Left'
   and (e.hire_declaration_ref is null
        or (e.affiliation_date is null and current_date > (e.date_of_joining + interval '2 months')::date)
        or (e.affiliation_date is not null and e.affiliation_date > (e.date_of_joining + interval '2 months')::date));
comment on view public.v_conformite_embauche is 'Salariés en poste sans déclaration d''embauche ou affiliés plus de 2 mois après l''embauche.';

-- ------------------------------------------------------------ cotisations : échéance et majoration (CSS art. 91-93, 320)
create or replace function public.echeance_cotisations(p_month date, p_headcount integer)
returns date
language sql
immutable
set search_path = ''
as $$
  select case
    when p_headcount >= 20 then (date_trunc('month', p_month) + interval '1 month' + interval '14 days')::date
    else (date_trunc('quarter', p_month) + interval '3 months' + interval '14 days')::date
  end;
$$;
comment on function public.echeance_cotisations(date, integer) is 'Échéance de versement : le 15 du mois suivant (au moins 20 salariés) ou le 15 du trimestre suivant (moins de 20).';

create or replace function public.majoration_retard_cotisations(p_amount numeric, p_due_date date, p_paid_on date)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
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
comment on function public.majoration_retard_cotisations(numeric, date, date) is '10 % par mois ou fraction de mois de retard, plafonné à 50 % (CSS art. 320). Le plafond est annuel : au-delà d''un an, appliquer le calcul par année.';

-- ------------------------------------------------------------ délégués du personnel (décret 67-1360)
create table public.delegate_seats (
  id           uuid primary key default gen_random_uuid(),
  workers_min  integer not null check (workers_min > 0),
  workers_max  integer check (workers_max is null or workers_max >= workers_min),
  seats        smallint not null check (seats > 0),
  source_code  text references public.legal_sources(code),
  unique (workers_min)
);
create index delegate_seats_source_idx on public.delegate_seats(source_code);
comment on table public.delegate_seats is 'Nombre de délégués titulaires selon l''effectif ; au-delà de 1 000, +1 par tranche de 500 supplémentaires (à gérer par le code).';
insert into public.delegate_seats (workers_min, workers_max, seats, source_code) values
  (11, 25, 1, 'DEC_67_1360'), (26, 50, 2, 'DEC_67_1360'), (51, 100, 3, 'DEC_67_1360'),
  (101, 250, 5, 'DEC_67_1360'), (251, 500, 7, 'DEC_67_1360'), (501, 1000, 9, 'DEC_67_1360');

create table public.employee_representatives (
  id           uuid primary key default gen_random_uuid(),
  employee_id  uuid not null references public.employees(id) on delete cascade,
  mandate      text not null check (mandate in ('DELEGUE_TITULAIRE','DELEGUE_SUPPLEANT','MEMBRE_CHST')),
  start_date   date not null,
  end_date     date check (end_date is null or end_date >= start_date),
  created_at   timestamptz not null default now()
);
create index employee_representatives_employee_idx on public.employee_representatives(employee_id);
comment on table public.employee_representatives is 'Salariés protégés : leur sortie exige une autorisation (ticket C26-15). Mandat de 3 ans.';

-- ------------------------------------------------------------ suivi des écarts
create table public.compliance_findings (
  id             uuid primary key default gen_random_uuid(),
  rule_id        text not null,
  severity       text not null check (severity in ('A','B')),
  entity         text not null,
  entity_id      uuid,
  message        text not null,
  detected_on    date not null default current_date,
  resolved_on    date,
  waived_by      uuid references auth.users(id) on delete set null,
  waiver_reason  text,
  created_at     timestamptz not null default now(),
  check (waived_by is null or waiver_reason is not null)
);
create index compliance_findings_entity_idx on public.compliance_findings(entity, entity_id);
create index compliance_findings_waived_idx on public.compliance_findings(waived_by);
create index compliance_findings_open_idx   on public.compliance_findings(rule_id) where resolved_on is null;
comment on table public.compliance_findings is 'Résultats des garde-fous. A = alerte, B = bloquant ; une dérogation exige un motif écrit.';

-- ------------------------------------------------------------ RLS
alter table public.delegate_seats enable row level security;
create policy delegate_seats_read on public.delegate_seats for select to authenticated using (true);
create policy delegate_seats_ins  on public.delegate_seats for insert to authenticated with check ((select public.has_role(array['rh'])));
create policy delegate_seats_upd  on public.delegate_seats for update to authenticated using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));
create policy delegate_seats_del  on public.delegate_seats for delete to authenticated using ((select public.has_role(array['rh'])));

alter table public.employee_representatives enable row level security;
create policy employee_representatives_read on public.employee_representatives for select to authenticated using ((select public.has_role(array['rh','paie'])));
create policy employee_representatives_ins  on public.employee_representatives for insert to authenticated with check ((select public.has_role(array['rh'])));
create policy employee_representatives_upd  on public.employee_representatives for update to authenticated using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));
create policy employee_representatives_del  on public.employee_representatives for delete to authenticated using ((select public.has_role(array['rh'])));

alter table public.compliance_findings enable row level security;
create policy compliance_findings_read on public.compliance_findings for select to authenticated using ((select public.has_role(array['rh','paie'])));
create policy compliance_findings_ins  on public.compliance_findings for insert to authenticated with check ((select public.has_role(array['rh','paie'])));
create policy compliance_findings_upd  on public.compliance_findings for update to authenticated using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));
create policy compliance_findings_del  on public.compliance_findings for delete to authenticated using ((select public.has_role(array['rh'])));

revoke execute on function public.echeance_cotisations(date, integer) from public, anon;
revoke execute on function public.majoration_retard_cotisations(numeric, date, date) from public, anon;
grant execute on function public.echeance_cotisations(date, integer) to authenticated;
grant execute on function public.majoration_retard_cotisations(numeric, date, date) to authenticated;
revoke all on public.v_conformite_embauche from anon;

notify pgrst, 'reload schema';
