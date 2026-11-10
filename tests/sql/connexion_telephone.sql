-- Connexion par téléphone (autorisation par l'administrateur) : normalisation, demande neutre, limites, autorisation,
-- ouverture (seconde information, verrou), finalisation, jeton à usage unique, expiration, verrou de rôle (y compris admin),
-- changement de numéro, droits (rh/paie ne peuvent pas autoriser). Données synthétiques ; tout est annulé.
-- Attendu : "OK connexion_telephone"
begin;
do $$
declare
  v_co uuid; v_e1 uuid; v_e2 uuid; v_e3 uuid; v_req uuid; v_user uuid; v_admin uuid; v_rh uuid; v_paie uuid;
  v_tok text := 'tok-' || gen_random_uuid(); n int; t text;
begin
  select id into v_co from public.companies limit 1;
  select user_id into v_admin from public.user_roles where role = 'admin' order by user_id limit 1;
  select user_id into v_rh from public.user_roles ur where role = 'rh'
    and not exists (select 1 from public.user_roles x where x.user_id = ur.user_id and x.role = 'admin') order by user_id limit 1;
  select user_id into v_paie from public.user_roles ur where role = 'paie'
    and not exists (select 1 from public.user_roles x where x.user_id = ur.user_id and x.role in ('admin', 'rh')) order by user_id limit 1;
  assert v_co is not null and v_admin is not null and v_rh is not null, 'données de test manquantes';

  insert into public.employees (company_id, employee_number, first_name, last_name, employment_type, date_of_joining, status, phone_personal, date_of_birth)
  values (v_co, 'TEL-T1', 'Awa', 'Diop', 'CDI', '2020-01-01', 'Active', '77 123 45 67', '1990-05-17') returning id into v_e1;
  insert into public.employees (company_id, employee_number, first_name, last_name, employment_type, date_of_joining, status, phone_personal, date_of_birth)
  values (v_co, 'TEL-T2', 'Moussa', 'Fall', 'CDI', '2020-01-01', 'Active', '+221 76 000 11 22', '1985-01-02') returning id into v_e2;
  insert into public.employees (company_id, employee_number, first_name, last_name, employment_type, date_of_joining, status, phone_personal, date_of_birth)
  values (v_co, 'TEL-T3', 'Fatou', 'Ndiaye', 'CDI', '2020-01-01', 'Active', '00221 76 000 11 22', '1986-03-04') returning id into v_e3;

  -- (1) normalisation
  assert public.phone_normalize('77 123 45 67') = '+221771234567', 'normalisation : espaces';
  assert public.phone_normalize('00221771234567') = '+221771234567', 'normalisation : 00221';
  assert public.phone_normalize('+221-77-123-45-67') = '+221771234567', 'normalisation : +221';
  assert public.phone_normalize('331234567') is null, 'fixe refusé';
  assert public.phone_normalize('7712345') is null, 'trop court refusé';
  assert public.phone_normalize('') is null and public.phone_normalize(null) is null, 'vide';

  -- (2) numéro inconnu : rien n'est créé ; numéro valide : une demande ; redemande : compteur
  perform public.phone_access_request('78 999 99 99', 'ip1');
  select count(*) into n from public.phone_access_requests where phone_e164 = '+221789999999';
  assert n = 0, 'numéro inconnu : aucune demande';
  perform public.phone_access_request('77 123 45 67', 'ip1');
  select id into v_req from public.phone_access_requests where employee_id = v_e1 and status = 'pending';
  assert v_req is not null, 'une demande en attente attendue';
  perform public.phone_access_request('771234567', 'ip1');
  assert (select repeat_count from public.phone_access_requests where id = v_req) = 1, 'redemande comptée';

  -- (3) numéro partagé par deux fiches : alerte discrète, aucune demande rattachée à une fiche
  perform public.phone_access_request('76 000 11 22', 'ip2');
  select count(*) into n from public.phone_access_requests where purpose = 'shared' and phone_e164 = '+221760001122' and employee_id is null;
  assert n = 1, 'numéro partagé : une alerte';
  assert (select count(*) from public.phone_access_requests where employee_id in (v_e2, v_e3)) = 0, 'numéro partagé : pas de demande de fiche';

  -- (4) limite : 3 demandes par numéro et par 24 h (la 4e est ignorée sans erreur)
  perform public.phone_access_request('77 123 45 67', 'ip3');
  perform public.phone_access_request('77 123 45 67', 'ip4');
  assert (select count(*) from public.phone_access_attempts where kind = 'request' and phone_e164 = '+221771234567') = 3, 'limite 3 par numéro';

  -- (5) tant que l'administrateur n'a rien autorisé, l'ouverture échoue
  assert not public.phone_access_open('77 123 45 67', '1990-05-17', 'ipx', 'h-early'), 'ouverture sans autorisation refusée';

  -- (6) droits : rh et paie ne peuvent pas autoriser, l'administrateur oui
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_rh::text, true);
  begin
    perform public.admin_phone_access_decide(v_req, true, null);
    raise exception 'FAIL : rh a pu autoriser';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  if v_paie is not null then
    perform set_config('request.jwt.claim.sub', v_paie::text, true);
    begin
      perform public.admin_phone_access_decide(v_req, true, null);
      raise exception 'FAIL : paie a pu autoriser';
    exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  end if;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform public.admin_phone_access_decide(v_req, true, 'Contacté par téléphone');
  assert exists (select 1 from public.legal_alerts() where code in ('phone_access_request', 'phone_access_shared')), 'alerte visible chez l''administrateur (numéro partagé)';
  execute 'reset role';
  assert (select status from public.phone_access_requests where id = v_req) = 'authorized', 'autorisation enregistrée';
  assert (select expires_at from public.phone_access_requests where id = v_req) between now() + interval '47 hours' and now() + interval '49 hours', 'validité 48 h';

  -- (7) ouverture : mauvaise seconde information ×5 puis verrou du numéro (même avec la bonne date)
  for i in 1..5 loop
    assert not public.phone_access_open('77 123 45 67', '1990-05-18', 'ipx', 'h-bad' || i), 'mauvaise date refusée';
  end loop;
  assert not public.phone_access_open('77 123 45 67', '1990-05-17', 'ipx', 'h-locked'), 'numéro verrouillé même avec la bonne date';
  -- fin du verrou : on antidate les échecs
  update public.phone_access_attempts set occurred_at = now() - interval '31 minutes' where kind = 'second_factor_fail';
  assert public.phone_access_open('+221 77 123 45 67', '1990-05-17', 'ipy', 'h-' || v_tok), 'ouverture avec la bonne date';
  assert exists (select 1 from public.phone_access_peek('h-' || v_tok)), 'jeton lisible';

  -- (8) finalisation : compte relié à la fiche, rôle salarie, jeton à usage unique
  v_user := gen_random_uuid();
  insert into auth.users (id, email, encrypted_password, email_confirmed_at) values (v_user, '221771234567@tel.soma-rh.invalid', 'x', now());
  perform public.phone_access_complete('h-' || v_tok, v_user);
  assert (select user_id from public.employees where id = v_e1) = v_user, 'fiche reliée au compte';
  assert (select array_agg(role) from public.user_roles where user_id = v_user) = array['salarie'], 'rôle salarie seul';
  assert (select status from public.phone_access_requests where id = v_req) = 'used', 'autorisation consommée';
  begin
    perform public.phone_access_complete('h-' || v_tok, v_user);
    raise exception 'FAIL : jeton réutilisé';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  assert not public.phone_access_open('77 123 45 67', '1990-05-17', 'ipz', 'h-again'), 'autorisation à usage unique';

  -- (9) verrou de rôle : refusé pour tout rôle autre que salarie, y compris en tant qu'administrateur et superutilisateur
  foreach t in array array['rh', 'paie', 'admin', 'manager'] loop
    begin
      insert into public.user_roles (user_id, role) values (v_user, t);
      raise exception 'FAIL : rôle % accepté (propriétaire)', t;
    exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  end loop;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  foreach t in array array['rh', 'paie', 'admin', 'manager'] loop
    begin
      insert into public.user_roles (user_id, role) values (v_user, t);
      raise exception 'FAIL : rôle % accepté (administrateur)', t;
    exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  end loop;
  begin
    perform public.admin_link_employee(v_user, null);
    raise exception 'FAIL : compte téléphone délié';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  execute 'reset role';
  begin
    update public.user_roles set role = 'admin' where user_id = v_user;
    raise exception 'FAIL : promotion par update acceptée';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;

  -- (10) statut sur la fiche, puis réinitialisation : demande de type reset, nouvelle autorisation, expiration
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_rh::text, true);
  assert public.employee_phone_access_status(v_e1) = 'actif', 'statut actif';
  assert public.employee_phone_access_status(v_e2) = 'non demandé', 'statut non demandé';
  execute 'reset role';
  update public.phone_access_attempts set occurred_at = now() - interval '2 days';
  perform public.phone_access_request('77 123 45 67', 'ip9');
  select id into v_req from public.phone_access_requests where employee_id = v_e1 and status = 'pending';
  assert (select purpose from public.phone_access_requests where id = v_req) = 'reset', 'réinitialisation';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform public.admin_phone_access_decide(v_req, true, null);
  execute 'reset role';
  update public.phone_access_requests set expires_at = now() - interval '1 minute' where id = v_req;
  assert not public.phone_access_open('77 123 45 67', '1990-05-17', 'ipw', 'h-expired'), 'autorisation expirée refusée';
  assert (select status from public.phone_access_requests where id = v_req) = 'expired', 'statut expirée';

  -- (11) refus puis révocation ; changement de numéro : compte désactivé
  perform public.phone_access_request('77 123 45 67', 'ip10');
  select id into v_req from public.phone_access_requests where employee_id = v_e1 and status = 'pending';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform public.admin_phone_access_decide(v_req, false, 'Refus de test');
  assert exists (select 1 from public.admin_phone_access_requests() where id = v_req and status = 'refused'), 'refus enregistré';
  assert exists (select 1 from public.admin_phone_access_accounts() where employee_id = v_e1 and status = 'active'), 'compte listé';
  perform public.admin_phone_access_revoke(v_e1);
  execute 'reset role';
  assert (select status from public.phone_access_accounts where employee_id = v_e1) = 'revoked', 'compte révoqué';
  assert (select user_id from public.employees where id = v_e1) is null, 'fiche déliée après révocation';
  assert not exists (select 1 from public.user_roles where user_id = v_user), 'rôles retirés après révocation';

  update public.phone_access_accounts set status = 'active' where employee_id = v_e1;
  update public.employees set phone_personal = '78 111 22 33' where id = v_e1;
  assert (select status from public.phone_access_accounts where employee_id = v_e1) = 'disabled', 'numéro modifié : compte désactivé';

  -- (12) l'audit existe et ne contient aucun mot de passe
  select count(*) into n from public.audit_log where table_name = 'phone_access';
  assert n >= 8, 'événements journalisés (' || n || ')';
  assert not exists (select 1 from public.audit_log where table_name = 'phone_access' and new_data::text ilike '%password%'), 'aucun mot de passe dans le journal';
  raise notice 'OK connexion_telephone';
end $$;
rollback;
