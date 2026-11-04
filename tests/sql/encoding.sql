-- D-009 : aucune fonction du schéma public ne contient de littéral accentué corrompu (« Valid??e »).
-- Cause d'origine : migrations appliquées avec un mauvais encodage. Appliquer avec `docker exec -i ... psql < fichier`.
do $$
declare corrompues text;
begin
  select string_agg(proname, ', ' order by proname) into corrompues
  from pg_proc where pronamespace = 'public'::regnamespace and prosrc ~ '[A-Za-z]\?\?[a-z]';
  if corrompues is not null then raise exception 'FAIL : littéraux corrompus dans : %', corrompues; end if;
  if not exists (select 1 from pg_proc where proname = 'payroll_entry_period_guard' and prosrc like '%Validée%') then
    raise exception 'FAIL : la garde de période ne reconnaît pas « Validée »'; end if;
  raise notice 'OK encoding';
end $$;
