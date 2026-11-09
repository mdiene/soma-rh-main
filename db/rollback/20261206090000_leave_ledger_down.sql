-- Retour : la vue des soldes relit leave_allocations et leave_applications ; le registre et ses fonctions sont supprimés.
create or replace view public.v_leave_balances with (security_invoker = true) as
 with alloc as (
   select employee_id, leave_type, sum(days) as allocated from public.leave_allocations
    where to_date >= date_trunc('year', current_date) group by employee_id, leave_type
 ), used as (
   select employee_id, leave_type, sum(total_days) as taken from public.leave_applications
    where status = 'Approuvée' and from_date >= date_trunc('year', current_date) group by employee_id, leave_type
 )
 select e.id as employee_id, e.employee_number, e.first_name, e.last_name, lt.code as leave_type, lt.name as leave_type_name,
        coalesce(a.allocated, 0::numeric) as allocated, coalesce(u.taken, 0::numeric) as taken,
        coalesce(a.allocated, 0::numeric) - coalesce(u.taken, 0::numeric) as balance
   from public.employees e
   cross join public.leave_types lt
   left join alloc a on a.employee_id = e.id and a.leave_type = lt.code
   left join used u on u.employee_id = e.id and u.leave_type = lt.code
  where e.status = 'Active' and (a.allocated is not null or u.taken is not null);
grant select on public.v_leave_balances to authenticated;

drop trigger if exists leave_allocations_ledger on public.leave_allocations;
drop trigger if exists leave_applications_ledger on public.leave_applications;
drop table if exists public.leave_ledger;
drop function if exists public.leave_ledger_sync();
drop function if exists public.leave_ledger_append_only();
notify pgrst, 'reload schema';
