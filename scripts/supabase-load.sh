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
  # Le planning des gardiens (shift_assignments, work_posts, shift_types) est retiré du produit : non migré.
  TABLES="companies departments designations contract_types employees employee_requests leave_allocations leave_applications attendance payroll_inputs additional_salaries salary_structure_assignments user_roles audit_log payroll_entries salary_slips salary_slip_details salary_payments"
  for t in $TABLES; do
    f=/bk/csv/$t.csv
    if [ ! -s "$f" ] || [ "$(wc -l < "$f")" -le 1 ]; then echo "  $t : vide, ignorée"; continue; fi
    cols=$(head -1 "$f")
    echo "  $t ..."
    psql -v ON_ERROR_STOP=1 -q <<SQL
set session_replication_role = replica;
create temp table s (like public.$t including defaults);
\copy s($cols) from '$f' csv header
insert into public.$t($cols) overriding system value select $cols from s on conflict do nothing;
do \$do\$ declare sq text; begin if exists (select 1 from information_schema.columns where table_schema='public' and table_name='$t' and column_name='id') then sq := pg_get_serial_sequence('public.$t','id'); end if; if sq is not null then execute format('select setval(%L, greatest((select coalesce(max(id),1) from public.$t),1))', sq); end if; end \$do\$;
SQL
  done
  # Journal d'audit : les identifiants 1 à 42 sont pris par les écritures d'audit du rechargement du schéma.
  # Les lignes de l'ancienne base qui sont entrées en collision sont reprises avec de nouveaux identifiants (idempotent).
  if [ -s /bk/csv/audit_log.csv ]; then
    cols=$(head -1 /bk/csv/audit_log.csv); cols_noid=$(echo "$cols" | tr ',' '\n' | grep -v '^id$' | paste -sd,)
    echo "  audit_log : reprise des lignes en collision d'identifiant ..."
    psql -v ON_ERROR_STOP=1 -q <<SQL
set session_replication_role = replica;
create temp table s (like public.audit_log including defaults);
\copy s($cols) from '/bk/csv/audit_log.csv' csv header
insert into public.audit_log($cols_noid) select $cols_noid from s
 where not exists (select 1 from public.audit_log a where a.occurred_at = s.occurred_at and a.table_name = s.table_name
                   and a.action = s.action and a.record_id is not distinct from s.record_id);
SQL
  fi
  $P -c "notify pgrst, 'reload schema'"
  echo "--- Contrôle des comptages (attendu = sauvegarde) ---"
  for t in $TABLES; do
    exp=$(grep "^public.$t," /bk/row-counts.csv | cut -d, -f2)
    got=$(psql -At -c "select count(*) from public.$t")
    if [ "$t" = audit_log ]; then [ "$got" -ge "$exp" ] && s=OK || s=ECART; else [ "$exp" = "$got" ] && s=OK || s=ECART; fi
    echo "$s  $t  attendu=$exp  charge=$got"
  done
  ;;
*) echo "usage: reset|donnees" >&2; exit 2 ;;
esac
