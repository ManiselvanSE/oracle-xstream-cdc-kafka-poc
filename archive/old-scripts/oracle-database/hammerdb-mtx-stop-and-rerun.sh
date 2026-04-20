#!/usr/bin/env bash
# Stop any running HammerDB CLI job, then start the MTX CDC load again.
# Run on the HammerDB host (same directory as hammerdb-mtx-run-production.sh).
#
# Required:
#   export HDB_MTX_PASS='<ordermgmt_password>'
#
# Optional (same as hammerdb-mtx-run-production.sh):
#   HDB_MTX_USER HDB_MTX_TNS HDB_MTX_TOTAL_ITERATIONS HDB_MTX_MODE HDB_MTX_VUS HDB_MTX_NO_TC HDB_MTX_SCRIPT_DIR
#
# Usage:
#   source hammerdb-oracle-env.sh
#   export HDB_MTX_PASS='...'
#   ./hammerdb-mtx-stop-and-rerun.sh 2>&1 | tee mtx-run.log
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

: "${HDB_MTX_PASS:?Set HDB_MTX_PASS (ORDERMGMT password)}"

# shellcheck source=./hammerdb-oracle-env.sh
source "${SCRIPT_DIR}/hammerdb-oracle-env.sh"

echo "=== Stopping any running hammerdbcli load ==="
if [ -x "${SCRIPT_DIR}/stop-hammerdb-load.sh" ]; then
  "${SCRIPT_DIR}/stop-hammerdb-load.sh" || true
else
  echo "WARNING: stop-hammerdb-load.sh missing; trying pkill" >&2
  pkill -TERM -f 'hammerdbcli.*(tcl|auto)' 2>/dev/null || true
  sleep 2
fi

sleep 1
if pgrep -f 'hammerdbcli' >/dev/null 2>&1; then
  echo "WARNING: hammerdbcli still running — check: pgrep -af hammerdbcli" >&2
fi

echo ""
echo "=== Starting MTX load (hammerdb-mtx-run-production.sh) ==="
exec "${SCRIPT_DIR}/hammerdb-mtx-run-production.sh"
