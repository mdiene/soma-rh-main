#!/bin/bash
# Rejoue toutes les migrations sur une base PostgreSQL neuve (conteneur jetable).
# Usage :
#   bash scripts/replay-migrations.sh                # mode complet : rejoue toutes les migrations de db/migrations/
#   bash scripts/replay-migrations.sh --baseline     # mode baseline : schema + reference data uniquement
set -euo pipefail
export MSYS_NO_PATHCONV=1

# Helper: report error and exit
error_exit() { echo "ERROR: $1" >&2; exit 1; }

# Parse arguments
BASELINE_MODE=false
if [ "$1" = "--baseline" ]; then
  BASELINE_MODE=true
fi

NAME=soma-pg-replay
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -e POSTGRES_PASSWORD=ci -e POSTGRES_USER=soma -e POSTGRES_DB=soma_rh postgres:17-alpine >/dev/null
trap 'docker rm -f "$NAME" >/dev/null 2>&1' EXIT

# Wait for PostgreSQL to be ready
for _ in $(seq 1 40); do
  docker exec "$NAME" pg_isready -U soma -d soma_rh >/dev/null 2>&1 && break
  sleep 2
done
sleep 4   # l'image redémarre une fois après son initialisation

if [ "$BASELINE_MODE" = true ]; then
  # --- MODE BASELINE ---
  # 1. Apply auth-compat.sql (provided by postgres setup)
  docker cp postgres/auth-compat.sql "$NAME":/a.sql >/dev/null 2>&1 || true
  docker exec "$NAME" psql -q -U soma -d soma_rh -v ON_ERROR_STOP=1 -f /a.sql >/dev/null 2>&1 || error_exit "Échec application auth-compat.sql"

  # 2. Apply baseline schema dump
  docker cp db/baseline/schema_local.sql "$NAME":/schema.sql >/dev/null 2>&1 || error_exit "Impossible de copier schema_local.sql"
  docker exec "$NAME" psql -q -U soma -d soma_rh -v ON_ERROR_STOP=1 -f /schema.sql >/dev/null 2>&1 || error_exit "Échec application schema_local.sql"

  # 3. Apply reference data only (no personal data)
  docker cp db/baseline/reference_data.sql "$NAME":/ref_data.sql >/dev/null 2>&1 || true
  docker exec "$NAME" psql -U soma -d soma_rh -f /ref_data.sql >/dev/null 2>&1 || true

  echo "Mode baseline terminé : schéma de référence appliqué."
  echo "Les migrations postérieures à la coupure (après 20261117090000_h41_rls_dev05_dev09) doivent être appliquées manuellement."
else
  # --- MODE COMPLET (par défaut) ---
  # 1. Apply auth-compat.sql (provided by postgres setup)
  docker cp postgres/auth-compat.sql "$NAME":/a.sql >/dev/null 2>&1 || true
  docker exec "$NAME" psql -q -U soma -d soma_rh -v ON_ERROR_STOP=1 -f /a.sql >/dev/null 2>&1 || error_exit "Échec application auth-compat.sql"

  # 2. Apply all migrations from db/migrations/ in alphabetical order
  docker cp db/migrations "$NAME":/m >/dev/null 2>&1 || error_exit "Impossible de copier db/migrations/"

  docker exec "$NAME" sh -c '
  for f in /m/*.sql; do
    out=$(psql -q -U soma -d soma_rh -v ON_ERROR_STOP=1 -f "$f" 2>&1 >/dev/null | grep -m1 ERROR) || true
    if [ -n "$out" ]; then echo "ECHEC $(basename "$f") : $out"; exit 1; fi
  done
  echo "Rejeu complet : toutes les migrations passent."'
fi
