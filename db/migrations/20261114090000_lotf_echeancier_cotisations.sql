-- =============================================================================
-- Lot F (C26-30) : échéancier des cotisations sociales (CSS art. 91-93, 320)
--   contribution_payments : versements réalisés, saisis par la paie
--   v_echeancier_cotisations : montant dû par mois, échéance, jours restants, majoration estimée
--   detecter_conformite() : ajoute la règle COT-ECHEANCE (alerte à J-5 ou en retard)
-- Montant dû = IPRES RG + RC (salarié + patronal) + CSS AF + AT, lu dans salary_slips.calculation->totals.
-- Hypothèses à confirmer : IPM, CFCE, IR/TRIMF hors échéancier ; échéance trimestrielle si moins de 20 salariés.
-- Retour : db/rollback/20261114090000_lotf_echeancier_cotisations_down.sql
-- =============================================================================
create table public.contribution_payments (
  month      date primary key check (month = date_trunc('month', month)::date),
  paid_on    date not null,
  amount     numeric not null check (amount >= 0),
  notes      text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index contribution_payments_created_by_idx on public.contribution_payments(created_by);
alter table public.contribution_payments enable row level security;
create policy contribution_payments_read on public.contribution_payments for select to authenticated using ((select public.has_role(array['rh','paie'])));
create policy contribution_payments_ins  on public.contribution_payments for insert to authenticated with check ((select public.has_role(array['paie'])));
create policy contribution_payments_upd  on public.contribution_payments for update to authenticated using ((select public.has_role(array['paie']))) with check ((select public.has_role(array['paie'])));
create policy contribution_payments_del  on public.contribution_payments for delete to authenticated using ((select public.has_role(array['paie'])));
revoke all on public.contribution_payments from anon;

create or replace view public.v_echeancier_cotisations
with (security_invoker = true) as
with m as (
  select date_trunc('month', s.period_start)::date as mois,
         count(distinct s.employee_id) as effectif,
         sum( coalesce((s.calculation->'totals'->>'ipres_rg_employee')::numeric, 0)
            + coalesce((s.calculation->'totals'->>'ipres_rg_employer')::numeric, 0)
            + coalesce((s.calculation->'totals'->>'ipres_rc_employee')::numeric, 0)
            + coalesce((s.calculation->'totals'->>'ipres_rc_employer')::numeric, 0)
            + coalesce((s.calculation->'totals'->>'css_af')::numeric, 0)
            + coalesce((s.calculation->'totals'->>'css_at')::numeric, 0)) as montant_du
    from public.salary_slips s
   where s.status = 'Validé'
   group by 1
)
select m.mois, m.effectif, m.montant_du,
       public.echeance_cotisations(m.mois, m.effectif::integer) as echeance,
       p.paid_on as paye_le, p.amount as montant_paye,
       (public.echeance_cotisations(m.mois, m.effectif::integer) - current_date) as jours_restants,
       public.majoration_retard_cotisations(m.montant_du, public.echeance_cotisations(m.mois, m.effectif::integer),
                                            coalesce(p.paid_on, current_date)) as majoration_estimee
  from m left join public.contribution_payments p on p.month = m.mois;
comment on view public.v_echeancier_cotisations is 'Cotisations sociales dues par mois de paie validée, échéance légale et majoration de retard estimée.';
revoke all on public.v_echeancier_cotisations from anon;
grant select on public.v_echeancier_cotisations to authenticated;

create or replace function public.detecter_conformite()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
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

revoke all on function public.detecter_conformite() from public, anon;
grant execute on function public.detecter_conformite() to authenticated;
notify pgrst, 'reload schema';
