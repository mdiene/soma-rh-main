#!/bin/bash
# Exécuté DANS le conteneur postgres:17 (dépôt monté sur /repo, sauvegarde sur /bk). Connexion par variables PG*.
set -euo pipefail
CUTOFF=20261119090000_c26_jo4091_plancher_legal
P="psql -v ON_ERROR_STOP=1 -q"
# Sur Supabase le rôle propriétaire est « postgres » (la base locale utilisait « soma »)
runf() { sed 's/FOR ROLE soma /FOR ROLE postgres /g' "$1" > /tmp/run.sql; $P -f /tmp/run.sql; }
case "${1:-}" in
reset)
  echo "Suppression du schéma public et recréation à vide..."
  $P -c "drop schema if exists public cascade; create schema public; grant usage on schema public to postgres, anon, authenticated, service_role;"
  echo "Schéma de référence (baseline)..."
  runf /repo/db/baseline/schema_local.sql
  echo "Données de paramétrage..."
  runf /repo/db/baseline/reference_data.sql
  for f in $(ls /repo/db/migrations/*.sql | sort); do
    n=$(basename "$f" .sql)
    [[ "$n" > "$CUTOFF" ]] || continue
    echo "Migration $n"; runf "$f"
  done
  $P -c "notify pgrst, 'reload schema'"
  echo "Base vide chargée."
  ;;
donnees)
  TABLES="companies departments designations contract_types employees employee_requests leave_allocations leave_applications attendance payroll_inputs additional_salaries salary_structure_assignments shift_assignments work_posts user_roles audit_log payroll_entries salary_slips salary_slip_details salary_payments"
  for t in $TABLES; do
    f=/bk/csv/$t.csv
    if [ ! -s "$f" ] || [ "$(wc -l < "$f")" -le 1 ]; then echo "  $t : vide, ignorée"; continue; fi
    cols=$(head -1 "$f")
    echo "  $t ..."
    psql -v ON_ERROR_STOP=1 -q <<SQL
set session_replication_role = replica;
create temp table s (like public.$t including defaults);
\copy s($cols) from '$f' csv header
insert into public.$t($cols) select $cols from s on conflict do nothing;
SQL
  done
  $P -c "notify pgrst, 'reload schema'"
  echo "--- Contrôle des comptages (attendu = sauvegarde) ---"
  for t in $TABLES; do
    exp=$(grep "^public.$t," /bk/row-counts.csv | cut -d, -f2)
    got=$(psql -At -c "select count(*) from public.$t")
    [ "$exp" = "$got" ] && s=OK || s="ECART"
    echo "$s  $t  attendu=$exp  charge=$got"
  done
  ;;
*) echo "usage: reset|donnees" >&2; exit 2 ;;
esac
