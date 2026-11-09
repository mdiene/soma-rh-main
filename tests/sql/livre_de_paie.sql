-- D-019 : v_payroll_register (réécrite pour ne lire le JSON qu'une fois) donne les mêmes valeurs que la lecture
-- directe de salary_slips.calculation, et le même cumul annuel que le calcul indépendant ci-dessous.
-- Échoue s'il n'y a aucun bulletin (le test ne prouverait rien).
-- Mois « validé » = traitement Validée, Payée ou Clôturée (migration 20261107100000, D-52) : même filtre que la vue.
do $$
declare n int; ecarts int; ecarts_cumul int;
begin
  select count(*) into n from public.v_payroll_register;
  if n = 0 then raise exception 'FAIL : aucun bulletin, test sans portée'; end if;

  select count(*) into ecarts
  from public.v_payroll_register v join public.salary_slips s on s.id = v.salary_slip_id
  where v.base_salary   is distinct from (s.calculation->'inputs'->>'base_salary')::numeric
     or v.brs           is distinct from (s.calculation->'totals'->>'brs')::numeric
     or v.cfce          is distinct from (s.calculation->'totals'->>'cfce')::numeric
     or v.ipres_rg_employee is distinct from (s.calculation->'totals'->>'ipres_rg_employee')::numeric
     or v.ipres_rg_total is distinct from coalesce((s.calculation->'totals'->>'ipres_rg_employee')::numeric,0) + coalesce((s.calculation->'totals'->>'ipres_rg_employer')::numeric,0)
     or v.net_pay       is distinct from s.net_pay
     or v.gross_pay     is distinct from s.gross_pay;
  if ecarts > 0 then raise exception 'FAIL : % lignes du livre de paie diffèrent du bulletin', ecarts; end if;

  select count(*) into ecarts_cumul
  from public.v_payroll_register v
  where v.ytd_gross is distinct from coalesce((
          select sum(p.gross_pay) from public.salary_slips p join public.payroll_entries pe on pe.id = p.payroll_entry_id and pe.status in ('Validée', 'Payée', 'Clôturée')
          where p.employee_id = v.employee_id and p.status = 'Validé'
            and p.period_start >= date_trunc('year', v.period_start)::date and p.period_start <= v.period_start), 0)
     or v.ytd_ipres_rg is distinct from coalesce((
          select sum(coalesce((p.calculation->'totals'->>'ipres_rg_employee')::numeric,0) + coalesce((p.calculation->'totals'->>'ipres_rg_employer')::numeric,0))
          from public.salary_slips p join public.payroll_entries pe on pe.id = p.payroll_entry_id and pe.status in ('Validée', 'Payée', 'Clôturée')
          where p.employee_id = v.employee_id and p.status = 'Validé'
            and p.period_start >= date_trunc('year', v.period_start)::date and p.period_start <= v.period_start), 0);
  if ecarts_cumul > 0 then raise exception 'FAIL : % lignes avec un cumul annuel différent', ecarts_cumul; end if;
  raise notice 'OK livre_de_paie (% lignes)', n;
end $$;
