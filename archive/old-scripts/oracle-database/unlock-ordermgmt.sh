#!/bin/bash
# Unlock ordermgmt and set password
# Run on VM where sqlplus is available.
# Usage: SYSDBA_PWD='<sys_password>' NEW_ORDMGMT_PWD='<new_ordermgmt_password>' ./unlock-ordermgmt.sh
#   Or: ./unlock-ordermgmt.sh <SYSDBA_PASSWORD>  (requires NEW_ORDMGMT_PWD env for new ordermgmt password)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
export TNS_ADMIN="$SCRIPT_DIR"

SYSDBA_PWD="${1:-${SYSDBA_PWD:?Set SYSDBA_PWD or pass as arg 1}}"
NEW_PWD="${NEW_ORDMGMT_PWD:?Set NEW_ORDMGMT_PWD for the new ordermgmt password}"

echo "Unlocking ordermgmt and setting password"
echo "Using sys with provided SYSDBA password to XSTRPDB..."

sqlplus -S "sys/${SYSDBA_PWD}@XSTRPDB as sysdba" << EOF
ALTER USER ordermgmt ACCOUNT UNLOCK;
SELECT profile FROM dba_users WHERE username='ORDMGMT';
ALTER PROFILE DEFAULT LIMIT PASSWORD_REUSE_MAX UNLIMITED;
ALTER PROFILE DEFAULT LIMIT PASSWORD_REUSE_TIME UNLIMITED;
ALTER USER ordermgmt IDENTIFIED BY "$NEW_PWD";
ALTER PROFILE DEFAULT LIMIT PASSWORD_REUSE_MAX 10;
ALTER PROFILE DEFAULT LIMIT PASSWORD_REUSE_TIME 10;
EXIT;
EOF

echo "Done. You can now run:"
echo "  export ORDMGMT_PWD='<password>'"
echo "  ./run-generate-heavy-cdc-load.sh 50000"
