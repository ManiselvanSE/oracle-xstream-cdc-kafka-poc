#!/usr/bin/env bash
# Run on the HammerDB host (sqlplus + hammerdbcli available).
# Steps: (1) stop any running hammerdbcli MTX load (2) unlock ORDERMGMT as SYSDBA (3) run MTX with a small wave count.
#
# Required env:
#   HDB_MTX_PASS        — ORDERMGMT password
#
# Required only if unlock runs (default). Not needed if SKIP_UNLOCK=1:
#   SYSDBA_PWD          — SYS password for sqlplus "sys/...@... as sysdba"
#
# Optional:
#   SYSDBA_TNS          — TNS alias for SYS sqlplus (default: same as HDB_MTX_TNS, e.g. RAC_XSTRPDB_POC).
#                         Use the service that exists in \$TNS_ADMIN/tnsnames.ora — bare XSTRPDB often gives ORA-12154.
#   SKIP_STOP=1         — do not kill hammerdbcli
#   SKIP_UNLOCK=1       — skip ALTER USER ... UNLOCK (use when account is already unlocked; no SYSDBA_PWD)
#   HDB_MTX_TOTAL_ITERATIONS — default 10 (small smoke)
#   HDB_MTX_VUS       — virtual users (default 1 for this script; full load: unset or e.g. 16)
#   HDB_MTX_USER HDB_MTX_TNS HDB_MTX_MODE  — passed through to hammerdb-mtx-run-production.sh
#
# Example (full unlock + load):
#   export SYSDBA_PWD='<sys_password>'
#   export HDB_MTX_PASS='<ordermgmt_password>'
#   ./hammerdb-mtx-stop-unlock-and-smoke.sh
#
# Example (already unlocked — only stop + small load):
#   export HDB_MTX_PASS='<ordermgmt_password>'
#   SKIP_UNLOCK=1 ./hammerdb-mtx-stop-unlock-and-smoke.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

: "${HDB_MTX_PASS:?Set HDB_MTX_PASS (ORDERMGMT password)}"

export HDB_MTX_USER="${HDB_MTX_USER:-ordermgmt}"
export HDB_MTX_TNS="${HDB_MTX_TNS:-RAC_XSTRPDB_POC}"
# Match ORDERMGMT/HammerDB — must resolve via tnsnames (ORA-12154 if wrong alias).
SYSDBA_TNS="${SYSDBA_TNS:-$HDB_MTX_TNS}"
export HDB_MTX_TOTAL_ITERATIONS="${HDB_MTX_TOTAL_ITERATIONS:-10}"
export HDB_MTX_VUS="${HDB_MTX_VUS:-1}"
export HDB_MTX_RAISEERROR="${HDB_MTX_RAISEERROR:-true}"
export HDB_MTX_MODE="${HDB_MTX_MODE:-all_mtx}"
ORACLE_APP_USER="${ORACLE_APP_USER:-ORDERMGMT}"

# shellcheck source=./hammerdb-oracle-env.sh
source "${SCRIPT_DIR}/hammerdb-oracle-env.sh"

echo "=== Step 1/3: stop HammerDB CLI load (if any) ==="
if [ "${SKIP_STOP:-0}" != "1" ]; then
  "${SCRIPT_DIR}/stop-hammerdb-load.sh" || true
else
  echo "SKIP_STOP=1 — not stopping hammerdbcli."
fi

echo ""
echo "=== Step 2/3: unlock ${ORACLE_APP_USER} (SYSDBA) ==="
if [ "${SKIP_UNLOCK:-0}" != "1" ]; then
  : "${SYSDBA_PWD:?Set SYSDBA_PWD (SYS password), or run with SKIP_UNLOCK=1 if ORDERMGMT is already unlocked}"
  if ! command -v sqlplus >/dev/null 2>&1; then
    echo "ERROR: sqlplus not in PATH. source hammerdb-oracle-env.sh or install Instant Client." >&2
    exit 1
  fi
  echo "Connecting sys as SYSDBA via TNS alias: ${SYSDBA_TNS} (set TNS_ADMIN in hammerdb-oracle-env.sh; override SYSDBA_TNS if needed)"
  # Quoted password avoids sqlplus misparsing # @ / in SYSDBA_PWD; /nolog + CONNECT is reliable.
  sqlplus -S /nolog <<EOF
WHENEVER SQLERROR EXIT SQL.SQLCODE
CONNECT sys/"${SYSDBA_PWD}"@${SYSDBA_TNS} AS SYSDBA
ALTER USER ${ORACLE_APP_USER} ACCOUNT UNLOCK;
EXIT;
EOF
  echo "Unlock OK."
else
  echo "SKIP_UNLOCK=1 — not running ALTER USER."
fi

echo ""
echo "=== Step 3/3: MTX load (HDB_MTX_TOTAL_ITERATIONS=${HDB_MTX_TOTAL_ITERATIONS} waves) ==="
exec "${SCRIPT_DIR}/hammerdb-mtx-run-production.sh"
