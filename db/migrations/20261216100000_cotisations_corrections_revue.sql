-- Corrections de la revue du 12/11/2026 sur le suivi des versements de cotisations (20261216090000).
-- 1. Concurrence : verrou par mois pendant la synchronisation (deux caisses validées en même temps laissaient le mois « non versé »).
-- 2. Périmètre : seules les caisses de l'échéancier (IPRES, Caisse de sécurité sociale) déclenchent la synchronisation ;
--    un versement saisi à la main dans contribution_payments n'est ni supprimé ni écrasé (seules les lignes créées par le suivi le sont).
-- 3. Changement de mois d'une ligne : l'ancien mois est resynchronisé aussi.
-- 4. Vue : réservée aux rôles rh et paie (un salarié lisait ses propres cotisations, part patronale comprise, par ses bulletins).
-- 5. Bornes de longueur sur la référence et la note.

create or replace view public.v_contribution_follow
with (security_invoker = true) as
with due as (
  select date_trunc('month', s.period_start)::date as mois,
         public.contribution_caisse(d.component_code) as caisse,
         sum(d.deduction_amount + d.employer_amount) as montant_du
    from public.salary_slip_details d
    join public.salary_slips s on s.id = d.salary_slip_id
   where s.status = 'Validé' and d.section in ('retenue', 'patronal')
     -- filtre de rôle pour les rôles d'API ; la synchronisation (propriétaire) et les outils d'administration voient tout
     and ((select public.has_role(array['rh', 'paie'])) or current_user not in ('authenticated', 'anon'))
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
declare
  v_month date; v_n integer; v_open integer; v_on date; v_amount numeric;
  c_marker constant text := 'Suivi des versements par caisse';
begin
  -- les autres caisses (IPM, impôts, divers) n'entrent pas dans l'échéancier légal
  if coalesce(new.caisse, old.caisse) not in ('IPRES', 'Caisse de sécurité sociale') then return null; end if;
  -- mois concernés (l'ancien aussi si la ligne change de mois), dans l'ordre pour éviter tout verrou croisé
  for v_month in
    select distinct m from unnest(array[case when tg_op <> 'INSERT' then old.month end, case when tg_op <> 'DELETE' then new.month end]) m
     where m is not null order by m
  loop
    perform pg_advisory_xact_lock(hashtext('cpl_sync_' || v_month::text)); -- tenu jusqu'à la fin de la transaction
    select count(*), count(*) filter (where statut <> 'Payé'), max(paye_le), sum(coalesce(montant_paye, montant_du))
      into v_n, v_open, v_on, v_amount
      from public.v_contribution_follow where mois = v_month and dans_echeancier;
    if v_n > 0 and v_open = 0 then
      insert into public.contribution_payments (month, paid_on, amount, notes)
      values (v_month, v_on, v_amount, c_marker)
      on conflict (month) do update set paid_on = excluded.paid_on, amount = excluded.amount, notes = excluded.notes
        where public.contribution_payments.notes = c_marker; -- une saisie manuelle n'est jamais écrasée
    else
      delete from public.contribution_payments where month = v_month and notes = c_marker;
    end if;
  end loop;
  return null;
end $$;
revoke execute on function public.contribution_payment_lines_sync() from public, anon, authenticated;

alter table public.contribution_payment_lines
  add constraint contribution_payment_lines_reference_len check (reference is null or char_length(reference) <= 100),
  add constraint contribution_payment_lines_note_len check (note is null or char_length(note) <= 500);

notify pgrst, 'reload schema';
