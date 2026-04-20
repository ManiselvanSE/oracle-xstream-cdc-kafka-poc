#!/bin/bash
# Run UG prod CDC load generator (ORDERMGMT + MTX* inserts in 17-generate-ug-prod-cdc-load.sql)
# Usage: ./run-generate-ug-prod-cdc-load.sh
#   ORDMGMT_PWD='...' ORACLE_CONN=RAC_XSTRPDB_POC ./run-generate-ug-prod-cdc-load.sh
# Env:
#   ORDMGMT_PWD / ORACLE_PWD  — ordermgmt password
#   ORACLE_CONN — TNS alias (default XSTRPDB; use RAC_XSTRPDB_POC on HammerDB/RAC VM)
#   ORACLE_USER — default ordermgmt

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ORACLE_USER="${ORACLE_USER:-ordermgmt}"
ORACLE_PWD="${ORDMGMT_PWD:-${ORACLE_PWD:-YourP@ssw0rd123}}"
: "${ORACLE_CONN:=XSTRPDB}"

echo "UG Prod CDC Load - inserting test rows (includes ORDERMGMT.MTX*)"
echo "Connect: ${ORACLE_USER}@${ORACLE_CONN}"
echo ""

if [[ "$ORACLE_PWD" == *"@"* ]]; then
  sqlplus -S /nolog <<SQLEOF
CONNECT "$ORACLE_USER"/"$ORACLE_PWD"@$ORACLE_CONN
@17-generate-ug-prod-cdc-load.sql
EXIT;
SQLEOF
else
  sqlplus -S "$ORACLE_USER/$ORACLE_PWD@$ORACLE_CONN" "@17-generate-ug-prod-cdc-load.sql"
fi

echo ""
echo "Done. On Connect VM: cd ~/oracle-xstream-cdc-poc && ./docker/scripts/check-ordermgmt-mtx-kafka-offsets.sh"
