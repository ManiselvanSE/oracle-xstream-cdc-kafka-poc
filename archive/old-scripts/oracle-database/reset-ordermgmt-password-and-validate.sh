#!/usr/bin/env bash
# Reset ORDERMGMT password (as SYSDBA) and validate sqlplus connectivity.
#
# Run on a host with sqlplus + tnsnames for your PDB (export TNS_ADMIN if needed).
#
# Example (password shown only as illustration — use your SYS password):
#   export TNS_ADMIN=~/oracle/network/admin
#   SYSDBA_PWD='<sys_password>' NEW_ORDMGMT_PWD='ConFL#_uent12' ORDERMGMT_TNS='RAC_XSTRPDB_POC' \\
#     ./reset-ordermgmt-password-and-validate.sh
#
# Uses unlock-ordermgmt.sh for ALTER USER + unlock + profile limits, then validate-ordermgmt-connectivity.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export SYSDBA_PWD="${SYSDBA_PWD:?Set SYSDBA_PWD (SYS password for sqlplus sys/... as sysdba)}"
export NEW_ORDMGMT_PWD="${NEW_ORDMGMT_PWD:?Set NEW_ORDMGMT_PWD (new ORDERMGMT password)}"
export ORDERMGMT_TNS="${ORDERMGMT_TNS:-RAC_XSTRPDB_POC}"

echo "=== Step 1: reset ORDERMGMT password (SYSDBA) ==="
"$SCRIPT_DIR/unlock-ordermgmt.sh"

echo ""
echo "=== Step 2: validate ORDERMGMT connectivity ==="
export ORACLE_CONN="$ORDERMGMT_TNS"
export ORDMGMT_PWD="$NEW_ORDMGMT_PWD"
"$SCRIPT_DIR/validate-ordermgmt-connectivity.sh"

echo ""
echo "For HammerDB MTX load, use the same password as NEW_ORDMGMT_PWD:"
echo "  export HDB_MTX_PASS='...'"
echo "  export HDB_MTX_TNS=${ORDERMGMT_TNS}"
