-- Dépôt de document par RPC : (1) RH dépose, (2) nouveau dépôt = version 2 en attente, (3) chemin hors dossier refusé,
-- (4) suppression RH renvoie les chemins, (5) un salarié ne supprime pas. Tout est annulé.
-- Attendu : "OK documents_supabase_storage"
begin;
do $$
declare
  v_rh uuid; v_emp uuid; v_user uuid; d public.employee_documents; v_paths text[]; v_code text; n int; v_ok boolean;
begin
  select user_id into v_rh from public.user_roles where role in ('rh', 'admin') order by user_id limit 1;
  select e.id, e.user_id into v_emp, v_user from public.employees e
   where e.user_id is not null
     and not exists (select 1 from public.user_roles x where x.user_id = e.user_id and x.role in ('rh', 'admin'))
   order by e.id limit 1;
  select code into v_code from public.document_requirements
   where active and 'application/pdf' = any(allowed_mime_types) and code not in ('situation_matrimoniale', 'actes_enfants')
   order by code limit 1;
  assert v_rh is not null and v_emp is not null and v_code is not null, 'données de test manquantes';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_rh::text, true);

  d := public.register_employee_document(v_emp, v_code, 1, v_emp || '/a.pdf', 'a.pdf', 'application/pdf', 1000, 'x');
  assert d.current_version = 1 and d.status = 'en_attente', '(1) dépôt initial';
  d := public.register_employee_document(v_emp, v_code, 1, v_emp || '/b.pdf', 'b.pdf', 'application/pdf', 1000, 'y');
  assert d.current_version = 2 and d.storage_path = v_emp || '/b.pdf', '(2) version 2';
  select count(*) into n from public.document_versions where document_id = d.id;
  assert n = 2, '(2) deux versions';

  begin
    perform public.register_employee_document(v_emp, v_code, 1, gen_random_uuid() || '/c.pdf', 'c.pdf', 'application/pdf', 10, null);
    v_ok := false;
  exception when others then v_ok := true; end;
  assert v_ok, '(3) chemin hors dossier accepté';

  perform set_config('request.jwt.claim.sub', v_user::text, true);
  begin perform public.delete_employee_document(d.id); v_ok := false; exception when others then v_ok := true; end;
  assert v_ok, '(5) un salarié a supprimé un document';

  perform set_config('request.jwt.claim.sub', v_rh::text, true);
  v_paths := public.delete_employee_document(d.id);
  assert array_length(v_paths, 1) = 2, '(4) chemins renvoyés';
  execute 'reset role';
end $$;
rollback;
\echo OK documents_supabase_storage
