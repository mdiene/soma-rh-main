drop function if exists public.team_loans_summary();
drop policy if exists attendance_select_team on public.attendance;
notify pgrst, 'reload schema';
