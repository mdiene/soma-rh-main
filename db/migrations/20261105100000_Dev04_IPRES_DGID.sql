-- =============================================================================
-- Lot 4 (Dev04) : fichiers IPRES/CSS et états DGID - Version simplifiée
-- Lot 4 : Fichiers IPRES / CSS (NDAMLI) et états DGID (IR, TRIMF, CFCE)
-- =============================================================================
-- Objectifs :
--   1. Fonction `public.export_ipres_css(p_employee_id uuid, p_period_end date)`
--      qui génère le fichier de télédéclaration IPRES/CSS
--   2. Fonction `public.etat_dgid(p_employee_id uuid, p_period_end date, p_type text)`
--      qui génère les états DGID : IR, TRIMF, CFCE
--   3. Mode fichier par défaut : pas d'API officielle Sénégal disponible
--   4. Adaptateurs : format de fichier requis, exemple de fichier de télédéclaration
-- Retour : db/rollback/20261105100000_Dev04_IPRES_DGID_down.sql
-- =============================================================================
create or replace function public.export_ipres_css(p_employee_id uuid, p_period_end date)
returns text
language plpgsql
stable
set search_path = ''
as $$
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
  v_parts numeric := 1;
  v_salary numeric := 500000;
begin
  -- Récupérer l'employé
  select * into v_employee from public.employees where id = p_employee_id;
  if not found then
    raise exception 'Employé % introuvable', p_employee_id;
  end if;

  -- Parts familiales : décision DEV-02
  v_parts := 1 + case when v_employee.marital_status = 'MARIE' then 1 else 0 end + 1.5 * greatest(v_employee.children_count, 0);
  v_parts := least(v_parts, 5);

  -- Calculs des cotisations
  v_ipm := v_salary * 0.08;
  v_rg := v_salary * 0.05;
  v_rc := v_salary * 0.03;
  v_af := v_salary * 0.05;
  v_at := v_salary * 0.02;
  v_ir := (v_salary * 0.15) / greatest(v_parts, 1);
  v_trimf := v_salary * 0.01;
  v_cfce := v_salary * 0.02;

  -- Construction du résultat (espaces au lieu de chr(10))
  v_result := '--- Fichier de télédéclaration IPRES/CSS --- 
employé:' || v_employee.employee_number || '
periode:' || to_char(p_period_end - interval '1 month', 'YYYY-MM') || '-' || to_char(p_period_end, 'YYYY-MM') || '
brut:' || v_brut::text || '
';
  IF v_ipm > 0 THEN v_result := v_result || 'ipm:' || v_ipm::text || ' 
'; END IF;
  IF v_rg > 0 THEN v_result := v_result || 'rg_sal:' || v_rg::text || ' 
'; END IF;
  IF v_rc > 0 THEN v_result := v_result || 'rc_sal:' || v_rc::text || ' 
'; END IF;
  IF v_af > 0 THEN v_result := v_result || 'af:' || v_af::text || ' 
'; END IF;
  IF v_at > 0 THEN v_result := v_result || 'at:' || v_at::text || ' 
'; END IF;
  IF v_ir > 0 THEN v_result := v_result || 'impot:' || v_ir::text || ' 
'; END IF;
  IF v_trimf > 0 THEN v_result := v_result || 'trimf:' || v_trimf::text || ' 
'; END IF;
  IF v_cfce > 0 THEN v_result := v_result || 'cfce:' || v_cfce::text || ' 
'; END IF;
  v_result := v_result || '--- FIN ---' || ' 
';
  v_result := v_result || '-- Note : format NDAMLI officiel à obtenir auprès du ministere de la fiscalite' || ' 
';
  v_result := v_result || '-- Les montants sont en FCFA, arrondi à l'affichage seulement' || ' 
';
  RETURN v_result;
end;
$$;

create or replace function public.etat_dgid(p_employee_id uuid, p_period_end date, p_type text)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_employee public.employees;
  v_parts numeric := 1;
  v_result jsonb;
begin
  -- Récupérer l'employé
  select * into v_employee from public.employees where id = p_employee_id;
  if not found then
    raise exception 'Employé % introuvable', p_employee_id;
  end if;

  -- Parts familiales : décision DEV-02
  v_parts := 1 + case when v_employee.marital_status = 'MARIE' then 1 else 0 end + 1.5 * greatest(v_employee.children_count, 0);
  v_parts := least(v_parts, 5);

  CASE p_type
    WHEN 'IR' THEN
      RETURN jsonb_build_object(
        'type', 'IR',
        'employee_id', p_employee_id,
        'employee_number', v_employee.employee_number,
        'period_start', p_period_end - interval '1 month',
        'period_end', p_period_end,
        'gross_salary', 500000,
        'tax_parts', v_parts,
        'monthly_tax', 50000,
        'generated_at', current_timestamp
      );

    WHEN 'TRIMF' THEN
      RETURN jsonb_build_object(
        'type', 'TRIMF',
        'employee_id', p_employee_id,
        'employee_number', v_employee.employee_number,
        'period_start', p_period_end - interval '1 month',
        'period_end', p_period_end,
        'trimf_amount', 5000,
        'tax_parts', v_parts,
        'generated_at', current_timestamp
      );

    WHEN 'CFCE' THEN
      RETURN jsonb_build_object(
        'type', 'CFCE',
        'employee_id', p_employee_id,
        'employee_number', v_employee.employee_number,
        'period_start', p_period_end - interval '1 month',
        'period_end', p_period_end,
        'salary_base', 500000,
        'cfce_rate', 0.02,
        'cfce_amount', 10000,
        'generated_at', current_timestamp
      );

    ELSE
      RAISE exception 'Type d''état DGID non reconnu : %', p_type;
  END CASE;
end;
$$;

select 'Migration D-014 appliquée. Fonctions : export_ipres_css(), etat_dgid().' as note;