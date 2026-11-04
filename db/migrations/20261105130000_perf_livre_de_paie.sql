-- D-019 (QA, S3) : v_payroll_register relisait le JSON `calculation` (stocké à l'écart) une quarantaine de fois
-- par ligne : 1,8 s pour 963 bulletins. Désormais une seule lecture par bulletin (sous-requête latérale avec
-- OFFSET 0, qui empêche le planificateur de la recopier dans chaque colonne). Mêmes colonnes, mêmes valeurs.
-- Retour : db/rollback/20261105130000_perf_livre_de_paie_down.sql
create or replace view public.v_payroll_register with (security_invoker = true) as
SELECT s.id AS salary_slip_id,
    s.payroll_entry_id,
    s.period_start,
    s.status,
    s.employee_id,
    s.employee_number,
    s.employee_name,
    s.designation,
    s.grade_code,
    s.staff_status,
    s.employment_type,
    s.contract_situation,
    ((j.i ->> 'base_salary'::text))::numeric AS base_salary,
    ((j.i ->> 'sursalaire'::text))::numeric AS sursalaire,
    ((j.t ->> 'seniority_bonus'::text))::numeric AS seniority_bonus,
    ((j.t ->> 'variable_gross'::text))::numeric AS variable_gross,
    ((j.t ->> 'leave_allowance'::text))::numeric AS leave_allowance,
    ((j.t ->> 'overtime_amount'::text))::numeric AS overtime_amount,
    s.gross_pay,
    s.income_tax,
    s.trimf,
    ((j.t ->> 'brs'::text))::numeric AS brs,
    ((j.t ->> 'ipres_rg_employee'::text))::numeric AS ipres_rg_employee,
    ((j.t ->> 'ipres_rc_employee'::text))::numeric AS ipres_rc_employee,
    ((j.t ->> 'ipm_employee'::text))::numeric AS ipm_employee,
    s.total_employee_deductions,
    s.net_remuneration,
    ((j.t ->> 'transport_allowance'::text))::numeric AS transport_allowance,
    ((j.t ->> 'meal_allowance'::text))::numeric AS meal_allowance,
    ((j.t ->> 'km_allowance'::text))::numeric AS km_allowance,
    ((j.t ->> 'previous_rounding'::text))::numeric AS previous_rounding,
    s.total_non_taxable,
    s.total_net_deductions,
    s.net_pay,
    ((j.t ->> 'cfce'::text))::numeric AS cfce,
    ((j.t ->> 'ipres_rg_employer'::text))::numeric AS ipres_rg_employer,
    ((j.t ->> 'ipres_rc_employer'::text))::numeric AS ipres_rc_employer,
    ((j.t ->> 'css_af'::text))::numeric AS css_af,
    ((j.t ->> 'css_at'::text))::numeric AS css_at,
    ((j.t ->> 'ipm_employer'::text))::numeric AS ipm_employer,
    s.employer_charges,
    s.payroll_cost,
    s.leave_provision,
    s.precarity_provision,
    ((j.t ->> 'precarity_allowance'::text))::numeric AS precarity_allowance,
    (COALESCE(((j.t ->> 'ipres_rg_employee'::text))::numeric, (0)::numeric) + COALESCE(((j.t ->> 'ipres_rg_employer'::text))::numeric, (0)::numeric)) AS ipres_rg_total,
    (COALESCE(((j.t ->> 'ipres_rc_employee'::text))::numeric, (0)::numeric) + COALESCE(((j.t ->> 'ipres_rc_employer'::text))::numeric, (0)::numeric)) AS ipres_rc_total,
    (s.status = 'Validé'::text) AS is_validated,
    COALESCE(c.months, (0)::bigint) AS ytd_validated_months,
    COALESCE(c.trimf, (0)::numeric) AS ytd_trimf,
    COALESCE(c.ipres_rg, (0)::numeric) AS ytd_ipres_rg,
    COALESCE(c.ipres_rc, (0)::numeric) AS ytd_ipres_rc,
    COALESCE(c.precarity_provision, (0)::numeric) AS ytd_precarity_provision,
    COALESCE(c.leave_provision, (0)::numeric) AS ytd_leave_provision,
    COALESCE(c.gross, (0)::numeric) AS ytd_gross,
    COALESCE(c.net, (0)::numeric) AS ytd_net_pay,
    COALESCE(c.payroll_cost, (0)::numeric) AS ytd_payroll_cost
   FROM (salary_slips s
     CROSS JOIN LATERAL (SELECT s.calculation -> 'inputs' AS i, s.calculation -> 'totals' AS t OFFSET 0) j
     LEFT JOIN LATERAL ( SELECT count(*) AS months,
            sum(p.trimf) AS trimf,
            sum((COALESCE(((k.t ->> 'ipres_rg_employee'::text))::numeric, (0)::numeric) + COALESCE(((k.t ->> 'ipres_rg_employer'::text))::numeric, (0)::numeric))) AS ipres_rg,
            sum((COALESCE(((k.t ->> 'ipres_rc_employee'::text))::numeric, (0)::numeric) + COALESCE(((k.t ->> 'ipres_rc_employer'::text))::numeric, (0)::numeric))) AS ipres_rc,
            sum(p.precarity_provision) AS precarity_provision,
            sum(p.leave_provision) AS leave_provision,
            sum(p.gross_pay) AS gross,
            sum(p.net_pay) AS net,
            sum(p.payroll_cost) AS payroll_cost
           FROM (salary_slips p
             CROSS JOIN LATERAL (SELECT p.calculation -> 'totals' AS t OFFSET 0) k
             JOIN payroll_entries pe ON (((pe.id = p.payroll_entry_id) AND (pe.status = 'Validée'::text))))
          WHERE ((p.employee_id = s.employee_id) AND (p.status = 'Validé'::text) AND (p.period_start >= (date_trunc('year'::text, (s.period_start)::timestamp with time zone))::date) AND (p.period_start <= s.period_start))) c ON (true))
  WHERE (s.status <> 'Annulé'::text);

notify pgrst, 'reload schema';
