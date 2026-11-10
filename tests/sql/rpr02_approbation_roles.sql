-- RPR-02 : l'approbation de la paie revient à l'administrateur et au rôle paie, pas au rôle rh ; séparation des tâches maintenue.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/rpr02_approbation_roles.sql  (attendu : "OK rpr02_approbation_roles")
-- Jeu de données : deux comptes paie seuls, un compte rh seul, un administrateur, un compte salarié seul. Tout est annulé.
begin;
create temp table t_ctx as
select
  (select user_id from public.user_roles group by user_id having bool_and(role = 'paie') order by user_id limit 1) as paie_a,
  (select user_id from public.user_roles group by user_id having bool_and(role = 'paie') order by user_id offset 1 limit 1) as paie_b,
  (select user_id from public.user_roles group by user_id having bool_and(role = 'rh') order by user_id limit 1) as rh,
  (select user_id from public.user_roles where role = 'admin' order by user_id limit 1) as admin,
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
create or replace function pg_temp.new_entry(p_company uuid, p_user uuid, p_month date) returns uuid language plpgsql as $$
declare e uuid;
begin
  execute 'reset role';
  perform set_config('soma.payroll_transition', 'on', true);
  insert into public.payroll_entries (company_id, period_start, period_end, status, created_by, submitted_by)
    values (p_company, p_month, (p_month + interval '1 month - 1 day')::date, 'En revue', p_user, p_user) returning id into e;
  return e;
end $$;
do $$
declare c t_ctx; e uuid; r text;
begin
  select * into c from t_ctx;
  if c.paie_a is null or c.paie_b is null or c.rh is null or c.admin is null or c.sal is null or c.company is null then
    raise exception 'jeu de données insuffisant (2 comptes paie seuls, rh seul, admin, salarié seul)';
  end if;

  -- 1. le rôle rh n'approuve pas
  e := pg_temp.new_entry(c.company, c.paie_a, '2030-01-01');
  perform pg_temp.as_user(c.rh);
  r := pg_temp.try(format('select public.transition_payroll_entry(%L, ''Approuvée'')', e));
  if r not like '%rôle « paie » ou administrateur requis%' then raise exception '1 : rh devait être refusé, obtenu : %', r; end if;

  -- 2. un salarié non plus
  perform pg_temp.as_user(c.sal);
  r := pg_temp.try(format('select public.transition_payroll_entry(%L, ''Approuvée'')', e));
  if r = 'OK' then raise exception '2 : un salarié a approuvé la paie'; end if;

  -- 3. la personne qui a envoyé la paie en revue ne l'approuve pas (séparation des tâches)
  perform pg_temp.as_user(c.paie_a);
  r := pg_temp.try(format('select public.transition_payroll_entry(%L, ''Approuvée'')', e));
  if r not like 'Séparation des tâches%' then raise exception '3 : préparateur devait être refusé, obtenu : %', r; end if;

  -- 4. un autre compte paie approuve
  perform pg_temp.as_user(c.paie_b);
  r := pg_temp.try(format('select public.transition_payroll_entry(%L, ''Approuvée'')', e));
  -- la paie du test est vide : le contrôle des anomalies peut la refuser, mais pas pour une question de rôle ni de séparation
  if r <> 'OK' and r not like 'Validation impossible%contrôle%' then raise exception '4 : un autre compte paie devait être accepté par les règles de rôle : %', r; end if;

  -- 5. l'administrateur approuve
  e := pg_temp.new_entry(c.company, c.paie_a, '2030-02-01');
  perform pg_temp.as_user(c.admin);
  r := pg_temp.try(format('select public.transition_payroll_entry(%L, ''Approuvée'')', e));
  if r <> 'OK' and r not like 'Validation impossible%contrôle%' then raise exception '5 : l''administrateur devait être accepté par les règles de rôle : %', r; end if;
end $$;
select 'OK rpr02_approbation_roles';
rollback;
