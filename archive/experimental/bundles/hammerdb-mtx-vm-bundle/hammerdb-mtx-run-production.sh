#!/usr/bin/env bash
# Run HammerDB CLI: ORDERMGMT.MTX_TRANSACTION_ITEMS CDC load (not TPCC).
# Default HDB_MTX_MODE=items_only (single table; max throughput path aligned with connector).
# Multi-table wave: HDB_MTX_MODE=all_mtx (needs hammerdb-mtx-multitable-wave.sql beside driver).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# HammerDB VU threads resolve [info script] to "." for customscript — wave SQL must use this path.
export HDB_MTX_SCRIPT_DIR="${HDB_MTX_SCRIPT_DIR:-$SCRIPT_DIR}"
# shellcheck source=./hammerdb-oracle-env.sh
source "${SCRIPT_DIR}/hammerdb-oracle-env.sh"

: "${HDB_MTX_PASS:?Set HDB_MTX_PASS to ORDERMGMT password}"

export HDB_MTX_USER="${HDB_MTX_USER:-ordermgmt}"
export HDB_MTX_TNS="${HDB_MTX_TNS:-RAC_XSTRPDB_POC}"
export HDB_MTX_TOTAL_ITERATIONS="${HDB_MTX_TOTAL_ITERATIONS:-100000}"
# Optional: HDB_MTX_DURATION_SECONDS (e.g. 1800) — time-bound run; see hammerdb-mtx-items-30min-heavy.sh
export HDB_MTX_DURATION_SECONDS="${HDB_MTX_DURATION_SECONDS:-}"
export HDB_MTX_RAISEERROR="${HDB_MTX_RAISEERROR:-false}"
export HDB_MTX_MODE="${HDB_MTX_MODE:-items_only}"
# Skip HammerDB transaction counter unless false (avoids spurious ORA-28000 on custom MTX driver).
export HDB_MTX_NO_TC="${HDB_MTX_NO_TC:-true}"
# When INSERT lists CDC_PAYLOAD, :plbd must be bound (0 = small CLOB path on DB).
export HDB_MTX_PAYLOAD_BYTES="${HDB_MTX_PAYLOAD_BYTES:-0}"

exec hammerdbcli tcl auto "${SCRIPT_DIR}/hammerdb-mtx-transaction-items-run.tcl"
