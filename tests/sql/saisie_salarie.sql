-- Saisie des salariés : mise en forme des noms, n° de CNI/passeport obligatoire (assistant) et unique, brouillons de saisie. Tout est annulé.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/saisie_salarie.sql  (attendu : "OK saisie_salarie")
begin;
create temp table t_ctx as
select
  (select user_id from public.user_roles r where role = 'rh' and not exists (select 1 from public.user_roles x where x.user_id = r.user_id and x.role in ('admin','paie')) order by user_id limit 1) as rh_a,
  (select user_id from public.user_roles r where role = 'rh' and not exists (select 1 from public.user_roles x where x.user_id = r.user_id and x.role in ('admin','paie'))
      and user_id <> (select user_id from public.user_roles r2 where role = 'rh' and not exists (select 1 from public.user_roles x where x.user_id = r2.user_id and x.role in ('admin','paie')) order by user_id limit 1) order by user_id limit 1) as rh_b,
  (select user_id from public.user_roles where role = 'admin' order by user_id limit 1) as admin,
  (select user_id from public.user_roles r where role = 'paie' and not exists (select 1 from public.user_roles x where x.user_id = r.user_id and x.role in ('admin','rh')) order by user_id limit 1) as paie,
  (select id from public.companies order by created_at limit 1) as company;
grant select on t_ctx to authenticated;
create or replace function pg_temp.as_user(p_user uuid) returns void language plpgsql as $$
begin execute 'reset role'; execute 'set local role authenticated'; perform set_config('request.jwt.claim.sub', p_user::text, true); end $$;
create or replace function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'OK'; exception when others then return sqlerrm; end $$;
do $$
declare c t_ctx; e public.employees; r text; n integer; v jsonb;
begin
  select * into c from t_ctx;
  if c.rh_a is null or c.rh_b is null or c.admin is null or c.paie is null or c.company is null then
    raise exception 'jeu de données insuffisant (deux comptes rh seuls, admin, paie seul, une société)';
  end if;

  -- 1. mise en forme des noms à la création
  insert into public.employees (company_id, employee_number, first_name, last_name, maiden_name, mother_first_name, mother_last_name, father_name, employment_type, date_of_joining, id_document_number)
  values (c.company, '', '  MAME   fatou ', 'n''DIAYE-sow', 'ba', 'AÏSSATOU', 'fall', 'MODOU diop', 'CDI', '2026-01-01', 'cni 100 200') returning * into e;
  if (e.first_name, e.last_name, e.maiden_name, e.mother_first_name, e.mother_last_name, e.father_name) is distinct from ('Mame Fatou', 'N''Diaye-Sow', 'Ba', 'Aïssatou', 'Fall', 'Modou Diop') then
    raise exception '1 : noms mal formés : %', row(e.first_name, e.last_name, e.maiden_name, e.mother_first_name, e.mother_last_name, e.father_name);
  end if;
  -- une modification d'un autre champ ne retouche pas les noms ; une modification du nom est mise en forme
  update public.employees set address = 'Dakar' where id = e.id;
  update public.employees set last_name = 'DIOP' where id = e.id returning * into e;
  if e.last_name <> 'Diop' then raise exception '1 : nom modifié non mis en forme : %', e.last_name; end if;

  -- 2. unicité du n° de pièce, espaces et casse ignorés ; les fiches sans numéro ne sont pas concernées
  r := pg_temp.try(format('insert into public.employees (company_id, employee_number, first_name, last_name, employment_type, date_of_joining, id_document_number) values (%L, '''', ''Autre'', ''Personne'', ''CDI'', ''2026-01-01'', ''CNI100200'')', c.company));
  if r not like '%employees_id_document_uidx%' then raise exception '2 : doublon de pièce accepté ou mauvaise erreur : %', r; end if;
  for n in 1..2 loop
    insert into public.employees (company_id, employee_number, first_name, last_name, employment_type, date_of_joining) values (c.company, '', 'Sans', 'Piece', 'CDI', '2026-01-01');
  end loop;

  -- 3. assistant : n° de pièce obligatoire et non déjà attribué (message lisible)
  perform pg_temp.as_user(c.rh_a);
  v := jsonb_build_object('first_name', 'Test', 'last_name', 'Assistant', 'employment_type', 'CDI', 'date_of_joining', '2026-01-01');
  r := pg_temp.try(format('select public.create_employee_from_wizard(%L::jsonb, null, null)', v));
  if r not like '%CNI ou de passeport est obligatoire%' then raise exception '3 : pièce manquante acceptée : %', r; end if;
  r := pg_temp.try(format('select public.create_employee_from_wizard(%L::jsonb, null, null)', v || jsonb_build_object('id_document_number', 'cni100200')));
  if r not like '%déjà attribué au salarié%' then raise exception '3 : doublon accepté ou message illisible : %', r; end if;
  r := pg_temp.try(format('select public.create_employee_from_wizard(%L::jsonb, null, null)', v || jsonb_build_object('id_document_number', 'TEST-NOUVELLE-PIECE')));
  if r <> 'OK' then raise exception '3 : création valide refusée : %', r; end if;

  -- 4. brouillons : chacun voit les siens ; l'administrateur voit tout ; paie seul ne crée rien
  perform pg_temp.as_user(c.rh_a);
  insert into public.employee_drafts (data) values ('{"draft": {"first_name": "Aminata"}}');
  select count(*) into n from public.employee_drafts;
  if n <> 1 then raise exception '4 : l''auteur devrait voir 1 brouillon, vu %', n; end if;
  perform pg_temp.as_user(c.rh_b);
  select count(*) into n from public.employee_drafts;
  if n <> 0 then raise exception '4 : un autre rh voit % brouillon(s)', n; end if;
  update public.employee_drafts set data = '{"x": 1}';
  get diagnostics n = row_count;
  if n <> 0 then raise exception '4 : un autre rh a modifié % brouillon(s)', n; end if;
  perform pg_temp.as_user(c.admin);
  select count(*) into n from public.employee_drafts;
  if n < 1 then raise exception '4 : l''administrateur ne voit pas les brouillons'; end if;
  perform pg_temp.as_user(c.paie);
  r := pg_temp.try('insert into public.employee_drafts (data) values (''{}'')');
  if r = 'OK' then raise exception '4 : un compte paie seul a créé un brouillon'; end if;
  -- un rh ne peut pas se faire passer pour un autre auteur
  perform pg_temp.as_user(c.rh_a);
  r := pg_temp.try(format('insert into public.employee_drafts (created_by, data) values (%L, ''{}'')', c.rh_b));
  if r = 'OK' then raise exception '4 : brouillon créé au nom d''un autre'; end if;
end $$;
select 'OK saisie_salarie';
rollback;
