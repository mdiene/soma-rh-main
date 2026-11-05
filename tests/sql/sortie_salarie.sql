-- DEV-06 : sortie_salarie, solde_tout_compte, certificat_travail. Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/sortie_salarie.sql
-- (attendu : "OK sortie_salarie") ; tout est annulé. Prérequis : comptes QA créés (scripts/qa-create-users.ps1).
begin;
create temp table t_ctx as
select e.id as emp, e.user_id as emp_user,
       (select id from auth.users where email = 'qa-rh@example.test') as rh,
       (select id from auth.users where email = 'qa-salarie@example.test') as sal
from public.employees e
where e.status = 'Active' and e.relieving_date is null
  and exists (select 1 from public.salary_structure_assignments a where a.employee_id = e.id)
order by e.employee_number limit 1;
grant select on t_ctx to authenticated;

create or replace function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'OK'; exception when others then return sqlerrm; end $$;

do $$
declare c t_ctx; r jsonb; s jsonb; cert text; msg text; e public.employees;
begin
  select * into c from t_ctx;
  if c.emp is null or c.rh is null then raise exception 'FAIL : prérequis absents (salarié avec structure de paie, compte qa-rh)'; end if;

  -- un salarié ne peut pas enregistrer de sortie
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', c.sal::text, true);
  msg := pg_temp.try(format('select public.sortie_salarie(%L, current_date, ''DEMISSION'')', c.emp));
  if msg not like '%Réservé au service RH%' then raise exception 'FAIL : un non-RH peut enregistrer une sortie (%)', msg; end if;
  execute 'reset role';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', c.rh::text, true);
  -- le solde et le certificat exigent une sortie enregistrée
  msg := pg_temp.try(format('select public.solde_tout_compte(%L)', c.emp));
  if msg not like '%sortie_salarie%' then raise exception 'FAIL : solde accepté sans sortie (%)', msg; end if;
  msg := pg_temp.try(format('select public.certificat_travail(%L)', c.emp));
  if msg not like '%sortie_salarie%' then raise exception 'FAIL : certificat accepté sans sortie (%)', msg; end if;
  -- motif invalide
  msg := pg_temp.try(format('select public.sortie_salarie(%L, current_date, ''AUTRE'')', c.emp));
  if msg not like 'Motif de sortie invalide%' then raise exception 'FAIL : motif invalide accepté (%)', msg; end if;

  r := public.sortie_salarie(c.emp, current_date, 'LICENCIEMENT');
  execute 'reset role';
  select * into e from public.employees where id = c.emp;
  if e.status <> 'Left' or e.relieving_date <> current_date or e.exit_reason <> 'LICENCIEMENT' then raise exception 'FAIL : sortie non enregistrée'; end if;
  if c.emp_user is not null and exists (select 1 from public.user_roles where user_id = c.emp_user) then raise exception 'FAIL : accès non retirés'; end if;
  if exists (select 1 from public.employee_manager_assignments where employee_id = c.emp and (valid_to is null or valid_to > current_date)) then
    raise exception 'FAIL : rattachement au manager non clos'; end if;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', c.rh::text, true);
  msg := pg_temp.try(format('select public.sortie_salarie(%L, current_date, ''DEMISSION'')', c.emp));
  if msg not like '%déjà enregistrée%' then raise exception 'FAIL : double sortie acceptée (%)', msg; end if;

  s := public.solde_tout_compte(c.emp);
  cert := public.certificat_travail(c.emp);
  execute 'reset role';
  if (s->>'net_pay') is null or (s->>'total_due')::numeric < (s->>'net_pay')::numeric then raise exception 'FAIL : solde incohérent (%)', s - 'slip'; end if;
  if jsonb_typeof(s->'slip'->'lines') <> 'array' then raise exception 'FAIL : bulletin de sortie absent'; end if;
  if cert not like '%' || e.employee_number || '%' or cert not like '%' || to_char(e.date_of_joining, 'DD/MM/YYYY') || '%' then raise exception 'FAIL : certificat sans matricule ou date d''entrée'; end if;
  if cert ~* 'impôt|FCFA|salaire' then raise exception 'FAIL : le certificat ne doit pas contenir de donnée de paie'; end if;
  raise notice 'OK sortie_salarie';
end $$;
rollback;
