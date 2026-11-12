-- Retour de RPR-12 : ancien message (simple compteur de contrôles bloquants).
create or replace function public.guard_payroll_validation()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare
  v_blocking integer;
begin
  if new.status in ('Approuvée', 'Validée')
     and old.status is distinct from new.status
     and public.has_role(array['rh', 'paie']) then
    select count(*) into v_blocking
    from jsonb_array_elements(public.payroll_entry_checks(new.id)) as item
    where item ->> 'niveau' = 'erreur';

    if v_blocking > 0 then
      raise exception 'Validation impossible : % contrôle(s) bloquant(s) doit/doivent être résolu(s)', v_blocking;
    end if;
  end if;
  return new;
end;
$function$;

revoke execute on function public.guard_payroll_validation() from public, anon;
notify pgrst, 'reload schema';
