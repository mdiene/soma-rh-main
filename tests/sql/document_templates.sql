-- L6-04 : modèles de documents. La RH modifie (version +1), la paie lit sans modifier, un compte sans rôle ne voit rien. Tout est annulé.
-- Attendu : "OK document_templates"
begin;
do $$
declare
  v_rh uuid; v_paie uuid; v_other uuid; n int; ver int; b text;
begin
  select user_id into v_rh from public.user_roles where role = 'rh' order by user_id limit 1;
  select user_id into v_paie from public.user_roles r where role = 'paie'
    and not exists (select 1 from public.user_roles x where x.user_id = r.user_id and x.role in ('rh', 'admin')) order by user_id limit 1;
  select u.id into v_other from auth.users u where not exists (select 1 from public.user_roles x where x.user_id = u.id and x.role in ('rh', 'paie', 'admin')) order by u.id limit 1;
  assert v_rh is not null, 'compte RH manquant';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_rh::text, true);
  select version into ver from public.document_templates where code = 'attestation_travail';
  assert ver is not null, 'modèle de départ absent';
  assert exists (select 1 from public.document_templates where code = 'certificat_travail'), 'modèle du certificat de travail absent';
  update public.document_templates set body = body || E'\n\nAjout de test' where code = 'attestation_travail';
  select version, body into ver, b from public.document_templates where code = 'attestation_travail';
  assert ver = 2 and b like '%Ajout de test', 'RH : modification + version +1 (' || ver || ')';

  if v_paie is not null then
    perform set_config('request.jwt.claim.sub', v_paie::text, true);
    select count(*) into n from public.document_templates;
    assert n >= 2, 'paie : lecture';
    update public.document_templates set body = 'interdit' where code = 'attestation_travail';
    get diagnostics n = row_count;
    assert n = 0, 'paie : aucune modification possible (' || n || ')';
  end if;

  if v_other is not null then
    perform set_config('request.jwt.claim.sub', v_other::text, true);
    select count(*) into n from public.document_templates;
    assert n = 0, 'sans rôle : rien de visible (' || n || ')';
  end if;
  execute 'reset role';
  raise notice 'OK document_templates';
end $$;
rollback;
