#!/bin/bash
# Régénère db/baseline/ depuis la base locale en marche (schéma public + données de paramétrage, sans donnée de salarié).
# À relancer quand on veut avancer la coupure, puis mettre à jour CUTOFF dans scripts/replay-migrations.sh et README.
set -euo pipefail
export MSYS_NO_PATHCONV=1
C=${C:-soma-rh-local-postgres-1}
OUT=db/baseline
REF="app_parameters collective_agreements contract_types document_requirements employee_grades exit_reasons garnishment_scale ir_family_reductions leave_types legal_sources notice_scales overtime_rates payment_modes payroll_settings salary_components salary_structures salary_structure_components severance_scales shift_types tax_slab_brackets tax_slabs trimf_brackets"
T=""; for t in $REF; do T="$T -t public.$t"; done
mkdir -p "$OUT"
{ cat <<'H'
-- Instantané du schéma public de la base locale (pg_dump --schema-only --no-owner -n public), voir db/baseline/README.md.
-- pg_dump -n public n'inclut pas les extensions : créées ici.
create extension if not exists btree_gist with schema public;
create extension if not exists pgcrypto with schema public;

H
  docker exec "$C" pg_dump -U soma -d soma_rh --schema-only --no-owner -n public \
    | grep -v -x -e 'CREATE SCHEMA public;' -e "COMMENT ON SCHEMA public IS 'standard public schema';"
} > "$OUT/schema_local.sql"
{ cat <<'H'
-- Données de paramétrage exportées de la base locale (pg_dump --data-only --column-inserts --on-conflict-do-nothing).
-- Aucune donnée de salarié. Déclencheurs suspendus pendant le chargement (journal d'audit, horodatages).
set session_replication_role = replica;

H
  # shellcheck disable=SC2086
  docker exec "$C" pg_dump -U soma -d soma_rh --data-only --column-inserts --on-conflict-do-nothing --no-owner $T
} > "$OUT/reference_data.sql"
echo "Instantané écrit dans $OUT/ ($(wc -l < "$OUT/schema_local.sql") lignes de schéma)."
