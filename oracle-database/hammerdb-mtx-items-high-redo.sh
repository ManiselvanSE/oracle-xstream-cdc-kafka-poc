#!/usr/bin/env bash
# Heavy MTX_TRANSACTION_ITEMS load aimed at high Oracle redo and frequent log switches.
# Uses hammerdb-mtx-items-30min-heavy.sh with a higher VU cap (more parallel inserts → more redo/sec).
#
#   source hammerdb-oracle-env.sh && export HDB_MTX_PASS='…'
#   ./hammerdb-mtx-items-high-redo.sh 2>&1 | tee mtx-high-redo.log
#
# Env (optional):
#   HDB_MTX_VUS_MAX=96|128   cap when auto-selecting VUs (default 96)
#   HDB_MTX_DURATION_SECONDS=1800
#   HDB_MTX_VUS=N          fixed VU count (overrides auto)
#
# Oracle: monitor log switches with @mtx-heavy-load-redo-and-switches.sql (SYSDBA). Online redo size is a DBA setting.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HDB_MTX_VUS_MAX="${HDB_MTX_VUS_MAX:-96}"
export HDB_MTX_DURATION_SECONDS="${HDB_MTX_DURATION_SECONDS:-1800}"
# More parallel VUs than default 30min script (2×nproc) → higher redo/sec and more log switches (with smaller online redo).
if [[ -z "${HDB_MTX_VUS:-}" ]]; then
  N=$(nproc 2>/dev/null || echo 8)
  MAX_V="${HDB_MTX_VUS_MAX}"
  V=$(( N * 3 ))
  if (( V > MAX_V )); then V=$MAX_V; fi
  if (( V < 1 )); then V=1; fi
  export HDB_MTX_VUS=$V
fi
exec "${SCRIPT_DIR}/hammerdb-mtx-items-30min-heavy.sh"
