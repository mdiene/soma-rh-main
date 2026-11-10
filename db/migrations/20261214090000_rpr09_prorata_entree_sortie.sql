-- RPR-09 / D-56 : prorata des jours travaillés pour une entrée ou une sortie en cours de mois.
-- Paramètre payroll_settings.proration_basis ('ouvrables' par défaut : lundi au samedi ; 'calendaires').
-- Une ligne RET_PRORATA (section gain, négative) est ajoutée au bulletin ; transport, kilométrique et prime d'ancienneté suivent le ratio.
-- Aucun bulletin existant n'est recalculé : seuls les calculs futurs changent. Retour : db/rollback/20261214090000_rpr09_prorata_entree_sortie_down.sql

alter table public.payroll_settings
  add column if not exists proration_basis text not null default 'ouvrables'
  check (proration_basis in ('ouvrables', 'calendaires'));

CREATE OR REPLACE FUNCTION public.compute_salary_slip(p_employee_id uuid, p_period_start date, p_period_end date, p_sursalaire numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
  v_pro_ratio   numeric := 1;   -- D-56 : part des jours travaillés dans le mois (entrée ou sortie en cours de mois)
  v_pro_h       numeric := 0;
  v_pro_den     integer;
  v_pro_num     integer;
  v_pro_start   date;
  v_pro_end     date;
  v_ret_pro     numeric := 0;
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
  v_mod         jsonb;                          -- M3 : éléments de paie des modules métiers
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

  -- D-56 : entrée ou sortie en cours de mois = prorata des jours travaillés (bornes incluses).
  -- Base 'ouvrables' (lundi au samedi, jours fériés non déduits) ou 'calendaires' selon payroll_settings.proration_basis.
  if (e.date_of_joining > p_period_start and e.date_of_joining <= p_period_end)
     or (e.relieving_date >= p_period_start and e.relieving_date < p_period_end) then
    v_pro_start := greatest(p_period_start, e.date_of_joining);
    v_pro_end   := least(p_period_end, coalesce(e.relieving_date, p_period_end));
    if s.proration_basis = 'calendaires' then
      v_pro_den := p_period_end - p_period_start + 1;
      v_pro_num := greatest(v_pro_end - v_pro_start + 1, 0);
    else
      select count(*) filter (where extract(isodow from d) <> 7),
             count(*) filter (where d::date between v_pro_start and v_pro_end and extract(isodow from d) <> 7)
        into v_pro_den, v_pro_num
        from generate_series(p_period_start::timestamp, p_period_end::timestamp, interval '1 day') d;
    end if;
    if v_pro_den > 0 then v_pro_ratio := v_pro_num::numeric / v_pro_den; end if;
    v_pro_h := H * (1 - v_pro_ratio);
  end if;
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
    v_prime_anc := v_base / H * (H - v_abs - v_pro_h + v_hs_total) * v_anc / 100.0;
  end if;

  -- Retenues absences (AL) et indemnité maladie (AM)
  v_ret_abs := - v_fixed_sum / H * v_abs;
  v_ret_pro := - v_fixed_sum * (1 - v_pro_ratio);
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

  -- M3 : éléments de paie des modules métiers (zéro si aucun module actif ni saisie)
  v_mod := public.module_payroll_adjustments(e.id, v_period, v_th);
  v_var_gross := v_var_gross + (v_mod->>'gross')::numeric;

  -- PRECARITE (AZ) : CDD/COD sortis au plus tard en fin de période
  if coalesce(ct.precarity_eligible, e.employment_type in ('CDD','COD')) and e.relieving_date is not null and e.relieving_date <= p_period_end then
    v_precarite := (v_fixed_sum + v_prime_anc + v_tabaski)
                   * coalesce(public.excel_datedif(e.date_of_joining, e.relieving_date, 'm'), 0)
                   * s.precarity_rate;
  end if;

  -- Heures supplémentaires (BA..BD)
  -- lot G (C26-27) : coefficients lus dans overtime_rates (CCNI art. 49) ; repli sur les valeurs historiques
  -- tranche « 60 » = HS_NUIT (HS_REPOS_FERIE_JOUR a le même taux) ; tranche « 100 » = HS_REPOS_FERIE_NUIT
  v_k15  := public.hs_majoration('HS_JOUR_8_PREMIERES', 1.15, p_period_end);
  v_k40  := public.hs_majoration('HS_JOUR_AU_DELA',     1.40, p_period_end);
  v_k60  := public.hs_majoration('HS_NUIT',             1.60, p_period_end);
  v_k100 := public.hs_majoration('HS_REPOS_FERIE_NUIT', 2.00, p_period_end);
  v_mt15  := v_hs15  * v_th * v_k15;
  v_mt40  := v_hs40  * v_th * v_k40;
  v_mt60  := v_hs60  * v_th * v_k60;
  v_mt100 := v_hs100 * v_th * v_k100;

  -- BRUT (BE) = SOMME(SALAIRE DE BASE : MT HS200%)
  v_brut := v_fixed_sum + v_prime_anc + v_ret_abs + v_ret_pro + v_ind_mal + v_var_gross
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
  v_at := v_css_base * public.css_at_rate_effective(s.css_at_rate);   -- M4 : taux AT propre à la société

  v_ipm_base := least(v_brut, s.ipm_ceiling);
  v_ipm_sal  := v_ipm_base * s.ipm_rate * s.ipm_employee_share;
  v_ipm_pat  := v_ipm_base * s.ipm_rate * (1 - s.ipm_employee_share);

  v_total_ret   := v_ir + v_trimf + v_brs + v_rg_sal + v_rc_sal + v_ipm_sal;      -- CB
  v_charges_pat := v_cfce + v_rg_pat + v_rc_pat + v_af + v_at + v_ipm_pat;        -- CC
  v_net_rem     := v_brut - v_total_ret;                                          -- CE

  -- ------------------------------------------------ indemnités non imposables
  if a.transport_mode = 'Prime de transport' then
    v_transport := (s.transport_allowance / H) * (H - (v_abs / 8)) * v_pro_ratio;
  elsif a.transport_mode = 'Indemnité kilométrique' then
    v_km := (s.km_allowance / H) * (H - (v_abs / 8)) * v_pro_ratio;
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

  v_var_nontax := v_var_nontax + (v_mod->>'non_taxable')::numeric;   -- M3

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
      'base', v_base / H, 'quantity', H - v_abs - v_pro_h + v_hs_total,
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
  if v_ret_pro <> 0 then
    v_lines := v_lines || jsonb_build_object('code','RET_PRORATA','label','Retenue prorata (entrée ou sortie en cours de mois)',
      'section','gain','sort',16,'base', v_fixed_sum,'quantity', v_pro_ratio,'rate',1,'gain', v_ret_pro);
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
  -- M3 : lignes des modules (section gains)
  v_lines := v_lines || coalesce((select jsonb_agg(jsonb_build_object('code', l->>'rule_id', 'label', l->>'label',
    'section','gain','sort',23,'gain',(l->>'amount')::numeric,'module_id',l->>'module_id','taxable',(l->>'taxable')::boolean))
    from jsonb_array_elements(v_mod->'lines') l), '[]'::jsonb);
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
      'base', v_css_base, 'employer_rate', public.css_at_rate_effective(s.css_at_rate), 'employer', v_at),
    jsonb_build_object('code','CFCE','label','CFCE','section','patronal','sort',59,
      'base', v_brut, 'employer_rate', s.cfce_rate, 'employer', v_cfce)
  );

  if v_transport <> 0 then
    v_lines := v_lines || jsonb_build_object('code','IND_TRANSPORT','label','Indemnité de transport',
      'section','indemnite','sort',70,'base', s.transport_allowance / H,'quantity', (H - v_abs / 8) * v_pro_ratio,'rate',1,'gain', v_transport);
  end if;
  if v_panier <> 0 then
    v_lines := v_lines || jsonb_build_object('code','IND_PANIER','label','Indemnité de panier',
      'section','indemnite','sort',71,'base', s.smig_hourly * s.meal_allowance_factor,'quantity', v_meals,'rate',1,'gain', v_panier);
  end if;
  if v_km <> 0 then
    v_lines := v_lines || jsonb_build_object('code','IND_KM','label','Indemnité kilométrique',
      'section','indemnite','sort',72,'base', s.km_allowance / H,'quantity', (H - v_abs / 8) * v_pro_ratio,'rate',1,'gain', v_km);
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
    'module_findings', v_mod->'findings',
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
$function$;

revoke execute on function public.compute_salary_slip(uuid, date, date, numeric) from public, anon;
grant execute on function public.compute_salary_slip(uuid, date, date, numeric) to authenticated, service_role;
notify pgrst, 'reload schema';
