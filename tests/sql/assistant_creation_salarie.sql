-- Assistant de création d'un salarié : (1) RH seul crée la fiche, pièces reçues enregistrées ; (2) RH seul ne peut pas affecter la structure ;
-- (3) compte RH + paie crée fiche et structure avec le net cible atteint ; (4) tout ou rien : payload invalide = aucune fiche ;
-- (5) la simulation du net ne laisse aucune fiche et ne consomme pas de matricule ; (6) un compte paie seul ne crée pas de salarié.
-- Tout est annulé. Attendu : "OK assistant_creation_salarie"
begin;
do $$
declare
  v_rh uuid; v_rhpaie uuid; v_paie uuid; v_grade uuid; v_agr text; v_req text;
  v jsonb; v_before int; v_after int; v_seq_before bigint; v_seq_after bigint; v_n int; v_ok boolean;
  emp jsonb; asg jsonb;
begin
  select user_id into v_rh from public.user_roles r where role = 'rh'
     and not exists (select 1 from public.user_roles x where x.user_id = r.user_id and x.role in ('paie', 'admin')) order by user_id limit 1;
  select user_id into v_rhpaie from public.user_roles where role in ('rh', 'admin')
     and user_id in (select user_id from public.user_roles where role in ('paie', 'admin')) order by user_id limit 1;
  select user_id into v_paie from public.user_roles r where role = 'paie'
     and not exists (select 1 from public.user_roles x where x.user_id = r.user_id and x.role in ('rh', 'admin')) order by user_id limit 1;
  select id, agreement_code into v_grade, v_agr from public.employee_grades where base_salary > 0 order by base_salary asc limit 1;
  select code into v_req from public.document_requirements where active order by sort_order limit 1;
  assert v_rh is not null and v_rhpaie is not null and v_paie is not null and v_grade is not null and v_req is not null,
    'FAIL : prérequis absents (comptes rh seul, rh+paie, paie seul, une grille, une pièce requise)';

  emp := jsonb_build_object('first_name', 'TestAssistant', 'last_name', 'Wizard', 'employment_type', 'CDI', 'date_of_joining', '2026-11-02',
                            'agreement_code', v_agr, 'grade_id', v_grade);
  asg := jsonb_build_object('from_date', '2026-11-02');

  execute 'set local role authenticated';

  -- (1) RH seul : fiche + pièces reçues, sans structure
  perform set_config('request.jwt.claim.sub', v_rh::text, true);
  v := public.create_employee_from_wizard(emp, null, array[v_req]);
  assert v->>'employee_number' <> '' and (v->>'structure_assigned')::boolean = false, '(1) fiche créée sans structure';
  select count(*) into v_n from public.employee_document_receipts where employee_id = (v->>'id')::uuid and requirement_code = v_req;
  assert v_n = 1, '(1) pièce reçue enregistrée';

  -- (2) RH seul : l'affectation de la structure est refusée et rien n'est créé
  reset role; select count(*) into v_before from public.employees; execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_rh::text, true);
  begin
    perform public.create_employee_from_wizard(emp, asg, null);
    v_ok := false;
  exception when others then v_ok := sqlerrm like '%relève de la paie%'; end;
  assert v_ok, '(2) RH seul refusé pour la structure';
  reset role; select count(*) into v_after from public.employees; execute 'set local role authenticated';
  assert v_after = v_before, '(2) aucune fiche créée après le refus';

  -- (3) RH + paie : fiche et structure, net cible atteint (à 1 F près)
  perform set_config('request.jwt.claim.sub', v_rhpaie::text, true);
  v := public.create_employee_from_wizard(emp, asg || jsonb_build_object('target_net', 150000), null);
  assert (v->>'structure_assigned')::boolean and (v->>'sursalaire')::numeric > 0, '(3) structure affectée avec sursalaire';
  assert abs((v->>'net_pay')::numeric - 150000) < 1, '(3) net cible atteint : ' || (v->>'net_pay');

  -- (4) tout ou rien : prénom manquant
  reset role; select count(*) into v_before from public.employees; execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_rhpaie::text, true);
  begin
    perform public.create_employee_from_wizard(emp - 'first_name', asg, null);
    v_ok := false;
  exception when others then v_ok := sqlerrm like '%prénom%'; end;
  assert v_ok, '(4) prénom obligatoire';
  reset role; select count(*) into v_after from public.employees; execute 'set local role authenticated';
  assert v_after = v_before, '(4) aucune fiche créée';

  -- (5) simulation : aucune fiche, matricule non consommé, net cible atteint
  reset role; select count(*) into v_before from public.employees; select last_value into v_seq_before from public.employee_number_seq; execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_rhpaie::text, true);
  v := public.simulate_net_for_draft(emp, asg, 120000);
  assert abs((v->>'net_pay')::numeric - 120000) < 1, '(5) net simulé atteint : ' || (v->>'net_pay');
  reset role; select count(*) into v_after from public.employees; select last_value into v_seq_after from public.employee_number_seq; execute 'set local role authenticated';
  assert v_after = v_before, '(5) la simulation ne laisse aucune fiche';
  assert v_seq_after = v_seq_before, '(5) la simulation ne consomme pas de matricule';

  -- (6) un compte paie seul ne crée pas de salarié
  perform set_config('request.jwt.claim.sub', v_paie::text, true);
  begin
    perform public.create_employee_from_wizard(emp, null, null);
    v_ok := false;
  exception when others then v_ok := sqlerrm like '%RH requis%'; end;
  assert v_ok, '(6) paie seul refusé';

  raise notice 'OK assistant_creation_salarie';
end $$;
rollback;
