-- D-43 : validation directe d'une paie « Calculée » refusée sans approbation (paie) ou sans motif (admin). Tout est annulé.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/d43_approbation.sql  (attendu : "OK d43_approbation")
begin;
create temp table t_ctx as
select
  (select user_id from public.user_roles where role = 'admin' order by user_id limit 1) as user_admin,
  (select user_id from public.user_roles where role = 'paie' and user_id not in (select user_id from public.user_roles where role = 'admin') order by user_id limit 1) as user_paie,
  (select id from public.payroll_entries where status = 'Calculée' order by period_start limit 1) as entry;
grant select on t_ctx to authenticated;
create or replace function pg_temp.as_user(p_user uuid) returns void language plpgsql as $$
begin
  execute 'reset role'; execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;
create or replace function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'OK'; exception when others then return sqlerrm; end $$;
do $$
declare c record; r text;
begin
  select * into c from t_ctx;
  if c.entry is null then raise exception 'Aucune paie Calculée : test non significatif'; end if;
  perform pg_temp.as_user(c.user_paie);
  r := pg_temp.try(format('select public.transition_payroll_entry(%L, ''Validée'', ''motif'')', c.entry));
  if r not like '%approuvée%' then raise exception 'paie : validation directe acceptée ou autre erreur : %', r; end if;
  perform pg_temp.as_user(c.user_admin);
  r := pg_temp.try(format('select public.transition_payroll_entry(%L, ''Validée'', null)', c.entry));
  if r not like '%motif de dérogation%' then raise exception 'admin sans motif : %', r; end if;
  raise notice 'OK d43_approbation';
end $$;
rollback;
