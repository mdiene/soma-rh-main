# Instantané de référence (baseline)

Les migrations de `db/migrations/` ne se rejouent plus sur une base vierge (ordre incohérent hérité : voir H48 dans
`docs/TACHES_ET_RECOMMANDATIONS_RECETTE.md`). Une base neuve se construit donc ainsi :

1. `postgres/auth-compat.sql` (schéma `auth`, rôles) ;
2. `db/baseline/schema_local.sql` : schéma `public` de la base locale (`pg_dump --schema-only --no-owner -n public`, droits compris) ;
3. `db/baseline/reference_data.sql` : données de paramétrage (22 tables, aucune donnée de salarié) ;
4. les migrations **postérieures à la coupure**, dans l'ordre.

- **Coupure actuelle** : `20261119090000_c26_jo4091_plancher_legal` (variable `CUTOFF` de `scripts/replay-migrations.sh`).
- **Régénérer** : `bash scripts/export-baseline.sh` (base locale en marche), puis avancer `CUTOFF` à la dernière migration appliquée sur cette base.
- **Reconstruire** : `bash scripts/replay-migrations.sh` (Docker requis ; `--full` rejoue tout `db/migrations` et échoue encore ; `--keep` garde le conteneur `soma-pg-replay`).
- **Vérifié le 2026-11-06** : schéma rejoué et schéma local identiques (`pg_dump --schema-only` comparés, 0 ligne de différence) ; 22 tables de paramétrage identiques (empreinte md5 par table).
- Le dump est fidèle à la base locale, y compris ses défauts éventuels : toute correction passe par une migration postérieure à la coupure.
- Tables exportées : `app_parameters, collective_agreements, contract_types, document_requirements, employee_grades, exit_reasons, garnishment_scale, ir_family_reductions, leave_types, legal_sources, notice_scales, overtime_rates, payment_modes, payroll_settings, salary_components, salary_structures, salary_structure_components, severance_scales, shift_types, tax_slab_brackets, tax_slabs, trimf_brackets`.
- Non exportées : `employees`, bulletins, paies, `user_roles`, `auth.*`, journaux d'audit, notifications, documents, présences, prêts.
