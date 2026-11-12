-- Retour arrière : rétablit 'infinity' (à éviter avec Supabase Auth).
CREATE OR REPLACE FUNCTION public.phone_access_disable(p_employee_id uuid, p_status text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.phone_access_accounts;
begin
  update public.phone_access_requests set status = 'revoked'
   where employee_id = p_employee_id and status in ('pending', 'authorized');
  select * into a from public.phone_access_accounts where employee_id = p_employee_id;
  if not found then return; end if;
  update public.phone_access_accounts set status = p_status, updated_at = now() where employee_id = p_employee_id;
  -- Date lointaine FINIE et non 'infinity' : le service d'authentification de Supabase ne sait pas lire 'infinity' (Scan error banned_until)
  -- et toute connexion du compte, ou sa réactivation, échouait en erreur 500.
  -- Coupure immédiate de l'accès aux données : plus de rôle ni de fiche reliée
  delete from public.user_roles where user_id = a.user_id;
  update public.employees set user_id = null where id = p_employee_id and user_id = a.user_id;
  if to_regclass('public.refresh_tokens') is not null then
    execute 'update public.refresh_tokens set is_revoked = true where user_id = $1' using a.user_id;
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'auth' and table_name = 'users' and column_name = 'banned_until') then
    execute 'update auth.users set banned_until = ''infinity'' where id = $1' using a.user_id;
  end if;
  perform public.phone_access_audit(p_reason, p_employee_id, '{}');
end;
$function$;
revoke all on function public.phone_access_disable(uuid, text, text) from public, anon, authenticated;
grant execute on function public.phone_access_disable(uuid, text, text) to service_role;
