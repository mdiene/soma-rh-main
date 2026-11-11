-- RPR-08 : plafond de retenue sur prêt — global (admin, rh, paie), surcharge par salarié, journal. Tout est annulé.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/rpr08_plafond_pret.sql  (attendu : "OK rpr08_plafond_pret")
begin;
create temp table t_ctx as
select
  (select user_id from public.user_roles group by user_id having bool_and(role = 'paie') order by user_id limit 1) as paie,
  (select user_id from public.user_roles group by user_id having bool_and(role = 'rh') order by user_id limit 1) as rh,
  (select user_id from public.user_roles group by user_id having bool_and(role = 'salarie') order by user_id limit 1) as sal,
  (select s.employee_id from public.salary_slips s join public.employees e on e.id = s.employee_id
    where e.status = 'Active' and s.status <> 'Annulé' and s.gross_pay > 50000 order by e.employee_number limit 1) as emp;
grant select on t_ctx to authenticated;
create or replace function pg_temp.as_user(p_user uuid) returns void language plpgsql as $$
begin
  execute 'reset role'; execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;
create or replace function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'OK'; exception when others then return sqlerrm; end $$;
do $$
declare c t_ctx; r text; brut numeric; amount numeric; n integer; v numeric;
begin
  select * into c from t_ctx;
  if c.paie is null or c.rh is null or c.sal is null or c.emp is null then raise exception 'jeu de données insuffisant (paie seul, rh seul, salarié seul, salarié avec bulletin)'; end if;

  -- 1. plafond global : modifiable par rh puis par paie, refusé au salarié, journalisé avec l'ancienne valeur
  perform pg_temp.as_user(c.rh);
  r := pg_temp.try('select public.set_loan_max_rate(0.4)');
  if r <> 'OK' then raise exception '1 : rh devait pouvoir modifier le plafond : %', r; end if;
  perform pg_temp.as_user(c.paie);
  r := pg_temp.try('select public.set_loan_max_rate(round(1.0 / 3, 6))');
  if r <> 'OK' then raise exception '1 : paie devait pouvoir modifier le plafond : %', r; end if;
  perform pg_temp.as_user(c.sal);
  r := pg_temp.try('select public.set_loan_max_rate(0.9)');
  if r not like '%Droits insuffisants%' then raise exception '1 : salarié accepté : %', r; end if;
  execute 'reset role';
  select count(*) into n from public.audit_events where action = 'plafond_pret_global' and actor_id = c.rh and (before_data->>'rate')::numeric = round(1.0 / 3, 6) and (after_data->>'rate')::numeric = 0.4;
  if n <> 1 then raise exception '1 : changement du plafond global non journalisé (ancienne et nouvelle valeur)'; end if;

  -- 2. surcharge par salarié : motif obligatoire, valeur bornée, refusée au salarié
  perform pg_temp.as_user(c.paie);
  r := pg_temp.try(format('select public.set_employee_loan_cap(%L, 0.5, ''ok'')', c.emp));
  if r not like '%motif%' then raise exception '2 : motif trop court accepté : %', r; end if;
  r := pg_temp.try(format('select public.set_employee_loan_cap(%L, 1.5, ''Situation particulière'')', c.emp));
  if r not like '%compris entre 0 et 1%' then raise exception '2 : taux invalide accepté : %', r; end if;
  perform pg_temp.as_user(c.sal);
  r := pg_temp.try(format('select public.set_employee_loan_cap(%L, 0.5, ''Situation particulière'')', c.emp));
  if r not like '%Droits insuffisants%' then raise exception '2 : salarié a modifié une surcharge : %', r; end if;

  -- 3. effet sur create_loan : une retenue à 40 % du brut est refusée au plafond global (1/3), acceptée avec une surcharge à 50 %
  execute 'reset role';
  select gross_pay into brut from public.salary_slips where employee_id = c.emp and status <> 'Annulé' and gross_pay > 0 order by period_start desc limit 1;
  amount := floor(brut * 0.4);
  perform pg_temp.as_user(c.paie);
  r := pg_temp.try(format('select public.create_loan(%L, ''test plafond'', %s, 1, ''2030-01-01'')', c.emp, amount));
  if r not like '%Retenue mensuelle trop élevée%' then raise exception '3 : retenue à 40 %% acceptée sans surcharge : %', r; end if;
  r := pg_temp.try(format('select public.set_employee_loan_cap(%L, 0.5, ''Situation particulière'')', c.emp));
  if r <> 'OK' then raise exception '3 : surcharge refusée : %', r; end if;
  v := public.get_employee_loan_cap(c.emp);
  if v <> 0.5 then raise exception '3 : plafond du salarié %, attendu 0,5', v; end if;
  r := pg_temp.try(format('select public.create_loan(%L, ''test plafond'', %s, 1, ''2030-01-01'')', c.emp, amount));
  if r <> 'OK' then raise exception '3 : prêt refusé malgré la surcharge à 50 %% : %', r; end if;

  -- 4. suppression de la surcharge : retour au plafond global, journalisé
  r := pg_temp.try(format('select public.set_employee_loan_cap(%L, null, ''Retour au plafond global'')', c.emp));
  if r <> 'OK' then raise exception '4 : suppression refusée : %', r; end if;
  if public.get_employee_loan_cap(c.emp) = 0.5 then raise exception '4 : surcharge conservée'; end if;
  execute 'reset role';
  select count(*) into n from public.audit_events where action = 'plafond_pret_salarie' and resource_id = c.emp;
  if n <> 2 then raise exception '4 : % ligne(s) de journal, attendu 2', n; end if;
end $$;
select 'OK rpr08_plafond_pret';
rollback;
