-- RPR-12 : le refus d'approbation ou de validation dit quels contrôles bloquent (par code, avec le nombre et un exemple),
-- au lieu d'un simple compteur. Retour : db/rollback/20261214160000_rpr12_message_controles_bloquants_down.sql

create or replace function public.guard_payroll_validation()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare
  v_blocking integer;
  v_detail text;
begin
  if new.status in ('Approuvée', 'Validée')
     and old.status is distinct from new.status
     and public.has_role(array['rh', 'paie']) then
    select sum(g.n)::integer,
           string_agg(g.code || ' (' || g.n || ') : ' || g.exemple, ' ; ' order by g.n desc, g.code)
      into v_blocking, v_detail
      from (select item ->> 'code' as code, count(*) as n,
                   min(coalesce(item ->> 'salarie', '') || ' — ' || coalesce(item ->> 'message', '')) as exemple
              from jsonb_array_elements(public.payroll_entry_checks(new.id)) as item
             where item ->> 'niveau' = 'erreur'
             group by item ->> 'code') g;

    if coalesce(v_blocking, 0) > 0 then
      raise exception 'Validation impossible : % contrôle(s) bloquant(s) à résoudre. %', v_blocking, v_detail;
    end if;
  end if;
  return new;
end;
$function$;

revoke execute on function public.guard_payroll_validation() from public, anon;
notify pgrst, 'reload schema';
