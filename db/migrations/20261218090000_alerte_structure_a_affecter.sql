-- Alerte « structure salariale à affecter » : un salarié actif sans structure n'a pas de bulletin.
-- Elle remplace la notification dédiée à la paie après une création par un compte RH seul (assistant de saisie) :
-- l'alerte apparaît sur le tableau de bord des comptes RH et paie, avec un lien vers la fiche.
create or replace function public.structure_pending_alerts()
returns table(code text, severity text, employee_id uuid, employee_number text, employee_name text, due_date date, message text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_role(array['rh', 'paie']) then
    raise exception 'Réservé aux comptes RH, paie ou administrateur';
  end if;
  return query
  select 'structure_a_affecter'::text,
         case when e.date_of_joining <= current_date - 15 then 'erreur' else 'alerte' end,
         e.id, e.employee_number, e.last_name || ' ' || e.first_name, e.date_of_joining,
         'Structure salariale à affecter par la paie : sans elle, aucun bulletin n''est calculé'::text
  from public.employees e
  where e.status = 'Active'
    and not exists (select 1 from public.salary_structure_assignments a where a.employee_id = e.id)
  order by e.date_of_joining, e.employee_number;
end;
$$;
revoke all on function public.structure_pending_alerts() from public, anon;
grant execute on function public.structure_pending_alerts() to authenticated;

notify pgrst, 'reload schema';
