-- Rend à PUBLIC le droit d'exécuter les fonctions de l'extension btree_gist uniquement (les autres fonctions restent protégées).
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_depend d on d.objid = p.oid and d.deptype = 'e'
           join pg_extension e on e.oid = d.refobjid and e.extname = 'btree_gist'
  loop execute format('grant execute on function %s to public', r.sig); end loop;
end $$;
