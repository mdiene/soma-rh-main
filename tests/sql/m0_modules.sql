-- M0 modules métiers : RLS par rôle, chargeur de manifeste, activation tracée, audit. Tout est annulé.
-- Attendu : "OK m0_modules"
begin;
create temp table t_ctx as
select (select user_id from public.user_roles where role = 'rh' and user_id not in (select user_id from public.user_roles where role = 'admin') order by user_id limit 1) as u_rh,
       (select user_id from public.user_roles where role = 'paie' and user_id not in (select user_id from public.user_roles where role in ('rh','admin')) order by user_id limit 1) as u_paie,
       (select e.user_id from public.employees e where e.user_id is not null
          and not exists (select 1 from public.user_roles r where r.user_id = e.user_id and r.role in ('rh','paie','admin')) order by e.id limit 1) as u_sal,
       (select e.user_id from public.employees e where e.user_id is not null
          and not exists (select 1 from public.user_roles r where r.user_id = e.user_id and r.role in ('rh','paie','admin')) order by e.id offset 1 limit 1) as u_sal2;
grant select on t_ctx to authenticated, anon;
create or replace function pg_temp.as_user(p_user uuid) returns void language plpgsql as $$
begin execute 'reset role'; execute 'set local role authenticated'; perform set_config('request.jwt.claim.sub', p_user::text, true); end $$;
create or replace function pg_temp.n(p_sql text) returns bigint language plpgsql as $$
declare r bigint; begin execute p_sql into r; return r; end $$;
create or replace function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'OK'; exception when others then return sqlerrm; end $$;
do $$
declare c record; v_emp uuid; v_emp2 uuid; r text; j jsonb; m jsonb;
begin
  select * into c from t_ctx;
  if c.u_rh is null or c.u_paie is null or c.u_sal is null or c.u_sal2 is null then raise exception 'utilisateurs de test manquants : %', c; end if;
  select id into v_emp  from public.employees where user_id = c.u_sal;
  select id into v_emp2 from public.employees where user_id = c.u_sal2;

  -- RLS activée partout
  if exists (select 1 from pg_class where oid in ('public.module_manifest'::regclass,'public.module_activation'::regclass,
       'public.module_parameter_value'::regclass,'public.employee_module_data'::regclass) and not relrowsecurity)
  then raise exception 'RLS non activée sur une table de module'; end if;

  -- RH : charge un manifeste de test (valeur ✔, ◐, ✖ sans valeur, ✖ avec valeur provisoire)
  perform pg_temp.as_user(c.u_rh);
  m := '{"module_id":"test-mod","module_name":"Module de test","version":"0.0.1","status":"draft","parameters":{
          "p_verifie":{"value":40,"legal_status":"verified","source":"S1"},
          "p_secondaire":{"value":0.15,"legal_status":"secondary","source":"S2"},
          "p_vide":{"value":null,"legal_status":"to_provide"},
          "p_provisoire":{"value":0.07,"legal_status":"to_provide","source":"S3"}}}'::jsonb;
  j := public.load_module_manifest(m, 'h1');
  if (j->>'seeded')::int <> 2 then raise exception 'chargeur : 2 paramètres attendus (✔ ◐), obtenu %', j; end if;
  if pg_temp.n('select count(*) from public.module_parameter_value where module_id=''test-mod'' and param_key in (''p_vide'',''p_provisoire'')') <> 0
    then raise exception 'chargeur : un paramètre ✖ a été pré-rempli'; end if;
  j := public.load_module_manifest(m, 'h1');
  if (j->>'changed')::boolean or (j->>'seeded')::int <> 0 then raise exception 'chargeur non idempotent : %', j; end if;
  if pg_temp.n('select count(*) from public.module_parameter_value where module_id=''test-mod''') <> 2 then raise exception 'doublons de paramètres'; end if;

  -- activation : horodatage, version et hash copiés du manifeste
  insert into public.module_activation(module_id, enabled) values ('test-mod', true);
  if pg_temp.n('select count(*) from public.module_activation where module_id=''test-mod'' and enabled and enabled_at is not null and enabled_by is not null and manifest_hash=''h1'' and manifest_version=''0.0.1''') <> 1
    then raise exception 'activation non estampée'; end if;
  update public.module_activation set enabled = false where module_id = 'test-mod';
  if pg_temp.n('select count(*) from public.module_activation where module_id=''test-mod'' and not enabled and disabled_at is not null') <> 1
    then raise exception 'désactivation non estampée'; end if;

  -- versions de paramètre : chevauchement refusé
  insert into public.module_parameter_value(module_id, param_key, value, legal_status, source, valid_from, valid_to)
    values ('test-mod','p_saisi','1','secondary','S','2026-01-01','2026-07-01');
  r := pg_temp.try('insert into public.module_parameter_value(module_id,param_key,value,legal_status,valid_from) values (''test-mod'',''p_saisi'',''2'',''secondary'',''2026-06-01'')');
  if r = 'OK' then raise exception 'chevauchement de versions accepté'; end if;
  insert into public.module_parameter_value(module_id, param_key, value, legal_status, valid_from)
    values ('test-mod','p_saisi','2','secondary','2026-07-01');

  -- données salarié
  insert into public.employee_module_data(employee_id, module_id, data) values (v_emp, 'test-mod', '{"k":1}'), (v_emp2, 'test-mod', '{"k":2}');

  -- paie : lit tout, n'écrit rien
  perform pg_temp.as_user(c.u_paie);
  if pg_temp.n('select count(*) from public.module_manifest') < 1 then raise exception 'paie ne lit pas les manifestes'; end if;
  if pg_temp.n('select count(*) from public.module_parameter_value where module_id=''test-mod''') < 3 then raise exception 'paie ne lit pas les paramètres'; end if;
  if pg_temp.n('select count(*) from public.employee_module_data') < 2 then raise exception 'paie ne lit pas les données salarié'; end if;
  perform pg_temp.try('update public.module_activation set enabled = true');
  if pg_temp.n('select count(*) from public.module_activation where enabled') <> 0 then raise exception 'paie a modifié une activation'; end if;
  r := pg_temp.try('insert into public.module_parameter_value(module_id,param_key,value,legal_status) values (''test-mod'',''x'',''1'',''secondary'')');
  if r = 'OK' then raise exception 'paie a écrit un paramètre'; end if;
  r := pg_temp.try('select public.load_module_manifest(''{"module_id":"x","version":"1"}''::jsonb, ''h'')');
  if r = 'OK' then raise exception 'paie a pu charger un manifeste'; end if;

  -- salarié : uniquement ses propres données de module, rien d'autre
  perform pg_temp.as_user(c.u_sal);
  if pg_temp.n('select count(*) from public.employee_module_data') <> 1 then raise exception 'salarié : lignes visibles <> 1'; end if;
  if pg_temp.n('select count(*) from public.module_manifest') <> 0 then raise exception 'salarié voit les manifestes'; end if;
  if pg_temp.n('select count(*) from public.module_activation') <> 0 then raise exception 'salarié voit les activations'; end if;
  if pg_temp.n('select count(*) from public.module_parameter_value') <> 0 then raise exception 'salarié voit les paramètres'; end if;
  r := pg_temp.try('insert into public.employee_module_data(employee_id,module_id,data) values ((select id from public.employees where user_id=(select auth.uid())),''test-mod'',''{}'')');
  if r = 'OK' then raise exception 'salarié a pu écrire ses données de module'; end if;

  -- anonyme : rien (lecture refusée ou vide, chargeur refusé)
  execute 'reset role'; execute 'set local role anon';
  r := pg_temp.try('select count(*) from public.module_manifest');
  if r = 'OK' and pg_temp.n('select count(*) from public.module_manifest') <> 0 then raise exception 'anonyme voit des manifestes'; end if;
  if pg_temp.try('select public.load_module_manifest(''{}''::jsonb, ''h'')') = 'OK' then raise exception 'anonyme a pu charger un manifeste'; end if;

  -- audit : activation et désactivation journalisées
  execute 'reset role';
  if (select count(*) from public.audit_log where table_name = 'module_activation') < 2 then raise exception 'activation non journalisée'; end if;
  raise notice 'OK m0_modules';
end $$;
rollback;
