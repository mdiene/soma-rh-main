-- Simulation de réorganisation : application « tout ou rien » d'une liste de changements (manager direct, unité, lien hors hiérarchie).
-- Une seule fonction = une seule transaction : si un changement est refusé, aucun n'est appliqué.
-- Mon équipe : les prêts ne sont plus exposés au manager (décision RH) ; la fonction team_loans_summary est supprimée.
-- Retour : db/rollback/20261106200000_reorg_atomique_down.sql
drop function if exists public.team_loans_summary();

create or replace function public.org_apply_reorg(p_moves jsonb, p_from date, p_reason text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare m jsonb; n integer := 0;
begin
  perform public.org_require_hr(p_reason);
  if p_from is null then raise exception 'La date d''effet est obligatoire'; end if;
  if jsonb_typeof(p_moves) is distinct from 'array' or jsonb_array_length(p_moves) = 0 then raise exception 'Aucun changement à appliquer'; end if;
  for m in select * from jsonb_array_elements(p_moves) loop
    case m->>'kind'
      when 'manager' then perform public.org_set_manager((m->>'employee')::uuid, nullif(m->>'manager', '')::uuid, p_from, p_reason);
      when 'unit' then perform public.org_set_employee_unit((m->>'employee')::uuid, nullif(m->>'unit', '')::uuid, p_reason);
      when 'relation' then perform public.org_save_relation(null, (m->>'employee')::uuid, (m->>'related')::uuid, m->>'type', p_from,
                                                            nullif(m->>'end', '')::date, nullif(m->>'pct', '')::numeric, null, p_reason);
      else raise exception 'Type de changement inconnu : %', m->>'kind';
    end case;
    n := n + 1;
  end loop;
  return n;
end;
$$;
revoke execute on function public.org_apply_reorg(jsonb, date, text) from public, anon;
grant execute on function public.org_apply_reorg(jsonb, date, text) to authenticated;

notify pgrst, 'reload schema';
