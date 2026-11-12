-- Corrections de la revue du 11/11/2026 : validation dérogatoire refusée si bulletins manquants, matricule non appelable
-- par un compte connecté, plafond cumulé des secondes informations fausses. Tout est annulé.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/revue_corrections.sql  (attendu : "OK revue_corrections")
begin;
create temp table t_ctx as
select
  (select user_id from public.user_roles where role = 'admin' order by user_id limit 1) as admin,
  (select user_id from public.user_roles where role = 'paie' and user_id not in (select user_id from public.user_roles where role = 'admin') order by user_id limit 1) as paie,
  (select company_id from public.payroll_entries limit 1) as company;
grant select on t_ctx to authenticated;
create or replace function pg_temp.as_user(p_user uuid) returns void language plpgsql as $$
begin
  execute 'reset role'; execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;
create or replace function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'OK'; exception when others then return sqlerrm; end $$;
do $$
declare
  c t_ctx; e uuid; r text; n integer; emp public.employees; req uuid; i integer;
begin
  select * into c from t_ctx;
  if c.admin is null or c.paie is null or c.company is null then raise exception 'jeu de données insuffisant'; end if;

  -- 1. validation dérogatoire d'une paie incomplète : refusée
  select count(*) into n from public.employees where status in ('Active', 'Left') and date_of_joining <= '2030-01-31' and (relieving_date is null or relieving_date >= '2030-01-01');
  perform set_config('soma.payroll_transition', 'on', true);
  insert into public.payroll_entries (company_id, period_start, period_end, status) values (c.company, '2030-01-01', '2030-01-31', 'Calculée') returning id into e;
  perform pg_temp.as_user(c.admin);
  r := pg_temp.try(format('select public.transition_payroll_entry(%L, ''Validée'', ''essai'')', e));
  if r not like format('Validation refusé : %s salarié(s) sans bulletin%%', n) then raise exception '1 : refus attendu, obtenu : %', r; end if;

  -- 2. next_employee_number n'est plus appelable par un compte connecté ; preview l'est pour paie seulement
  perform pg_temp.as_user(c.paie);
  r := pg_temp.try('select public.next_employee_number()');
  if r = 'OK' then raise exception '2 : next_employee_number appelable par un compte connecté'; end if;
  r := pg_temp.try('select public.preview_employee_number()');
  if r <> 'OK' then raise exception '2 : aperçu refusé au rôle paie : %', r; end if;

  -- 3. 10 secondes informations fausses sur une autorisation : elle est révoquée
  execute 'reset role';
  select * into emp from public.employees where status = 'Active' and date_of_birth is not null limit 1;
  update public.employees set phone_personal = '700009991' where id = emp.id;
  insert into public.phone_access_requests (employee_id, phone_e164, purpose, status, decided_at, expires_at)
    values (emp.id, '+221700009991', 'signup', 'authorized', now() - interval '2 days', now() + interval '1 day') returning id into req;
  -- 9 échecs anciens (hors du verrou de 30 min) puis un 10e réel
  insert into public.phone_access_attempts (kind, phone_e164, ip_hash, occurred_at)
    select 'second_factor_fail', '+221700009991', 'iptest', now() - interval '1 hour' - (g || ' minutes')::interval from generate_series(1, 9) g;
  perform public.phone_access_open('700009991', '1900-01-01', 'iptest', 'tok1');
  if (select status from public.phone_access_requests where id = req) <> 'revoked' then raise exception '3 : autorisation non révoquée, statut %', (select status from public.phone_access_requests where id = req); end if;
end $$;
select 'OK revue_corrections';
rollback;
