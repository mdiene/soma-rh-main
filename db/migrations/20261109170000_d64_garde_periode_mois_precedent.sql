-- D-64 : la garde de période refusait la validation d'un mois M quand le mois M-1 était déjà « Payée » ou « Clôturée »
-- (elle n'acceptait que le statut exact « Validée »). Un compte non administrateur ne pouvait donc plus valider
-- aucun mois à partir du deuxième. Un mois précédent validé, payé ou clôturé est désormais accepté.
create or replace function public.payroll_entry_period_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare v_prev date := (date_trunc('month', new.period_start) - interval '1 month')::date;
begin
  if new.status = 'Validée' and (tg_op = 'INSERT' or old.status is distinct from 'Validée') then
    if new.period_start > date_trunc('month', current_date)::date then
      raise exception 'Période % : impossible de valider un mois futur', to_char(new.period_start, 'MM/YYYY');
    end if;
    if not public.has_role(array['admin'])
       and exists (select 1 from public.payroll_entries e where e.period_start < new.period_start and e.id <> new.id and e.status <> 'Annulée')
       and not exists (select 1 from public.payroll_entries e
                       where date_trunc('month', e.period_start) = v_prev
                         and e.status in ('Validée', 'Payée', 'Clôturée')) then
      raise exception 'Période % : le mois précédent (%) n''est pas validé. Validez-le d''abord (ou demandez à un administrateur).',
        to_char(new.period_start, 'MM/YYYY'), to_char(v_prev, 'MM/YYYY');
    end if;
  end if;
  return new;
end;
$$;
