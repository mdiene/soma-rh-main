#!/bin/bash
# Check for migration naming conflicts and non-ASCII characters
# Usage: bash scripts/check-migrations.sh
# Exits with code 1 if issues found, 0 if all OK

set -e

MIGRATIONS_DIR="db/migrations"
ALLOWLIST="scripts/migrations-allowlist.txt"

# Collect all migration file names (just the filename, not full path)
files=()
for f in "$MIGRATIONS_DIR"/*.sql; do
    [ -f "$f" ] || continue
    files+=("$(basename "$f")")
done

# Check for non-ASCII characters in filenames
for f in "${files[@]}"; do
    if printf '%s' "$f" | LC_ALL=C grep -q '[^ -~]'; then
        echo "ERROR: Non-ASCII character found in filename: $f"
        exit 1
    fi
done

# Check for duplicate 14-character prefixes
declare -A prefixes
declare -a duplicate_prefixes
for f in "${files[@]}"; do
    # Extract the 14-character prefix (YYYYMMDDHHMMSS format)
    prefix="${f:0:14}"
    # Check if prefix is valid (all digits)
    if [[ "$prefix" =~ ^[0-9]{14}$ ]]; then
        if [[ -n "${prefixes[$prefix]:-}" ]]; then
            # Check if this prefix is in the allowlist
            if grep -q "^${prefix}$" "$ALLOWLIST" 2>/dev/null; then
                continue  # This is an allowed duplicate
            fi
            duplicate_prefixes+=("$prefix")
        else
            prefixes[$prefix]=1
        fi
    fi
done

if [ ${#duplicate_prefixes[@]} -gt 0 ]; then
    echo "ERROR: Duplicate migration prefixes found (not in allowlist):"
    for p in "${duplicate_prefixes[@]}"; do
        echo "  - $p"
    done
    exit 1
fi

echo "Migration naming check passed."
exit 0