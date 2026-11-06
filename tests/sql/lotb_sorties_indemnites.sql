-- Lot B : indemnités de sortie lues dans exit_reasons (C26-04, C26-05, C26-28). Tout est annulé.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/lotb_sorties_indemnites.sql  (attendu : "OK lotb_sorties_indemnites")
-- Aucun identifiant de salarié n'est affiché.
begin;
do $$
declare
  emp uuid; rh uuid; rec record; t jsonb; r jsonb;
begin
  select e.id into emp from public.employees e
   where e.status = 'Active' and e.employment_type = 'CDI' and e.relieving_date is null
     and exists (select 1 from public.salary_structure_assignments a where a.employee_id = e.id)
   order by e.employee_number limit 1;
  if emp is null then raise exception 'FAIL : prérequis absents (salarié CDI avec structure de paie)'; end if;

  -- (motif, mois d'ancienneté, licenciement attendu, spéciale attendue, funéraires attendus) ; true = montant > 0
  for rec in
    select * from (values
      ('DEMISSION',                 24, false, false, false),
      ('LICENCIEMENT_FAUTE_LOURDE', 24, false, false, false),
      ('LICENCIEMENT_PERSONNEL',     6, false, false, false),   -- < 12 mois : pas d'indemnité (C26-05)
      ('LICENCIEMENT_PERSONNEL',    24, true,  false, false),
      ('LICENCIEMENT',               6, false, false, false),   -- ancien code = LICENCIEMENT_PERSONNEL
      ('LICENCIEMENT_ECONOMIQUE',    6, false, true,  false),   -- spéciale due sans condition d'ancienneté
      ('LICENCIEMENT_ECONOMIQUE',   24, true,  true,  false),
      ('CESSATION_ACTIVITE',        24, true,  true,  false),
      ('PLAN_SOCIAL',               24, true,  true,  false),
      ('DECES',                      6, false, false, true),    -- décès < 1 an : frais funéraires seulement
      ('DECES',                     24, true,  false, true)
    ) as v(code, months, sev, spec, fun)
  loop
    update public.employees
       set relieving_date = date '2026-08-31',
           date_of_joining = date '2026-08-31' - (rec.months || ' months')::interval + interval '1 day',
           exit_reason = rec.code
     where id = emp;
    t := (public.compute_salary_slip(emp, date '2026-08-01', date '2026-08-31'))->'totals';
    if ((t->>'severance_pay')::numeric > 0) is distinct from rec.sev then
      raise exception 'FAIL : % à % mois, indemnité de licenciement % attendue %', rec.code, rec.months, t->>'severance_pay', rec.sev; end if;
    if ((t->>'special_indemnity')::numeric > 0) is distinct from rec.spec then
      raise exception 'FAIL : % à % mois, indemnité spéciale % attendue %', rec.code, rec.months, t->>'special_indemnity', rec.spec; end if;
    if ((t->>'funeral_indemnity')::numeric > 0) is distinct from rec.fun then
      raise exception 'FAIL : % à % mois, frais funéraires % attendus %', rec.code, rec.months, t->>'funeral_indemnity', rec.fun; end if;
  end loop;

  -- RETRAITE : indemnité de départ inchangée, pas d'indemnité de licenciement
  update public.employees set exit_reason = 'RETRAITE' where id = emp;
  t := (public.compute_salary_slip(emp, date '2026-08-01', date '2026-08-31'))->'totals';
  if (t->>'retirement_pay')::numeric <= 0 or (t->>'severance_pay')::numeric <> 0 then raise exception 'FAIL : retraite (%)', t; end if;

  -- sortie_salarie accepte les nouveaux motifs et refuse les inconnus
  update public.employees set relieving_date = null, exit_reason = null, status = 'Active' where id = emp;
  select user_id into rh from public.user_roles where role = 'rh' limit 1;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', rh::text, true);
  begin
    perform public.sortie_salarie(emp, current_date, 'MOTIF_INCONNU');
    raise exception 'FAIL : motif inconnu accepté';
  exception when others then
    if sqlerrm not like 'Motif de sortie invalide%' then raise exception 'FAIL : message inattendu (%)', sqlerrm; end if;
  end;
  r := public.sortie_salarie(emp, current_date, 'PLAN_SOCIAL');
  if r->>'exit_reason' <> 'PLAN_SOCIAL' then raise exception 'FAIL : PLAN_SOCIAL non enregistré'; end if;
  execute 'reset role';

  raise notice 'OK lotb_sorties_indemnites';
end $$;
rollback;
