-- RPR-14 : numérotation des matricules paramétrable (préfixe, nombre de chiffres) par l'administrateur seul, avec journal. Tout est annulé.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/rpr14_matricule_parametrable.sql  (attendu : "OK rpr14_matricule_parametrable")
-- p_next et next_employee_number ne sont pas appelés : setval et nextval ne sont pas annulés par la transaction (aperçu seulement).
begin;
create temp table t_ctx as
select
  (select user_id from public.user_roles where role = 'admin' order by user_id limit 1) as admin,
  (select user_id from public.user_roles group by user_id having bool_and(role = 'rh') order by user_id limit 1) as rh,
  (select id from public.employees order by employee_number limit 1) as emp;
grant select on t_ctx to authenticated;
create or replace function pg_temp.as_user(p_user uuid) returns void language plpgsql as $$
begin
  execute 'reset role'; execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;
create or replace function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'OK'; exception when others then return sqlerrm; end $$;
do $$
declare c t_ctx; r text; v text; n integer;
begin
  select * into c from t_ctx;
  if c.admin is null or c.rh is null or c.emp is null then raise exception 'jeu de données insuffisant'; end if;

  -- 1. par défaut : « S » et 4 chiffres, comme avant
  perform pg_temp.as_user(c.admin);
  v := public.preview_employee_number();
  if v !~ '^S[0-9]{4}$' then raise exception '1 : numérotation par défaut inattendue : %', v; end if;

  -- 2. seul l'administrateur modifie ; valeurs invalides refusées
  perform pg_temp.as_user(c.rh);
  r := pg_temp.try('select public.set_employee_number_settings(''SOMA'', 5)');
  if r not like '%Seul un administrateur%' then raise exception '2 : rh a modifié la numérotation : %', r; end if;
  perform pg_temp.as_user(c.admin);
  r := pg_temp.try('select public.set_employee_number_settings(''so ma'', 5)');
  if r not like '%1 à 6 lettres%' then raise exception '2 : préfixe invalide accepté : %', r; end if;
  r := pg_temp.try('select public.set_employee_number_settings(''SOMA'', 2)');
  if r not like '%entre 3 et 8%' then raise exception '2 : largeur invalide acceptée : %', r; end if;

  -- 3. préfixe SOMA, 5 chiffres : l'aperçu et l'attribution suivent
  r := pg_temp.try('select public.set_employee_number_settings(''soma'', 5)');
  if r <> 'OK' then raise exception '3 : modification refusée : %', r; end if;
  v := public.preview_employee_number();
  if v !~ '^SOMA[0-9]{5}$' then raise exception '3 : aperçu après modification : %', v; end if;

  -- 4. le changement manuel de matricule accepte le nouveau format
  r := pg_temp.try(format('select public.admin_change_employee_number(%L, ''SOMA00001'', ''Test de numérotation'')', c.emp));
  if r <> 'OK' then raise exception '4 : changement de matricule refusé : %', r; end if;

  -- 5. journalisé avec l'ancienne et la nouvelle valeur
  execute 'reset role';
  select count(*) into n from public.audit_events where action = 'parametrage_matricule' and actor_id = c.admin
    and before_data->>'prefix' = 'S' and after_data->>'prefix' = 'SOMA';
  if n <> 1 then raise exception '5 : modification non journalisée'; end if;
end $$;
select 'OK rpr14_matricule_parametrable';
rollback;
