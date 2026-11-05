-- Retour de la migration 20261105150000 : retire les alertes légales et les champs d'identité ajoutés.
drop function if exists public.legal_alerts(date, integer);
drop index if exists public.companies_collective_agreement_idx;
alter table public.companies
  drop column if exists collective_agreement_code,
  drop column if exists css_number,
  drop column if exists ipres_number;
