-- Historique des emplois : (1) reprise, (2) changement d'emploi = fermeture + ouverture, (3) correction le jour même sans période vide,
-- (4) pas de chevauchement, (5) droits : RH écrit, paie lit, personne d'autre. Tout est annulé.
-- Attendu : "OK job_history"
begin;
do $$
declare
  v_emp uuid; v_d1 uuid; v_d2 uuid; v_start date; n int; r public.employee_job_history; v_rh uuid; v_paie uuid; v_other uuid;
begin
  select e.id, e.designation_id, e.date_of_joining into v_emp, v_d1, v_start from public.employees e
   where e.designation_id is not null and e.status = 'Active' and e.date_of_joining < current_date order by e.id limit 1;
  select id into v_d2 from public.designations where id <> v_d1 order by id limit 1;
  select user_id into v_rh from public.user_roles where role = 'rh' order by user_id limit 1;
  select user_id into v_paie from public.user_roles ur where role = 'paie'
    and not exists (select 1 from public.user_roles x where x.user_id = ur.user_id and x.role in ('rh', 'admin')) order by user_id limit 1;
  select u.id into v_other from auth.users u where not exists (select 1 from public.user_roles x where x.user_id = u.id and x.role in ('rh', 'paie', 'admin')) order by u.id limit 1;
  assert v_emp is not null and v_d2 is not null and v_rh is not null, 'données de test manquantes';

  -- (1) reprise : une période ouverte depuis l'entrée
  select * into r from public.employee_job_history where employee_id = v_emp and valid_to is null;
  assert r.id is not null and r.valid_from = v_start and r.designation_id = v_d1, 'reprise : période ouverte attendue';

  -- (2) changement d'emploi : l'ancienne période se ferme la veille, la nouvelle s'ouvre aujourd'hui
  update public.employees set designation_id = v_d2 where id = v_emp;
  select count(*) into n from public.employee_job_history where employee_id = v_emp and designation_id = v_d1 and valid_to = current_date - 1;
  assert n = 1, 'ancienne période non fermée à la veille';
  select * into r from public.employee_job_history where employee_id = v_emp and valid_to is null;
  assert r.designation_id = v_d2 and r.valid_from = current_date, 'nouvelle période non ouverte aujourd''hui';

  -- (3) nouveau changement le jour même : correction de la période ouverte, pas de période vide
  update public.employees set designation_id = v_d1 where id = v_emp;
  select count(*) into n from public.employee_job_history where employee_id = v_emp and valid_from = current_date;
  assert n = 1, 'changement le jour même : une seule période attendue (' || n || ')';
  select * into r from public.employee_job_history where employee_id = v_emp and valid_to is null;
  assert r.designation_id = v_d1, 'correction du jour : emploi attendu ' || v_d1;

  -- (4) chevauchement refusé
  begin
    insert into public.employee_job_history(employee_id, title, valid_from, valid_to) values (v_emp, 'Chevauchement', v_start, v_start + 5);
    raise exception 'FAIL : chevauchement accepté';
  exception when exclusion_violation then null; end;

  -- (5) droits
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_rh::text, true);
  insert into public.employee_job_history(employee_id, title, valid_from, valid_to) values (v_emp, 'Ancien poste', v_start - 400, v_start - 300);
  if v_paie is not null then
    perform set_config('request.jwt.claim.sub', v_paie::text, true);
    select count(*) into n from public.employee_job_history where employee_id = v_emp;
    assert n >= 3, 'paie : lecture';
    begin
      insert into public.employee_job_history(employee_id, title, valid_from, valid_to) values (v_emp, 'Interdit', v_start - 900, v_start - 800);
      raise exception 'FAIL : écriture de la paie acceptée';
    exception when insufficient_privilege then null; end;
  end if;
  if v_other is not null then
    perform set_config('request.jwt.claim.sub', v_other::text, true);
    select count(*) into n from public.employee_job_history;
    assert n = 0, 'sans rôle : rien de visible (' || n || ')';
  end if;
  execute 'reset role';
  raise notice 'OK job_history';
end $$;
rollback;
