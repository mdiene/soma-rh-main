-- Retour arrière de 20261216100000 : rétablit la vue et la synchronisation de 20261216090000.
alter table public.contribution_payment_lines
  drop constraint if exists contribution_payment_lines_reference_len,
  drop constraint if exists contribution_payment_lines_note_len;

create or replace view public.v_contribution_follow
with (security_invoker = true) as
with due as (
  select date_trunc('month', s.period_start)::date as mois,
         public.contribution_caisse(d.component_code) as caisse,
         sum(d.deduction_amount + d.employer_amount) as montant_du
    from public.salary_slip_details d
    join public.salary_slips s on s.id = d.salary_slip_id
   where s.status = 'Validé' and d.section in ('retenue', 'patronal')
   group by 1, 2
)
select due.mois, due.caisse, due.montant_du,
       due.caisse in ('IPRES', 'Caisse de sécurité sociale') as dans_echeancier,
       coalesce(l.status, 'À payer') as statut, l.paid_at as paye_le, l.payment_mode as mode,
       l.amount_paid as montant_paye, l.reference, l.note
  from due
  left join public.contribution_payment_lines l on l.month = due.mois and l.caisse = due.caisse
 where due.montant_du <> 0;

create or replace function public.contribution_payment_lines_sync()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_month date := coalesce(new.month, old.month); v_n integer; v_open integer; v_on date; v_amount numeric;
begin
  select count(*), count(*) filter (where statut <> 'Payé'), max(paye_le), sum(coalesce(montant_paye, montant_du))
    into v_n, v_open, v_on, v_amount
    from public.v_contribution_follow where mois = v_month and dans_echeancier;
  if v_n > 0 and v_open = 0 then
    insert into public.contribution_payments (month, paid_on, amount, notes)
    values (v_month, v_on, v_amount, 'Suivi des versements par caisse')
    on conflict (month) do update set paid_on = excluded.paid_on, amount = excluded.amount, notes = excluded.notes;
  else
    delete from public.contribution_payments where month = v_month;
  end if;
  return null;
end $$;
revoke execute on function public.contribution_payment_lines_sync() from public, anon, authenticated;
notify pgrst, 'reload schema';
