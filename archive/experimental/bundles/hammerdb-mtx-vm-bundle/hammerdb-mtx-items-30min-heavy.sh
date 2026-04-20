#!/usr/bin/env bash
# Sustained heavy load on ORDERMGMT.MTX_TRANSACTION_ITEMS for 30 minutes (default).
# Uses HDB_MTX_DURATION_SECONDS (time-bound loop) + extra parallel VUs for high redo and log switches.
#
#   source hammerdb-oracle-env.sh
#   export HDB_MTX_PASS='<ordermgmt_password>'
#   ./hammerdb-mtx-items-30min-heavy.sh 2>&1 | tee mtx-30min-heavy.log
#
# Optional env:
#   HDB_MTX_DURATION_SECONDS=1800   (default 1800 = 30 min)
#   HDB_MTX_VUS=32                  (override; default = min(2×nproc, HDB_MTX_VUS_MAX))
#   HDB_MTX_VUS_MAX=64              (cap when auto-selecting VUs)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HDB_MTX_SCRIPT_DIR="${HDB_MTX_SCRIPT_DIR:-$SCRIPT_DIR}"
# shellcheck source=./hammerdb-oracle-env.sh
source "${SCRIPT_DIR}/hammerdb-oracle-env.sh"

: "${HDB_MTX_PASS:?Set HDB_MTX_PASS to ORDERMGMT password}"

export HDB_MTX_USER="${HDB_MTX_USER:-ordermgmt}"
export HDB_MTX_TNS="${HDB_MTX_TNS:-RAC_XSTRPDB_POC}"
export HDB_MTX_MODE="${HDB_MTX_MODE:-items_only}"
export HDB_MTX_DURATION_SECONDS="${HDB_MTX_DURATION_SECONDS:-1800}"
export HDB_MTX_TOTAL_ITERATIONS="${HDB_MTX_TOTAL_ITERATIONS:-999999999}"
export HDB_MTX_RAISEERROR="${HDB_MTX_RAISEERROR:-false}"
export HDB_MTX_NO_TC="${HDB_MTX_NO_TC:-true}"
export HDB_MTX_PAYLOAD_BYTES="${HDB_MTX_PAYLOAD_BYTES:-0}"

if [[ -z "${HDB_MTX_VUS:-}" ]]; then
  N=$(nproc 2>/dev/null || echo 8)
  MAX_V="${HDB_MTX_VUS_MAX:-64}"
  V=$(( N * 2 ))
  if (( V > MAX_V )); then V=$MAX_V; fi
  if (( V < 1 )); then V=1; fi
  export HDB_MTX_VUS=$V
fi

echo "hammerdb-mtx-items-30min-heavy: duration=${HDB_MTX_DURATION_SECONDS}s vu=${HDB_MTX_VUS} mode=${HDB_MTX_MODE}"

exec hammerdbcli tcl auto "${SCRIPT_DIR}/hammerdb-mtx-transaction-items-run.tcl"
