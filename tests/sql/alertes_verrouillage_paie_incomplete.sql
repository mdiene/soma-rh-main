-- RPR-03 (alerte) et RPR-01 (avertissement) : security_alerts réservée à l'administrateur, payroll_missing_employees réservée à rh/paie. Tout est annulé.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/alertes_verrouillage_paie_incomplete.sql  (attendu : "OK alertes_verrouillage_paie_incomplete")
begin;
create temp table t_ctx as
select
  (select user_id from public.user_roles where role = 'admin' order by user_id limit 1) as admin,
  (select user_id from public.user_roles group by user_id having bool_and(role = 'paie') order by user_id limit 1) as paie,
  (select user_id from public.user_roles group by user_id having bool_and(role = 'salarie') order by user_id limit 1) as sal,
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
declare c t_ctx; r text; n integer; e uuid; total integer;
begin
  select * into c from t_ctx;
  if c.admin is null or c.paie is null or c.sal is null or c.company is null then raise exception 'jeu de données insuffisant'; end if;

  -- 1. deux verrouillages du même compte, un d'un autre compte : l'administrateur voit deux alertes, regroupées par compte
  execute 'reset role';
  insert into public.audit_events (action, resource_type, result, after_data) values
    ('verrouillage_connexion', 'auth', 'denied', '{"account":"zz***@test.invalid","ip_hash":"a"}'),
    ('verrouillage_connexion', 'auth', 'denied', '{"account":"zz***@test.invalid","ip_hash":"b"}'),
    ('verrouillage_connexion', 'auth', 'denied', '{"account":"yy***@test.invalid","ip_hash":"a"}');
  perform pg_temp.as_user(c.admin);
  select count(*) into n from public.security_alerts() where employee_name = 'zz***@test.invalid' and message like 'Compte verrouillé 2 fois%';
  if n <> 1 then raise exception '1 : alerte du compte zz absente ou mal regroupée (%)', n; end if;
  select count(*) into n from public.security_alerts() where employee_name = 'yy***@test.invalid' and message like 'Compte verrouillé 1 fois%';
  if n <> 1 then raise exception '1 : alerte du compte yy absente'; end if;

  -- 2. réservée à l'administrateur
  perform pg_temp.as_user(c.paie);
  r := pg_temp.try('select * from public.security_alerts()');
  if r not like '%Réservé aux administrateurs%' then raise exception '2 : paie a lu les alertes de sécurité : %', r; end if;

  -- 3. paie incomplète : la fonction liste les salariés sans bulletin ; refusée au salarié
  execute 'reset role';
  perform set_config('soma.payroll_transition', 'on', true);
  insert into public.payroll_entries (company_id, period_start, period_end, status) values (c.company, '2030-03-01', '2030-03-31', 'Calculée') returning id into e;
  select count(*) into total from public.employees where status in ('Active', 'Left') and date_of_joining <= '2030-03-31' and (relieving_date is null or relieving_date >= '2030-03-01');
  perform pg_temp.as_user(c.paie);
  select count(*) into n from public.payroll_missing_employees(e);
  if n <> total then raise exception '3 : % salarié(s) manquant(s) listé(s), attendu %', n, total; end if;
  perform pg_temp.as_user(c.sal);
  r := pg_temp.try(format('select * from public.payroll_missing_employees(%L)', e));
  if r not like '%Droits insuffisants%' then raise exception '3 : un salarié a lu la liste : %', r; end if;
end $$;
select 'OK alertes_verrouillage_paie_incomplete';
rollback;
