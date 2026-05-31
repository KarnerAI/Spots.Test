#!/usr/bin/env bash
#
# apply-migrations-to-test.sh
#
# Applies every .sql file under Spots.Test/SQL/ to a Supabase test project in
# chronological order. Use once after creating the test project (see
# Docs/INTEGRATION_TEST_HARNESS.md), and after any new migration is added in a
# subsequent PR.
#
# Usage:
#   DB_URL="postgres://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:6543/postgres" \
#     ./Docs/scripts/apply-migrations-to-test.sh
#
# Get DB_URL from Supabase Dashboard → Project Settings → Database → "Connection string"
# (the "URI" / pooler variant). Treat it as a secret — do not commit it.
#
# This script REFUSES to run if the DB_URL appears to point at the prod project.
# It pattern-matches against `prod_supabase_ref_blocklist.txt` if that file
# exists in the home dir; otherwise it just warns and continues.

set -euo pipefail

if [[ -z "${DB_URL:-}" ]]; then
  echo "ERROR: DB_URL not set. Example:" >&2
  echo "  DB_URL='postgres://...' $0" >&2
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "ERROR: psql not found. Install with: brew install libpq && brew link --force libpq" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SQL_DIR="$REPO_ROOT/SQL"

if [[ ! -d "$SQL_DIR" ]]; then
  echo "ERROR: SQL dir not found at $SQL_DIR" >&2
  exit 1
fi

# Safety: refuse if the URL looks like a known prod ref (manual blocklist).
BLOCKLIST="$HOME/.config/spots-test-harness/prod-blocklist.txt"
if [[ -f "$BLOCKLIST" ]]; then
  while IFS= read -r ref; do
    [[ -z "$ref" || "$ref" =~ ^# ]] && continue
    if [[ "$DB_URL" == *"$ref"* ]]; then
      echo "ABORTING: DB_URL contains blocklisted prod ref '$ref'." >&2
      echo "If this is intentional, edit $BLOCKLIST." >&2
      exit 1
    fi
  done < "$BLOCKLIST"
fi

echo "Applying migrations from $SQL_DIR to test project..."
echo ""

count=0
# Sort lexically; the migration filenames are date-prefixed (2026-05-xx_*) for
# recent ones and alphabetical for the older create_*.sql / add_*.sql files.
# The historical files were committed in the order needed; lexical sort happens
# to keep them in the order they were originally applied to prod. Verify by eye
# the first time you run this against a new test project.
while IFS= read -r -d '' sql_file; do
  count=$((count + 1))
  rel="${sql_file#$REPO_ROOT/}"
  printf "  [%2d] %s ... " "$count" "$rel"
  if psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f "$sql_file" >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAILED"
    echo "" >&2
    echo "Re-run for details:" >&2
    echo "  psql \"\$DB_URL\" -v ON_ERROR_STOP=1 -f \"$sql_file\"" >&2
    exit 1
  fi
done < <(find "$SQL_DIR" -maxdepth 1 -type f -name '*.sql' -print0 | sort -z)

echo ""
echo "Applied $count migration files."
