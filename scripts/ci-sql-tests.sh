#!/bin/bash
# Joue tests/sql/*.sql dans le conteneur soma-pg-replay (créé par : bash scripts/replay-migrations.sh --keep).
#   bash scripts/ci-sql-tests.sh            tous les tests, sauf ceux de tests/sql/ci-scenario.txt
#   bash scripts/ci-sql-tests.sh rpc_droits un seul test (sans .sql)
# Chaque fichier s'annule ou ne fait que lire. Exit 1 si au moins un échec.
# ponytail: un test qui exige des données de scénario (QA-01) se déclare dans ci-scenario.txt ; le chargement d'un scénario fictif reste à faire (soma-base).
set -uo pipefail
export MSYS_NO_PATHCONV=1
NAME=soma-pg-replay
SKIP=tests/sql/ci-scenario.txt
fail=0; n=0
if [ -n "${1:-}" ]; then files=("tests/sql/$1.sql"); else files=(tests/sql/*.sql); fi
for f in "${files[@]}"; do
  b=$(basename "$f" .sql)
  if [ -z "${1:-}" ] && [ -f "$SKIP" ] && grep -qx "$b" <(grep -v '^#' "$SKIP"); then echo "IGNORÉ $b (scénario)"; continue; fi
  n=$((n+1))
  if out=$(docker exec -i "$NAME" psql -U soma -d soma_rh -v ON_ERROR_STOP=1 < "$f" 2>&1); then echo "OK     $b"
  else fail=$((fail+1)); echo "ECHEC  $b"; echo "$out" | grep -E 'ERROR|DETAIL|HINT|FAIL' | head -4 | sed 's/^/         /'; fi
done
echo "$n test(s), $fail échec(s)"
[ "$fail" -eq 0 ]
