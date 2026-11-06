-- =============================================================================
-- Lot C (C26-07 / C26-26) : contrôle des retenues sur net contre la quotité cessible et le plafond des 2/3
-- Règles : RET-03/RET-04 (CT art. 215-216, CPC art. 381). Même principe que v_conformite_embauche :
-- la vue LISTE les écarts, elle ne modifie pas compute_salary_slip ni ne bloque la paie
-- (le blocage [B] reste un ticket applicatif ; verify-payroll n'est donc pas concerné).
-- Hypothèses à confirmer (juriste) : assiette = brut + éléments non imposables ; « retenues » = total_net_deductions
-- (avances, caisse, coopérative…) ; les prélèvements obligatoires ne comptent pas dans le plafond.
-- Retour : db/rollback/20261111090000_lotc_controle_retenues_down.sql
-- =============================================================================
create or replace view public.v_conformite_retenues
with (security_invoker = true) as
with p as (select min(deduction_global_cap) as cap from public.payroll_settings),
b as (
  select s.id as slip_id, s.employee_id, s.employee_number, s.period_start, s.status,
         s.total_net_deductions as retenues,
         s.gross_pay + s.total_non_taxable as assiette
    from public.salary_slips s
   where s.total_net_deductions > 0
)
select b.slip_id, b.employee_id, b.employee_number, b.period_start, b.status,
       b.assiette, b.retenues,
       public.quotite_cessible(b.assiette)                  as quotite_cessible,
       public.plafond_retenues(b.assiette, p.cap)           as plafond_global,
       b.retenues > public.quotite_cessible(b.assiette)     as depasse_quotite_cessible,
       b.retenues > public.plafond_retenues(b.assiette, p.cap) as depasse_plafond_global
  from b cross join p
 where b.retenues > public.quotite_cessible(b.assiette)
    or b.retenues > public.plafond_retenues(b.assiette, p.cap);
comment on view public.v_conformite_retenues is 'Bulletins dont les retenues sur net dépassent la quotité cessible (CPC 381) ou le plafond global des 2/3 ; lecture seule.';
revoke all on public.v_conformite_retenues from anon;
grant select on public.v_conformite_retenues to authenticated;
