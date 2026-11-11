-- Verrou de connexion persistant : 5 échecs -> verrou, palier doublé, remise à zéro par une réussite. Tout est annulé.
-- Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/verrou_connexion_base.sql  (attendu : "OK verrou_connexion_base")
begin;
do $$
declare i integer; l boolean; w integer; k text := 'test-' || gen_random_uuid()::text;
begin
  for i in 1..4 loop
    if public.login_lock_fail(k) then raise exception 'verrou trop tôt (échec %)', i; end if;
  end loop;
  if public.login_lock_retry_after(k) <> 0 then raise exception 'verrou avant 5 échecs'; end if;
  if not public.login_lock_fail(k) then raise exception '5e échec sans verrou'; end if;
  w := public.login_lock_retry_after(k);
  if w < 55 or w > 60 then raise exception 'premier verrou attendu ~60 s, obtenu %', w; end if;
  update public.login_attempts set locked_until = now() - interval '1 second' where key_hash = k; -- fin du verrou
  for i in 1..5 loop l := public.login_lock_fail(k); end loop;
  w := public.login_lock_retry_after(k);
  if w < 115 or w > 120 then raise exception 'second verrou attendu ~120 s, obtenu %', w; end if;
  perform public.login_lock_success(k);
  if public.login_lock_retry_after(k) <> 0 then raise exception 'réussite sans remise à zéro'; end if;
  if has_function_privilege('authenticated', 'public.login_lock_fail(text,integer,integer,integer)', 'execute') then raise exception 'fonction exposée à authenticated'; end if;
end $$;
select 'OK verrou_connexion_base';
rollback;
