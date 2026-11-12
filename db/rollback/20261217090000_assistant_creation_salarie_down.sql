-- retour arrière de l'assistant de création d'un salarié
drop function if exists public.simulate_net_for_draft(jsonb, jsonb, numeric, date);
drop function if exists public.create_employee_from_wizard(jsonb, jsonb, text[]);
drop function if exists public.wizard_insert_employee(jsonb, jsonb, text[], date);
drop table if exists public.employee_document_receipts;
notify pgrst, 'reload schema';
