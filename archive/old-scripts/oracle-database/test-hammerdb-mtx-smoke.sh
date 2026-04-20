#!/usr/bin/env bash
# Local smoke checks for HammerDB MTX load artifacts (no Oracle required).
# For a real DB test, run on the HammerDB VM with TNS + password (see INSTALL in hammerdb-mtx-vm-bundle).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "== 1) Regenerate SQL from DDL (generator must succeed) =="
python3 generate-hammerdb-mtx-multitable-wave.py > /tmp/hammerdb-mtx-multitable-wave.gen.sql
test -s /tmp/hammerdb-mtx-multitable-wave.gen.sql
test -s hammerdb-mtx-items-only-insert.sql

echo "== 2) Drift check: repo wave SQL matches generator output (re-run gen after DDL edits) =="
if ! cmp -s hammerdb-mtx-multitable-wave.sql /tmp/hammerdb-mtx-multitable-wave.gen.sql; then
  echo "WARN: hammerdb-mtx-multitable-wave.sql differs from generator output." >&2
  echo "      Run: python3 generate-hammerdb-mtx-multitable-wave.py > hammerdb-mtx-multitable-wave.sql" >&2
  exit 1
fi
echo "    OK: committed wave SQL matches generator."

echo "== 3) Wave covers 24 MTX tables (one INSERT block each) =="
n=$(grep -c 'INSERT INTO ORDERMGMT\.MTX_' hammerdb-mtx-multitable-wave.sql || true)
if [[ "$n" -ne 24 ]]; then
  echo "FAIL: expected 24 INSERT INTO ORDERMGMT.MTX_* lines, got $n" >&2
  exit 1
fi
echo "    OK: $n MTX INSERT blocks."

echo "== 4) items_only INSERT lists all MTX_TRANSACTION_ITEMS columns =="
# First line after comment: INSERT ... ( col1, col2, ... )
line=$(grep -n '^INSERT INTO ORDERMGMT.MTX_TRANSACTION_ITEMS' hammerdb-mtx-items-only-insert.sql | head -1 | cut -d: -f2-)
nc=$(echo "$line" | tr ',' '\n' | wc -l | tr -d ' ')
if [[ "${nc:-0}" -lt 50 ]]; then
  echo "FAIL: MTX_TRANSACTION_ITEMS column list looks short ($nc fields)" >&2
  exit 1
fi
echo "    OK: items-only INSERT lists $nc columns (must match 12-create-mtx-transaction-items.sql)."

echo "== 5) Required files beside driver =="
for f in hammerdb-mtx-multitable-wave.sql hammerdb-mtx-items-only-insert.sql hammerdb-mtx-custom-driver.tcl hammerdb-mtx-transaction-items-run.tcl; do
  test -f "$f" || { echo "FAIL: missing $f"; exit 1; }
done
echo "    OK."

echo ""
echo "All local smoke checks passed."
echo ""
echo "To test against Oracle (HammerDB VM or host with sqlplus + hammerdbcli):"
echo "  export HDB_MTX_PASS='<ordermgmt_password>'"
echo "  export HDB_MTX_TNS='<your_tns_alias>'"
echo "  export HDB_MTX_TOTAL_ITERATIONS=10"
echo "  export HDB_MTX_RAISEERROR=true"
echo "  source ./hammerdb-oracle-env.sh   # set ORACLE_HOME / PATH on that host"
echo "  ./hammerdb-mtx-run-production.sh"
