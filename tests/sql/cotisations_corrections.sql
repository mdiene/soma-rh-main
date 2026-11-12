-- Corrections de la revue sur le suivi des cotisations : saisie manuelle jamais écrasée ni effacée, caisses hors échéancier sans effet,
-- vue réservée aux rôles rh et paie, bornes de longueur. Tout est annulé à la fin.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/cotisations_corrections.sql  (attendu : "OK cotisations_corrections")
begin;
create temp table t_ctx as
select
  (select mois from public.v_contribution_follow where dans_echeancier group by mois having count(*) = 2 order by mois limit 1) as v_month,
  (select user_id from public.user_roles ur where role = 'salarie' and not exists (select 1 from public.user_roles x where x.user_id = ur.user_id and x.role in ('rh','paie','admin','manager')) order by user_id limit 1) as u_sal;
grant select on t_ctx to authenticated;
do $$
declare c t_ctx; n integer;
begin
  select * into c from t_ctx;
  if c.v_month is null then raise exception 'jeu de données insuffisant : aucun mois avec deux caisses d''échéancier'; end if;
  if c.u_sal is null then raise exception 'jeu de données insuffisant : aucun compte salarié seul'; end if;
  delete from public.contribution_payments where month = c.v_month;

  -- 1. une saisie manuelle (échéancier légal) n'est pas effacée par une ligne hors échéancier
  insert into public.contribution_payments (month, paid_on, amount, notes) values (c.v_month, current_date, 123, 'saisie manuelle');
  insert into public.contribution_payment_lines (month, caisse, status) values (c.v_month, 'IPM', 'À payer');
  if (select notes from public.contribution_payments where month = c.v_month) is distinct from 'saisie manuelle' then
    raise exception '1 : versement saisi à la main effacé par une ligne IPM';
  end if;

  -- 2. même quand toutes les caisses de l'échéancier sont payées : la saisie manuelle n'est pas écrasée
  insert into public.contribution_payment_lines (month, caisse, status, paid_at, payment_mode, reference) values
    (c.v_month, 'IPRES', 'Payé', current_date, 'virement', 'T1'), (c.v_month, 'Caisse de sécurité sociale', 'Payé', current_date, 'virement', 'T2');
  if (select notes from public.contribution_payments where month = c.v_month) is distinct from 'saisie manuelle' then
    raise exception '2 : versement saisi à la main écrasé par la synchronisation';
  end if;

  -- 3. sans saisie manuelle, la synchronisation crée puis retire sa propre ligne
  delete from public.contribution_payments where month = c.v_month;
  update public.contribution_payment_lines set status = 'À payer', paid_at = null where month = c.v_month and caisse = 'IPRES';
  update public.contribution_payment_lines set status = 'Payé', paid_at = current_date, payment_mode = 'virement' where month = c.v_month and caisse = 'IPRES';
  if (select notes from public.contribution_payments where month = c.v_month) is distinct from 'Suivi des versements par caisse' then
    raise exception '3 : ligne de suivi non créée';
  end if;
  update public.contribution_payment_lines set status = 'À payer', paid_at = null where month = c.v_month and caisse = 'IPRES';
  if exists (select 1 from public.contribution_payments where month = c.v_month) then raise exception '3 : ligne de suivi non retirée'; end if;

  -- 4. un salarié (sans rôle rh ni paie) ne lit rien dans la vue
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', c.u_sal::text, true);
  select count(*) into n from public.v_contribution_follow;
  if n <> 0 then raise exception '4 : la vue renvoie % ligne(s) à un salarié', n; end if;
  execute 'reset role';

  -- 5. bornes de longueur
  begin
    insert into public.contribution_payment_lines (month, caisse, status, reference) values (c.v_month, 'Autres', 'À payer', repeat('x', 101));
    raise exception '5 : référence de 101 caractères acceptée';
  exception when check_violation then null; end;
end $$;
select 'OK cotisations_corrections';
rollback;
