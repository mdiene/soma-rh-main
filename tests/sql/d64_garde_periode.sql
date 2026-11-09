-- D-64 : la garde de période accepte un mois précédent Payée ou Clôturée. Vérification de la définition de la fonction.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/d64_garde_periode.sql  (attendu : "OK d64_garde_periode")
do $$
declare v_src text := pg_get_functiondef('public.payroll_entry_period_guard()'::regprocedure);
begin
  if v_src not like '%''Payée''%' or v_src not like '%''Clôturée''%' then
    raise exception 'La garde de période n''accepte pas encore un mois précédent payé ou clôturé';
  end if;
  raise notice 'OK d64_garde_periode';
end $$;
