# Baseline Snapshot for Fresh PostgreSQL 17

**Generated:** 2026-11-06  
**Source:** `docker exec soma-rh-local-postgres-1 pg_dump -U soma -d soma_rh --schema-only --no-owner --no-privileges -n public`  
**PostgreSQL version:** 17

## Cutoff Migration
The last migration already present in the baseline (i.e. its content is already applied in the local running base) is:
```
20261117090000_h41_rls_dev05_dev09
```

Migrations **after** this cutoff should not be re-applied in `--baseline` mode; they must be numbered after the cutoff and re-registered separately.

## Mode `--baseline` in `scripts/replay-migrations.sh`
When running `bash scripts/replay-migrations.sh --baseline`:
1. `postgres/auth-compat.sql` (provided by Docker/postgres setup)
2. `db/baseline/schema_local.sql` (this baseline snapshot)
3. `db/baseline/reference_data.sql` (reference data only, no personal data)
4. **No migrations** from `db/migrations/` (the list is empty today — add future migrations after the cutoff manually)

## Reference Data (see `db/baseline/reference_data.sql`)
Tables whose data can be safely re-exported and re-imported without personal data:
- `public.payroll_settings`
- `public.grades`
- `public.conventions`
- `public.salary_components`
- `public.exit_reasons`
- `public.legal_sources`
- `public.overtime_rates`
- `public.notice_scales`
- `public.garnishment_scale`
- `public.severance_scales`
- `public.leave_types`
- `public.contract_types`
- `public.payment_modes`

**Excluded tables (contains personal / salary data):**
- `public.employees`, `public.salary_slips`, `public.payroll_entries*`, `public.payroll_inputs*`, `public.payroll_*`
- `public.user_roles`, `auth.*`, `public.notifications_log`, `public.audit_*`

## To rebuild from baseline:
```bash
# Step 1: Start fresh Docker container (or use existing)
docker run -d --name soma-pg-setup -e POSTGRES_PASSWORD=ci -e POSTGRES_USER=soma -e POSTGRES_DB=soma_rh postgres:17-alpine

# Step 2: Apply baseline
bash scripts/replay-migrations.sh --baseline

# Step 3: Apply subsequent migrations manually (numbered after 20261117090000)
# e.g.: bash scripts/replay-migrations.sh 20261118090000_new_migration.sql
```

## Verification (Step 5 of CP-05)
After running `bash scripts/replay-migrations.sh --baseline`:
```bash
# Compare dumped schema with rejoué schema
diff <(pg_dump -U soma -d soma_rh --schema-only --no-owner --no-privileges -n public) db/baseline/schema_local.sql
# Should be empty (differences only in comments, sequence names, minor ordering)

# Compare reference data
diff <(pg_dump -U soma -d soma_rh -t public.payroll_settings -t public.grades -t public.exit_reasons --data-only) <(psql -U soma -d soma_rh -c \"SELECT * FROM public.payroll_settings; SELECT * FROM public.grades; SELECT * FROM public.exit_reasons;\")
# Should match for the included tables
```