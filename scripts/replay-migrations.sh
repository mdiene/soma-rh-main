#!/bin/bash
# Reconstruit une base PostgreSQL 17 neuve dans un conteneur jetable.
#   bash scripts/replay-migrations.sh            # défaut : auth-compat + instantané db/baseline + migrations postérieures à la coupure
#   bash scripts/replay-migrations.sh --full     # rejeu de tout db/migrations (ne passe plus : voir H48)
#   bash scripts/replay-migrations.sh --keep     # conserve le conteneur soma-pg-replay (pour comparer le schéma)
# Aucune erreur n'est masquée : la première erreur arrête le script (code 1).
set -euo pipefail
export MSYS_NO_PATHCONV=1
MODE=baseline; KEEP=false
for a in "$@"; do
  case "$a" in --full) MODE=full ;; --keep) KEEP=true ;; *) echo "Option inconnue : $a" >&2; exit 2 ;; esac
done
CUTOFF=20261119090000_c26_jo4091_plancher_legal   # dernière migration comprise dans db/baseline/schema_local.sql
NAME=soma-pg-replay

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -e POSTGRES_PASSWORD=ci -e POSTGRES_USER=soma -e POSTGRES_DB=soma_rh postgres:17-alpine >/dev/null
[ "$KEEP" = true ] || trap 'docker rm -f "$NAME" >/dev/null 2>&1' EXIT
for _ in $(seq 1 40); do docker exec "$NAME" pg_isready -U soma -d soma_rh >/dev/null 2>&1 && break; sleep 2; done
sleep 4   # l'image redémarre une fois après son initialisation

run() {   # run <fichier local> : copie puis exécute avec arrêt à la première erreur
  docker cp "$1" "$NAME":/f.sql >/dev/null
  docker exec "$NAME" psql -q -U soma -d soma_rh -v ON_ERROR_STOP=1 -f /f.sql >/dev/null || { echo "ECHEC : $1" >&2; exit 1; }
}

run postgres/auth-compat.sql
if [ "$MODE" = baseline ]; then
  run db/baseline/schema_local.sql
  run db/baseline/reference_data.sql
  for f in db/migrations/*.sql; do
    n=$(basename "$f" .sql)
    [[ "$n" > "$CUTOFF" ]] || continue
    echo "Migration postérieure à la coupure : $n"; run "$f"
  done
else
  for f in db/migrations/*.sql; do run "$f"; done
fi
if [ "$MODE" = full ]; then
  # mêmes droits par défaut que docker/postgres-init/001-run-migrations.sh (en mode baseline, l'instantané porte déjà les droits exacts)
  docker exec "$NAME" psql -q -U soma -d soma_rh -v ON_ERROR_STOP=1 -c "grant select, insert, update, delete on all tables in schema public to authenticated; grant usage, select on all sequences in schema public to authenticated; grant execute on all functions in schema public to authenticated;" >/dev/null
fi
echo "Reconstruction terminée (mode $MODE)."
