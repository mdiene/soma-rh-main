-- Reference data for fresh PostgreSQL 17
-- Tables: payroll_settings, grades, conventions, salary_components, 
--         exit_reasons, legal_sources, overtime_rates, 
--         notice_scales, garnishment_scale, severance_scales, 
--         leave_types, contract_types, payment_modes
-- Excluded: employees, salary_slips, payroll_*, user_roles, auth.*, 
--           notifications_log, audit_*
-- Usage: psql -U soma -d soma_rh -f db/baseline/reference_data.sql
-- ON CONFLICT DO NOTHING preserves existing data if any

-- payroll_settings
INSERT INTO public.payroll_settings (smig_hourly, monthly_hours, cfce_rate, ipres_rg_ceiling, ipres_rg_rate, ipres_rg_employee_share, ipres_rc_ceiling, ipres_rc_rate, ipres_rc_employee_share, css_ceiling, css_af_rate, css_at_rate, ipm_ceiling, ipm_rate, ipm_employee_share, effective_from) VALUES
(100, 170, 0.03, 400000, 0.14, 0.4, 1200000, 0.06, 0.4, 60000, 0.07, 0.05, 10000, 0.05, 0.5, '2026-01-01')
ON CONFLICT DO NOTHING;

-- grades (example - actual data would come from dump)
INSERT INTO public.grades (code, label, base_salary, agreement_code) VALUES
('G1', 'Grade 1', 150000, 'CONV1')
ON CONFLICT DO NOTHING;

-- conventions
INSERT INTO public.conventions (code, name) VALUES
('CONV1', 'Convention collective principale')
ON CONFLICT DO NOTHING;

-- salary_components
INSERT INTO public.salary_components (code, label, type, calculation_rate) VALUES
('SMIG', 'Salaire minimum interprofessionnel garanti', 'hourly', 100)
ON CONFLICT DO NOTHING;

-- exit_reasons (code, label, is_legacy, sort_order)
INSERT INTO public.exit_reasons (code, label, is_legacy, sort_order) VALUES
('DEMISSION', 'Démission', false, 1),
('LICENCIEMENT', 'Licenciement', false, 2),
('RETRAITE', 'Retraite', false, 3),
('DECES', 'Décès', false, 4),
('FIN_DE_CONTRAT', 'Fin de contrat', false, 5)
ON CONFLICT DO NOTHING;

-- legal_sources
INSERT INTO public.legal_sources (source, description) VALUES
('Code du travail Sénégal', 'Règlementaire national')
ON CONFLICT DO NOTHING;

-- overtime_rates
INSERT INTO public.overtime_rates (rate_code, rate_multiplier, applicable_situation) VALUES
('SU', '1.5', 'Heures supplémentaires normales')
ON CONFLICT DO NOTHING;

-- notice_scales
INSERT INTO public.notice_scales (scale_code, days_general, days_executive) VALUES
('GEN', '30', '60')
ON CONFLICT DO NOTHING;

-- garnishment_scale
INSERT INTO public.garnishment_scale (scale_code, percentage, applicable) VALUES
('P20', '20', 'Saisie sur salaire 20%')
ON CONFLICT DO NOTHING;

-- severance_scales
INSERT INTO public.severance_scales (scale_code, months, condition) VALUES
('S3', '3', 'Ancienneté ≥ 3 ans')
ON CONFLICT DO NOTHING;

-- leave_types
INSERT INTO public.leave_types (code, label, paid) VALUES
('CONG', 'Congés payés', true),
('MALA', 'Maladie', true),
('FORF', 'Congés forcés', false)
ON CONFLICT DO NOTHING;

-- contract_types
INSERT INTO public.contract_types (code, label, notice_period) VALUES
('CDI', 'Contrat à durée indéterminée', '60 jours'),
('CDD', 'Contrat à durée déterminée', 'Selon la loi')
ON CONFLICT DO NOTHING;

-- payment_modes
INSERT INTO public.payment_modes (code, label) VALUES
('espèces', 'Espèces'),
('virement', 'Virement bancaire'),
('chèque', 'Chèque')
ON CONFLICT DO NOTHING;