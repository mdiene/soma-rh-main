-- Mon équipe : anomalies de présence (lecture du pointage de ses collaborateurs) et prêts en cours (sans montants).
-- Le pointage ne contient ni salaire ni donnée de paie : lecture ouverte au manager via can_see_leave.
-- Les prêts sont financiers : le manager ne reçoit que le nombre d'échéances restantes, jamais les montants.
-- Retour : db/rollback/20261104190000_equipe_presence_prets_down.sql
create policy attendance_select_team on public.attendance
  for select to authenticated
  using ((select public.can_see_leave(employee_id, attendance_date)));

create or replace function public.team_loans_summary()
returns table (employee_id uuid, label text, installments_total integer, installments_left integer)
language sql stable security definer set search_path = '' as $$
  select l.employee_id, l.label, l.installments,
         (select count(*)::int from public.loan_installments i where i.loan_id = l.id and i.status = 'Prévue')
  from public.loans l
  where l.status = 'Actif'
    and public.can_see_leave(l.employee_id, current_date)
$$;
revoke execute on function public.team_loans_summary() from public, anon;
grant execute on function public.team_loans_summary() to authenticated;

notify pgrst, 'reload schema';
