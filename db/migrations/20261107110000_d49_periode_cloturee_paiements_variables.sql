-- D-49 : la clôture d'une paie gèle aussi les paiements (salary_payments) et les éléments variables (payroll_inputs).
-- Une réouverture motivée (statut « Réouverte ») lève le verrou, comme pour les bulletins.
-- Rollback : db/rollback/20261107110000_d49_periode_cloturee_paiements_variables_down.sql
create or replace function public.prevent_closed_period_data_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_closed boolean := false;
  v_slip uuid;
  v_emp  uuid;
  v_per  date;
begin
  if tg_table_name = 'salary_payments' then
    for v_slip in select x from unnest(case tg_op
        when 'INSERT' then array[new.slip_id]
        when 'DELETE' then array[old.slip_id]
        else array[old.slip_id, new.slip_id] end) as t(x) loop
      select exists (
        select 1 from public.salary_slips s join public.payroll_entries e on e.id = s.payroll_entry_id
         where s.id = v_slip and e.status = U&'Cl\00F4tur\00E9e') into v_closed;
      exit when v_closed;
    end loop;
  else
    for v_per in select x from unnest(case tg_op
        when 'INSERT' then array[new.period]
        when 'DELETE' then array[old.period]
        else array[old.period, new.period] end) as t(x) loop
      select exists (
        select 1 from public.payroll_entries e
         where e.status = U&'Cl\00F4tur\00E9e' and v_per between e.period_start and e.period_end) into v_closed;
      exit when v_closed;
    end loop;
  end if;
  if v_closed then
    raise exception 'La paie clôturée est immuable : % refusé ; une réouverture motivée est requise', tg_op;
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists salary_payments_closed_guard on public.salary_payments;
create trigger salary_payments_closed_guard
before insert or update or delete on public.salary_payments
for each row execute function public.prevent_closed_period_data_mutation();

drop trigger if exists payroll_inputs_closed_guard on public.payroll_inputs;
create trigger payroll_inputs_closed_guard
before insert or update or delete on public.payroll_inputs
for each row execute function public.prevent_closed_period_data_mutation();

notify pgrst, 'reload schema';
