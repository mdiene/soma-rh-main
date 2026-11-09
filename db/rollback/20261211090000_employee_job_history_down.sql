-- Retour : supprime l'historique des emplois et ses déclencheurs (le certificat de travail retombe sur l'emploi actuel).
drop trigger if exists employees_job_history_ins on public.employees;
drop trigger if exists employees_job_history_upd on public.employees;
drop table if exists public.employee_job_history;
drop function if exists public.employee_job_history_sync();
notify pgrst, 'reload schema';
