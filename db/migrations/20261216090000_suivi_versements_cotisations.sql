-- =============================================================================
-- Suivi des versements de cotisations, par mois et par caisse (comme le suivi du paiement des salaires)
--   contribution_payment_lines : état « À payer / Payé » d'une caisse pour un mois, avec mode, date et référence (reçu, virement, chèque)
--   v_contribution_follow      : montant dû par mois et par caisse (bulletins validés) + état du versement
--   Synchronisation avec contribution_payments (échéancier, règle COT-ECHEANCE) : un mois est « versé » quand toutes les caisses
--   de l'échéancier (IPRES, Caisse de sécurité sociale) sont payées.
-- Retour : db/rollback/20261216090000_suivi_versements_cotisations_down.sql
-- =============================================================================
create table public.contribution_payment_lines (
  month        date not null check (month = date_trunc('month', month)::date),
  caisse       text not null,
  status       text not null default 'À payer' check (status in ('À payer', 'Payé')),
  paid_at      date,
  payment_mode text references public.payment_modes(code),
  amount_paid  numeric check (amount_paid is null or amount_paid >= 0),
  reference    text,
  note         text,
  paid_by      uuid references auth.users(id) on delete set null default auth.uid(),
  updated_at   timestamptz not null default now(),
  primary key (month, caisse),
  check (status = 'À payer' or paid_at is not null)
);
create index contribution_payment_lines_paid_by_idx on public.contribution_payment_lines(paid_by);
create index contribution_payment_lines_mode_idx on public.contribution_payment_lines(payment_mode);
create index contribution_payment_lines_status_idx on public.contribution_payment_lines(status);

alter table public.contribution_payment_lines enable row level security;
create policy contribution_payment_lines_read on public.contribution_payment_lines for select to authenticated
  using ((select public.has_role(array['rh', 'paie'])));
create policy contribution_payment_lines_ins on public.contribution_payment_lines for insert to authenticated
  with check ((select public.has_role(array['paie'])));
create policy contribution_payment_lines_upd on public.contribution_payment_lines for update to authenticated
  using ((select public.has_role(array['paie']))) with check ((select public.has_role(array['paie'])));
create policy contribution_payment_lines_del on public.contribution_payment_lines for delete to authenticated
  using ((select public.has_role(array['admin'])));
revoke all on public.contribution_payment_lines from anon;

create or replace function public.contribution_payment_lines_touch()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  new.paid_by := coalesce((select auth.uid()), new.paid_by);
  return new;
end $$;
create trigger contribution_payment_lines_touch before insert or update on public.contribution_payment_lines
  for each row execute function public.contribution_payment_lines_touch();

create or replace function public.contribution_payment_lines_audit()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.audit_log (table_name, record_id, record_key, action, old_data, new_data)
  values ('contribution_payment_lines', null, coalesce(new.month, old.month)::text || ' ' || coalesce(new.caisse, old.caisse),
          case tg_op when 'INSERT' then 'création' when 'UPDATE' then 'modification' else 'suppression' end,
          case when tg_op <> 'INSERT' then to_jsonb(old) - 'updated_at' end,
          case when tg_op <> 'DELETE' then to_jsonb(new) - 'updated_at' end);
  return null;
end $$;
revoke execute on function public.contribution_payment_lines_audit() from public, anon, authenticated;
create trigger contribution_payment_lines_audit after insert or update or delete on public.contribution_payment_lines
  for each row execute function public.contribution_payment_lines_audit();

-- Caisse destinataire d'une rubrique (même regroupement que l'état résumé des cotisations de l'interface)
create or replace function public.contribution_caisse(p_code text)
returns text language sql immutable set search_path = '' as $$
  select case p_code
    when 'IPRES_RG' then 'IPRES' when 'IPRES_RC' then 'IPRES'
    when 'CSS_AF' then 'Caisse de sécurité sociale' when 'CSS_AT' then 'Caisse de sécurité sociale'
    when 'IPM' then 'IPM'
    when 'IR' then 'Impôts (DGID)' when 'TRIMF' then 'Impôts (DGID)' when 'CFCE' then 'Impôts (DGID)' when 'BRS' then 'Impôts (DGID)'
    else 'Autres' end
$$;

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
revoke all on public.v_contribution_follow from anon;
grant select on public.v_contribution_follow to authenticated;

-- Synchronise l'échéancier : mois versé quand toutes les caisses de l'échéancier sont payées, sinon versement effacé.
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
create trigger contribution_payment_lines_sync after insert or update or delete on public.contribution_payment_lines
  for each row execute function public.contribution_payment_lines_sync();

-- aucune de ces fonctions n'est appelée directement par un client (déclencheurs et vue) : pas d'exécution pour anon
revoke execute on function public.contribution_payment_lines_touch() from public, anon, authenticated;
revoke execute on function public.contribution_caisse(text) from public, anon;

notify pgrst, 'reload schema';
