drop trigger if exists salary_payments_closed_guard on public.salary_payments;
drop trigger if exists payroll_inputs_closed_guard on public.payroll_inputs;
drop function if exists public.prevent_closed_period_data_mutation();
notify pgrst, 'reload schema';
