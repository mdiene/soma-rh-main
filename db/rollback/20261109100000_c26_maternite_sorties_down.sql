-- Retour C26 (2/3). Attention : si des salariés portent un nouveau motif de sortie, la contrainte d'origine échouera ;
-- les remettre d'abord sur l'un des 5 anciens motifs.
alter table public.employees drop constraint if exists employees_exit_reason_fk;
alter table public.employees
  add constraint employees_exit_reason_check check (exit_reason in ('DEMISSION','LICENCIEMENT','RETRAITE','DECES','FIN DE CONTRAT'));
drop index if exists public.employees_exit_reason_idx;
drop table if exists public.exit_reasons;
alter table public.payroll_settings drop column if exists severance_min_months;
update public.leave_types set max_days_per_year = 98 where code = 'MATERNITE';
alter table public.leave_types drop column if exists extension_days;
notify pgrst, 'reload schema';
