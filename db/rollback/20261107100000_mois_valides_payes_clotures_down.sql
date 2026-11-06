-- Retour de 20261107100000_mois_valides_payes_clotures : filtres d'origine (« Validée » seul).
create or replace function public.hr_dashboard_year(p_year integer)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with v as (
    -- bulletins validés d'un traitement validé de l'année
    select s.employee_id,
           s.period_start,
           s.gross_pay, s.net_pay, s.income_tax, s.trimf, s.total_employee_deductions, s.total_net_deductions,
           s.employer_charges, s.payroll_cost, s.leave_provision, s.precarity_provision,
           coalesce((s.calculation->'totals'->>'ipres_rg_employee')::numeric,0)
             + coalesce((s.calculation->'totals'->>'ipres_rg_employer')::numeric,0) as ipres_rg,
           coalesce((s.calculation->'totals'->>'ipres_rc_employee')::numeric,0)
             + coalesce((s.calculation->'totals'->>'ipres_rc_employer')::numeric,0) as ipres_rc,
           coalesce((s.calculation->'totals'->>'css_af')::numeric,0)
             + coalesce((s.calculation->'totals'->>'css_at')::numeric,0) as css,
           coalesce((s.calculation->'totals'->>'cfce')::numeric,0) as cfce
    from public.salary_slips s
    join public.payroll_entries pe on pe.id = s.payroll_entry_id and pe.status = 'Validée'
    where s.status = 'Validé'
      and s.period_start >= make_date(p_year, 1, 1)
      and s.period_start <  make_date(p_year + 1, 1, 1)
  ),
  by_month as (
    select date_trunc('month', period_start)::date as period,
           count(*) as slips, count(distinct employee_id) as employees,
           sum(gross_pay) as gross, sum(net_pay) as net, sum(income_tax) as income_tax, sum(trimf) as trimf,
           sum(total_employee_deductions) as employee_deductions, sum(total_net_deductions) as net_deductions,
           sum(ipres_rg) as ipres_rg, sum(ipres_rc) as ipres_rc, sum(css) as css, sum(cfce) as cfce,
           sum(employer_charges) as employer_charges, sum(leave_provision) as leave_provision,
           sum(precarity_provision) as precarity_provision, sum(payroll_cost) as payroll_cost
    from v group by 1
  )
  select jsonb_build_object(
    'year', p_year,
    'totals', (select jsonb_build_object(
        'slips', count(*),
        'employees', count(distinct employee_id),
        'months', count(distinct period_start),
        'gross', coalesce(sum(gross_pay),0),
        'net', coalesce(sum(net_pay),0),
        'income_tax', coalesce(sum(income_tax),0),
        'trimf', coalesce(sum(trimf),0),
        'employee_deductions', coalesce(sum(total_employee_deductions),0),
        'net_deductions', coalesce(sum(total_net_deductions),0),
        'ipres_rg', coalesce(sum(ipres_rg),0),
        'ipres_rc', coalesce(sum(ipres_rc),0),
        'css', coalesce(sum(css),0),
        'cfce', coalesce(sum(cfce),0),
        'employer_charges', coalesce(sum(employer_charges),0),
        'leave_provision', coalesce(sum(leave_provision),0),
        'precarity_provision', coalesce(sum(precarity_provision),0),
        'payroll_cost', coalesce(sum(payroll_cost),0)) from v),
    'months', (select jsonb_agg(jsonb_build_object(
        'period', gs.d,
        'slips', coalesce(b.slips,0), 'employees', coalesce(b.employees,0),
        'gross', coalesce(b.gross,0), 'net', coalesce(b.net,0), 'income_tax', coalesce(b.income_tax,0),
        'trimf', coalesce(b.trimf,0), 'employee_deductions', coalesce(b.employee_deductions,0),
        'net_deductions', coalesce(b.net_deductions,0),
        'ipres_rg', coalesce(b.ipres_rg,0), 'ipres_rc', coalesce(b.ipres_rc,0),
        'css', coalesce(b.css,0), 'cfce', coalesce(b.cfce,0),
        'employer_charges', coalesce(b.employer_charges,0),
        'leave_provision', coalesce(b.leave_provision,0), 'precarity_provision', coalesce(b.precarity_provision,0),
        'payroll_cost', coalesce(b.payroll_cost,0)) order by gs.d)
      from (select make_date(p_year, m, 1) as d from generate_series(1, 12) m) gs
      left join by_month b on b.period = gs.d),
    -- bulletins de l'année hors périmètre (calculés mais non validés) : pour l'expliquer à l'écran
    'pending_slips', (select count(*) from public.salary_slips s
                      where s.status = 'Brouillon'
                        and s.period_start >= make_date(p_year, 1, 1)
                        and s.period_start <  make_date(p_year + 1, 1, 1))
  );
$$;

CREATE OR REPLACE FUNCTION public.payroll_entry_checks(p_payroll_entry_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  pe public.payroll_entries;
  v_prev uuid;
  v_out jsonb := '[]'::jsonb;
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis pour consulter les contrôles';
  end if;
  select * into pe from public.payroll_entries where id = p_payroll_entry_id;
  if not found then return v_out; end if;

  select id into v_prev from public.payroll_entries
   where period_start < pe.period_start and status = 'Validée'
   order by period_start desc limit 1;

  -- salariés actifs sans bulletin (avec la cause probable : pas de structure salariale)
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('niveau', 'erreur', 'code', 'sans_bulletin',
             'salarie', e.employee_number || ' ' || e.last_name || ' ' || e.first_name,
             'message', case when not exists (select 1 from public.salary_structure_assignments a
                                               where a.employee_id = e.id and a.from_date <= pe.period_end)
                             then 'Salarié actif sans structure salariale : aucun bulletin possible'
                             else 'Salarié actif sans bulletin dans ce traitement' end))
      from public.employees e
     where e.status = 'Active'
       and e.date_of_joining <= pe.period_end
       and (e.relieving_date is null or e.relieving_date >= pe.period_start)
       and not exists (select 1 from public.salary_slips s
                        where s.payroll_entry_id = pe.id and s.employee_id = e.id and s.status <> 'Annulé')), '[]'::jsonb);

  -- plusieurs bulletins actifs pour un même salarié
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('niveau', 'erreur', 'code', 'doublon_bulletin',
             'salarie', e.employee_number || ' ' || e.last_name || ' ' || e.first_name,
             'message', 'Plusieurs bulletins actifs pour ce salarié dans le traitement'))
      from public.employees e
     where (select count(*) from public.salary_slips s
             where s.payroll_entry_id = pe.id and s.employee_id = e.id and s.status <> 'Annulé') > 1), '[]'::jsonb);

  -- net nul ou négatif
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('niveau', 'erreur', 'code', 'net_negatif',
             'salarie', e.employee_number || ' ' || e.last_name || ' ' || e.first_name,
             'message', 'Net à payer nul ou négatif'))
      from public.salary_slips s join public.employees e on e.id = s.employee_id
     where s.payroll_entry_id = pe.id and s.status <> 'Annulé' and s.net_pay <= 0), '[]'::jsonb);

  -- variation du net supérieure à 30 % par rapport au dernier mois validé
  if v_prev is not null then
    v_out := v_out || coalesce((
      select jsonb_agg(jsonb_build_object('niveau', 'alerte', 'code', 'variation',
               'salarie', e.employee_number || ' ' || e.last_name || ' ' || e.first_name,
               'message', 'Net ' || round(p.net_pay) || ' → ' || round(s.net_pay) || ' F ('
                          || round(((s.net_pay - p.net_pay) / p.net_pay) * 100) || ' %)'))
        from public.salary_slips s
        join public.salary_slips p on p.employee_id = s.employee_id and p.payroll_entry_id = v_prev and p.status <> 'Annulé'
        join public.employees e on e.id = s.employee_id
       where s.payroll_entry_id = pe.id and s.status <> 'Annulé' and p.net_pay > 0
         and abs((s.net_pay - p.net_pay) / p.net_pay) > 0.30), '[]'::jsonb);
  end if;

  -- aucune variable du mois saisie pour un salarié payé
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('niveau', 'alerte', 'code', 'sans_variables',
             'salarie', e.employee_number || ' ' || e.last_name || ' ' || e.first_name,
             'message', 'Aucune variable du mois saisie (absences, heures supplémentaires)'))
      from public.salary_slips s join public.employees e on e.id = s.employee_id
     where s.payroll_entry_id = pe.id and s.status <> 'Annulé'
       and not exists (select 1 from public.payroll_inputs i where i.employee_id = s.employee_id and i.period = pe.period_start)), '[]'::jsonb);

  -- variables corrigées à la main (écart avec les présences)
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('niveau', 'info', 'code', 'variable_corrigee',
             'salarie', e.employee_number || ' ' || e.last_name || ' ' || e.first_name,
             'message', 'Variables du mois corrigées manuellement (différent des présences)'))
      from public.payroll_inputs i join public.employees e on e.id = i.employee_id
     where i.period = pe.period_start and i.attendance_override), '[]'::jsonb);

  -- demandes de congé encore ouvertes sur la période
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('niveau', 'alerte', 'code', 'conge_en_attente',
             'salarie', e.employee_number || ' ' || e.last_name || ' ' || e.first_name,
             'message', 'Demande de congé du ' || l.from_date || ' au ' || l.to_date || ' non traitée'))
      from public.leave_applications l join public.employees e on e.id = l.employee_id
     where l.status = 'Ouverte' and l.from_date <= pe.period_end and l.to_date >= pe.period_start), '[]'::jsonb);

  return v_out;
end;
$function$

;

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
revoke execute on function public.payroll_entry_comparison(uuid) from public, anon;
grant execute on function public.payroll_entry_comparison(uuid) to authenticated;

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

create or replace function public.export_payroll_journal(p_payroll_entry_id uuid)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_entry public.payroll_entries;
  v_journal public.v_accounting_journal%rowtype;
  v_file text;
  v_csv text := '';
  v_total_debit numeric := 0;
  v_total_credit numeric := 0;
  v_has_missing_imputation boolean := false;
  v_line_count integer := 0;
  v_is_balanced boolean := false;
begin
  -- Vérifier que la paie existe et est clôturée
  select * into v_entry from public.payroll_entries where id = p_payroll_entry_id;
  if not found then
    raise exception 'Traitement de paie introuvable : ID %', p_payroll_entry_id;
  end if;

  -- Vérifier que la paie est en état "Validée" ou "Approuvée" (clôturée)
  if v_entry.status not in ('Validée', 'Approuvée') then
    raise exception 'Impossible d''exporter le journal : la paie % n''est pas clôturée (état : %), seule les paies Validée/Approuvée peuvent être exportées', v_entry.id, v_entry.status;
  end if;

  -- Ouvrir le fichier de résultat (simulation fichier ; en production : COPY vers fichier réel)
  -- On construit le contenu CSV ligne par ligne
  v_csv := 'journal_comptable,paie,' || v_entry.id || ',' || v_entry.period_start || ',' || v_entry.period_end || chr(10);

  -- Parcourir chaque ligne du journal comptable
  FOR v_line_count IN
    SELECT count(*) FROM public.v_accounting_journal WHERE payroll_entry_id = p_payroll_entry_id
  LOOP
    -- Pour chaque ligne, vérifier l'imputation
    SELECT * INTO v_journal FROM public.v_accounting_journal WHERE payroll_entry_id = p_payroll_entry_id AND line_no = v_line_count;

    -- Contrôle : rubrique sans imputation (compte analytique NULL ou vide)
    IF v_journal.account IS NULL OR v_journal.account = '' THEN
      v_has_missing_imputation := true;
      -- On quand mêmeinclude la ligne mais avec mise en garde
    END IF;

    -- Additionner pour le contrôle d'équilibre
    v_total_debit := v_total_debit + v_journal.debit;
    v_total_credit := v_total_credit + v_journal.credit;

    -- Format CSV : compte,libellé,débit,crédit
    v_csv := v_csv || v_journal.account || ',' || v_journal.label || ',' || 
             to_char(v_journal.debit, '999G999G990D00') || ',' || 
             to_char(v_journal.credit, '999G999G990D00') || chr(10);
  END LOOP;

  -- Contrôle d'équilibre : somme des débit = somme des crédit
  IF v_total_debit = v_total_credit THEN
    v_is_balanced := true;
  END IF;

  -- Message de fin
  v_csv := v_csv || chr(10) || '-- CONTROLE D''ÉQUILIBRE --' || chr(10);
  IF v_is_balanced THEN
    v_csv := v_csv || 'Équilibre OK : Σ débit = Σ crédit (' || v_total_debit :: text || ')' || chr(10);
  ELSE
    v_csv := v_csv || 'ATTENTION : Déséquilibre : Σ débit (' || v_total_debit :: text || ') ≠ Σ crédit (' || v_total_credit :: text || ')' || chr(10);
  END IF;

  IF v_has_missing_imputation THEN
    v_csv := v_csv || 'Mise en garde : Certaines rubriques n''ont pas d''imputation comptable (compte NULL)' || chr(10);
  END IF;

  v_csv := v_csv || '-- FIN DU JOURNAL --' || chr(10);

  -- En production, ici on écrirait le fichier avec COPY ou un gestionnaire de fichiers
  -- Pour l'instant, on retourne le contenu CSV
  RETURN v_csv;
end;
$$;


notify pgrst, 'reload schema';
