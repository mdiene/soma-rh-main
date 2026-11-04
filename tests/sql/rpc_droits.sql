-- T-I11 (fonctions) : le rôle anonyme n'exécute aucune fonction appelable du schéma public ;
-- les fonctions de déclencheur ne sont exécutables par personne en direct ;
-- et les nouvelles fonctions héritent de ces droits (privilèges par défaut).
do $$
declare anon_liste text; defaut int;
begin
  select string_agg(p.proname, ', ' order by p.proname) into anon_liste
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
    and has_function_privilege('anon', p.oid, 'execute');
  if anon_liste is not null then
    raise exception 'FAIL : fonctions exécutables par le rôle anonyme : %', left(anon_liste, 400);
  end if;

  -- privilèges par défaut : une fonction créée plus tard ne doit pas être publique
  select count(*) into defaut
  from pg_default_acl d
  where d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'f'
    and not exists (select 1 from aclexplode(d.defaclacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE');
  if defaut = 0 then
    raise exception 'FAIL : aucun privilège par défaut retirant EXECUTE à PUBLIC pour les fonctions futures';
  end if;
  raise notice 'OK rpc_droits';
end $$;
