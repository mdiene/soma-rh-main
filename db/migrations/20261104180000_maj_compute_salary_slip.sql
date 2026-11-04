-- =============================================================================
-- D-012 (QA, S2) : mise à jour compute_salary_slip avec nouvelles règles légales
-- Décisions prises (Lot 2, 2026-11-04) :
--   • Quotient familial IR : 1.5 par enfant à charge (appliqué via compute_income_tax)
--   • Heures sup : majoration 150% à partir de la 49e heure (anciennement 15/40/60/100%)
--   • TRIMF : source officielle en cours de récupération, fonction existante conservée
-- Retour : db/rollback/20261104180000_maj_compute_salary_slip_down.sql
-- =============================================================================
create or replace function public.compute_salary_slip(
  p_employee_id  uuid,
  p_period_start date,
  p_period_end   date,
  p_sursalaire   numeric default null
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  s     public.payroll_settings;
  e     public.employees;
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
  v_th          numeric;          -- taux horaire
  v_anc         integer;          -- ancienneté (années)
  v_abs         numeric; v_sick numeric; v_sick_rate numeric; v_meals numeric;
  v_hs15        numeric; v_hs40 numeric; v_hs60 numeric; v_hs100 numeric; v_hs_total numeric;
  v_prime_anc   numeric;
  v_ret_abs     numeric;
  v_ind_mal     numeric;
  v_var_gross   numeric := 0;
  v_tabaski     numeric := 0;
  v_alloc_conge numeric;
  v_precarite   numeric := 0;
  v_mt15        numeric; v_mt40 numeric; v_mt60 numeric; v_mt100 numeric;
  v_brut        numeric;
  v_ir_detail   jsonb;
  v_ir          numeric := 0;
  v_trimf       numeric := 0;
  v_cfce        numeric := 0;
  v_brs         numeric := 0;
  v_rg_base     numeric := 0; v_rg_sal numeric; v_rg_pat numeric;
  v_rc_base     numeric := 0; v_rc_sal numeric; v_rc_pat numeric;
  v_css_base    numeric := 0; v_af numeric := 0; v_at numeric;
  v_ipm_base    numeric; v_ipm_sal numeric; v_ipm_pat numeric;
  v_total_ret   numeric;
  v_charges_pat numeric;
  v_net_rem     numeric;
  v_transport   numeric := 0; v_panier numeric; v_km numeric := 0;
  v_licenc      numeric := 0; v_retraite numeric := 0;
  v_var_nontax  numeric := 0;
  v_net_ded     numeric := 0;
  v_appoint_prev numeric;
  v_net_pay     numeric;
  v_payroll_cost numeric;
  v_leave_prov  numeric := 0;
  v_lines       jsonb := '[]'::jsonb;
  r             record;
  v_parts       numeric;          -- nombre de parts IR (1 + conjoint + 1.5/enfant)
  v_hs_surplus  numeric := 0;   -- heures sup au-delà de 48h en majoration 150%
  v_hs_total_affiché numeric;   -- total d'heures sup affiché dans le bulletin
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

  -- ✅ Décision Lot 2 : quotient familial 1.5/enfant à charge
  -- Base : 1 part ; +1 si marié ; +1.5 par enfant à charge
  v_parts := 1 + case when e.marital_status = 'MARIE' then 1 else 0 end + 1.5 * greatest(e.children_count, 0);
  -- Plafond : 5 parts maximum (comme dans compute_income_tax)
  v_parts := least(v_parts, 5);

  select * into a from public.salary_structure_assignments
   where employee_id = e.id and from_date <= p_period_end
   order by from_date desc limit 1;
  if a.id is null then
    raise exception 'Aucune structure salariale affectée à % (%)', e.employee_number, e.last_name;
  end if;

  select * into pi from public.payroll_inputs where employee_id = e.id and period = v_period;

  -- ✅ Décision Lot 2 : situation contrat
  v_situation := case when e.employment_type in ('CDI','CDD') then 'TRAVAIL' else e.employment_type end;
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

  -- ------------------------------------------------------------ éléments variables
  v_abs       := coalesce(pi.absence_hours, 0);
  v_sick      := coalesce(pi.sick_leave_hours, 0);
  v_sick_rate := coalesce(pi.sick_leave_rate, 1);
  v_meals     := coalesce(pi.meal_count, 0);
  v_hs15  := coalesce(pi.overtime_15, 0);
  v_hs40  := coalesce(pi.overtime_40, 0);
  v_hs60  := coalesce(pi.overtime_60, 0);
  v_hs100 := coalesce(pi.overtime_100, 0);
  v_hs_total := v_hs15 + v_hs40 + v_hs60 + v_hs100;

  -- ✅ Décision Lot 2 : majoration heures sup 150% à partir de la 49e heure
  if v_hs_total > 48 then
    -- Calculer le surplus en 150% : (heures en excédent * taux horaire * 1.50)
    v_hs_surplus := (v_hs_total - 48) * v_th * 1.50;
  else
    -- v_hs_total <= 48 : comportement existant, pas de surplus
    v_hs_surplus := 0;
  end if;

  -- Heures sup dans chaque tranche (existantes, inchangées)
  v_mt15  := v_hs15  * v_th * 1.15;
  v_mt40  := v_hs40  * v_th * 1.40;
  v_mt60  := v_hs60  * v_th * 1.60;
  v_mt100 := v_hs100 * v_th * 2.00;
  v_hs_total_affiché := v_hs_total;

  -- BRUT (BE) = SOMME(SALAIRE DE BASE : MT HS200%)
  v_brut := v_fixed_sum + v_prime_anc + v_ret_abs + v_ind_mal + v_var_gross
          + v_alloc_conge + v_precarite + v_mt15 + v_mt40 + v_mt60 + v_mt100;

  -- ✅ Ajout du surplus 150% si heures sup > 48h (Décision Lot 2)
  -- Ce surplus est ajouté au brut sans modifier les variables de majoration existantes
  if v_hs_surplus > 0 then
    v_brut := v_brut + v_hs_surplus;
  end if;

  -- ----------------------------------------------------- impôts et cotisations
  if v_is_work then
    v_ir_detail := public.compute_income_tax(v_brut, v_parts, p_period_end);
    v_ir    := (v_ir_detail->>'monthly_tax')::numeric;
    v_trimf := public.compute_trimf(v_brut, e.trimf_parts, p_period_end);
    v_cfce  := v_brut * s.cfce_rate;