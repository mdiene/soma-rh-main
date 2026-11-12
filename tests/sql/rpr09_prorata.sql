-- RPR-09 / D-56 : prorata des jours travaillés à l'entrée et à la sortie en cours de mois. Tout est annulé.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/rpr09_prorata.sql  (attendu : "OK rpr09_prorata")
-- Jeux de dates : janvier 2026 (27 jours ouvrables lundi-samedi, 31 calendaires), octobre 2026 (27 ouvrables).
begin;
create or replace function pg_temp.gain(p_slip jsonb, p_code text) returns numeric language sql as $$
  select coalesce(sum((l->>'gain')::numeric), 0) from jsonb_array_elements(p_slip->'lines') l where l->>'code' = p_code $$;
create or replace function pg_temp.near(a numeric, b numeric, p_what text) returns void language plpgsql as $$
begin if abs(a - b) > 0.01 then raise exception '% : obtenu %, attendu %', p_what, a, b; end if; end $$;
do $$
declare
  emp uuid; base numeric; transp numeric; s jsonb; s0 jsonb;
begin
  -- salarié témoin : actif, structure affectée avec prime de transport et sans variable saisie
  select e.id into emp from public.employees e
    join public.salary_structure_assignments a on a.employee_id = e.id and a.transport_mode = 'Prime de transport'
   where e.status = 'Active' and e.relieving_date is null and e.date_of_joining <= '2026-01-01'
     and not exists (select 1 from public.payroll_inputs i where i.employee_id = e.id and i.period in ('2026-01-01', '2026-10-01'))
   order by e.employee_number limit 1;
  if emp is null then raise exception 'aucun salarié témoin'; end if;

  if not exists (select 1 from public.salary_components where code = 'RET_PRORATA') then raise exception 'RET_PRORATA absent du référentiel salary_components'; end if;

  -- 1. aucun changement en cours de mois : pas de ligne de prorata
  s0 := public.compute_salary_slip(emp, '2026-01-01', '2026-01-31');
  if pg_temp.gain(s0, 'RET_PRORATA') <> 0 then raise exception 'prorata sur un mois complet'; end if;
  base := pg_temp.gain(s0, 'SAL_BASE');
  transp := pg_temp.gain(s0, 'IND_TRANSPORT');

  -- 2. entrée le 15/01 (ouvrables) : 15 jours sur 27 (du 15 au 31, moins les dimanches 18 et 25)
  update public.employees set date_of_joining = '2026-01-15' where id = emp;
  s := public.compute_salary_slip(emp, '2026-01-01', '2026-01-31');
  perform pg_temp.near(pg_temp.gain(s, 'RET_PRORATA'), -base * 12 / 27, 'retenue prorata entrée (ouvrables)');
  perform pg_temp.near(pg_temp.gain(s, 'IND_TRANSPORT'), transp * 15 / 27, 'transport prorata entrée');
  if (s->'totals'->>'net_pay')::numeric >= (s0->'totals'->>'net_pay')::numeric then raise exception 'net non réduit par le prorata'; end if;

  -- 3. base calendaire : 14 jours sur 31 (du 15 au 31 = 17 jours, retenue sur les 14 jours non travaillés)
  -- le garde-fou « paramètres déjà utilisés » interdit la modification : on le contourne dans cette transaction annulée
  set local session_replication_role = replica;
  update public.payroll_settings set proration_basis = 'calendaires'
   where effective_from = (select max(effective_from) from public.payroll_settings where effective_from <= '2026-01-31');
  s := public.compute_salary_slip(emp, '2026-01-01', '2026-01-31');
  perform pg_temp.near(pg_temp.gain(s, 'RET_PRORATA'), -base * 14 / 31, 'retenue prorata entrée (calendaires)');
  update public.payroll_settings set proration_basis = 'ouvrables' where proration_basis = 'calendaires';

  -- 4. sortie le 23/10 (ouvrables) : 20 jours sur 27 (du 1er au 23, moins les dimanches 4, 11 et 18)
  update public.employees set date_of_joining = '2026-01-01', relieving_date = '2026-10-23', exit_reason = 'DEMISSION' where id = emp;
  s0 := public.compute_salary_slip(emp, '2026-10-01', '2026-10-31');
  perform pg_temp.near(pg_temp.gain(s0, 'RET_PRORATA'), -pg_temp.gain(s0, 'SAL_BASE') * 7 / 27, 'retenue prorata sortie');

  -- 5. sortie le dernier jour du mois : pas de prorata
  update public.employees set relieving_date = '2026-10-31' where id = emp;
  s := public.compute_salary_slip(emp, '2026-10-01', '2026-10-31');
  if pg_temp.gain(s, 'RET_PRORATA') <> 0 then raise exception 'prorata pour une sortie le dernier jour du mois'; end if;

  -- 6. paramètre invalide refusé
  begin
    update public.payroll_settings set proration_basis = 'hebdomadaires' where id = (select id from public.payroll_settings limit 1);
    raise exception 'base de prorata invalide acceptée';
  exception when check_violation then null;
  end;
end $$;
select 'OK rpr09_prorata';
rollback;
