#!/bin/bash
# Rejoue toutes les migrations sur une base PostgreSQL neuve (conteneur jetable) et s'arrête à la première erreur.
# Usage : bash scripts/replay-migrations.sh   (Docker requis ; sert aussi à la CI)
set -euo pipefail
export MSYS_NO_PATHCONV=1
NAME=soma-pg-replay
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -e POSTGRES_PASSWORD=ci -e POSTGRES_USER=soma -e POSTGRES_DB=soma_rh postgres:17-alpine >/dev/null
trap 'docker rm -f "$NAME" >/dev/null 2>&1' EXIT
for _ in $(seq 1 40); do docker exec "$NAME" pg_isready -U soma -d soma_rh >/dev/null 2>&1 && break; sleep 2; done
sleep 4   # l'image redémarre une fois après son initialisation
docker cp postgres/auth-compat.sql "$NAME":/a.sql
docker cp db/migrations "$NAME":/m
docker exec "$NAME" psql -q -U soma -d soma_rh -v ON_ERROR_STOP=1 -f /a.sql >/dev/null
docker exec "$NAME" sh -c '
for f in /m/*.sql; do
  out=$(psql -q -U soma -d soma_rh -v ON_ERROR_STOP=1 -f "$f" 2>&1 >/dev/null | grep -m1 ERROR) || true
  if [ -n "$out" ]; then echo "ECHEC $(basename "$f") : $out"; exit 1; fi
done
echo "Rejeu complet : toutes les migrations passent."'
