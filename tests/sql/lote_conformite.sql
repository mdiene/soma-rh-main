-- Lot E : détection idempotente, dérogation réservée au rôle RH et motivée. Tout est annulé.
-- Attendu : "OK lote_conformite"
begin;
create temp table t_ctx as
select (select user_id from public.user_roles where role = 'rh' order by user_id limit 1) as user_rh,
       (select user_id from public.user_roles where role = 'paie' and user_id not in (select user_id from public.user_roles where role in ('rh','admin')) order by user_id limit 1) as user_paie;
grant select on t_ctx to authenticated;
create or replace function pg_temp.as_user(p_user uuid) returns void language plpgsql as $$
begin execute 'reset role'; execute 'set local role authenticated'; perform set_config('request.jwt.claim.sub', p_user::text, true); end $$;
create or replace function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'OK'; exception when others then return sqlerrm; end $$;
do $$
declare c record; r text; n1 int; n2 int; v_id uuid;
begin
  select * into c from t_ctx;
  if c.user_rh is null or c.user_paie is null then raise exception 'rôles de test manquants'; end if;
  -- départ à vide : la base locale contient déjà des constats ouverts, et la détection ne compte que les nouveaux (annulé en fin de transaction)
  delete from public.compliance_findings;
  perform pg_temp.as_user(c.user_paie);
  n1 := public.detecter_conformite();
  n2 := public.detecter_conformite();
  if n1 = 0 then raise exception 'aucun constat détecté (des salariés sans déclaration sont attendus)'; end if;
  if n2 <> 0 then raise exception 'détection non idempotente : % nouveaux', n2; end if;
  select id into v_id from public.compliance_findings where resolved_on is null limit 1;
  r := pg_temp.try(format('select public.deroger_constat(%L, ''motif'')', v_id));
  if r not like '%rh%' then raise exception 'paie a pu déroger : %', r; end if;
  perform pg_temp.as_user(c.user_rh);
  r := pg_temp.try(format('select public.deroger_constat(%L, ''  '')', v_id));
  if r not like '%motif%' then raise exception 'dérogation sans motif acceptée : %', r; end if;
  r := pg_temp.try(format('select public.deroger_constat(%L, ''Régularisation en cours'')', v_id));
  if r <> 'OK' then raise exception 'rh refusé : %', r; end if;
  raise notice 'OK lote_conformite';
end $$;
rollback;
