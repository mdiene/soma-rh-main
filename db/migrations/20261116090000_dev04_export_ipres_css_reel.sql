-- =============================================================================
-- H3 : fixe dans le dépôt la version réellement en base de export_ipres_css
-- (lit le bulletin calculé ; la version de 20261105100000_Dev04_IPRES_DGID.sql utilisait un salaire fictif de 500 000 F
--  et son origine n'était dans aucun fichier). Sans effet sur la base actuelle : même définition.
-- Retour : db/rollback/20261116090000_dev04_export_ipres_css_reel_down.sql (version initiale de Dev04)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.export_ipres_css(p_employee_id uuid, p_period_end date)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_employee public.employees;
  v_brut numeric;
  v_ir numeric;
  v_trimf numeric;
  v_cfce numeric;
  v_ipm numeric;
  v_rg numeric;
  v_rc numeric;
  v_af numeric;
  v_at numeric;
  v_result text;
  v_slip jsonb;
begin
  -- Récupérer l'employé
  select * into v_employee from public.employees where id = p_employee_id;
  if not found then
    raise exception 'Employé % introuvable', p_employee_id;
  end if;

  -- Extraire tous les montants d'un seul appel à compute_salary_slip
  v_slip := public.compute_salary_slip(p_employee_id, p_period_end - interval '1 month', p_period_end);
  v_brut := (v_slip->>'brut_pay')::numeric;
  v_ir := (v_slip->>'income_tax')::numeric;
  v_trimf := (v_slip->>'trimf')::numeric;
  v_cfce := (v_slip->>'cfce')::numeric;
  v_ipm := (v_slip->>'ipm_employee')::numeric;
  v_rg := (v_slip->>'ipres_rg_employee')::numeric;
  v_rc := (v_slip->>'ipres_rc_employee')::numeric;
  v_af := (v_slip->>'css_af')::numeric;
  v_at := (v_slip->>'css_at')::numeric;

  -- Construction du résultat texte (format simplifié NDAMLI)
  v_result := '--- Fichier de télédéclaration IPRES/CSS ---' || chr(10);
  v_result := v_result || 'employe:' || v_employee.employee_number || chr(10);
  v_result := v_result || 'periode:' || to_char(p_period_end - interval '1 month', 'YYYY-MM') || '-' || to_char(p_period_end, 'YYYY-MM') || chr(10);
  v_result := v_result || 'brut:' || v_brut::text || chr(10);

  -- Section IPRES
  IF v_ipm > 0 THEN
    v_result := v_result || 'ipm:' || v_ipm::text || chr(10);
  END IF;
  IF v_rg > 0 THEN
    v_result := v_result || 'rg_sal:' || v_rg::text || chr(10);
  END IF;
  IF v_rc > 0 THEN
    v_result := v_result || 'rc_sal:' || v_rc::text || chr(10);
  END IF;
  IF v_af > 0 THEN
    v_result := v_result || 'af:' || v_af::text || chr(10);
  END IF;
  IF v_at > 0 THEN
    v_result := v_result || 'at:' || v_at::text || chr(10);
  END IF;

  -- Section IR
  IF v_ir > 0 THEN
    v_result := v_result || 'impot:' || v_ir::text || chr(10);
  END IF;
  -- TRIMF
  IF v_trimf > 0 THEN
    v_result := v_result || 'trimf:' || v_trimf::text || chr(10);
  END IF;
  -- CFCE
  IF v_cfce > 0 THEN
    v_result := v_result || 'cfce:' || v_cfce::text || chr(10);
  END IF;

  v_result := v_result || '--- FIN ---' || chr(10);
  RETURN v_result;
end;
$function$

;
revoke execute on function public.export_ipres_css(uuid, date) from public, anon;
grant execute on function public.export_ipres_css(uuid, date) to authenticated, service_role;
notify pgrst, 'reload schema';
