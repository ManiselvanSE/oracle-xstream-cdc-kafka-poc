#!/bin/bash
# Run CDC throughput generator against Oracle
# Usage: ./run-generate-cdc-throughput.sh
# Set ORDMGMT_PWD if password has special chars: ORDMGMT_PWD='YourP@ssw0rd123' ./run-generate-cdc-throughput.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Connection from connector config (edit if different)
ORACLE_HOST="${ORACLE_HOST:-racdb-scan.sub01061249390.xstrmconnectdb2.oraclevcn.com}"
ORACLE_PORT="${ORACLE_PORT:-1521}"
ORACLE_SERVICE="${ORACLE_SERVICE:-XSTRPDB.sub01061249390.xstrmconnectdb2.oraclevcn.com}"
ORACLE_USER="${ORACLE_USER:-ordermgmt}"
ORACLE_PWD="${ORDMGMT_PWD:-YourP@ssw0rd123}"

export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-/opt/oracle/instantclient/instantclient_19_30}:$LD_LIBRARY_PATH"
export PATH="${ORACLE_INSTANTCLIENT_PATH:-/opt/oracle/instantclient/instantclient_19_30}:$PATH"
export TNS_ADMIN="$SCRIPT_DIR"

echo "Connecting to $ORACLE_USER@XSTRPDB (TNS)"
echo "Running 15-generate-cdc-throughput.sql ..."
echo ""

# Use quoted password if it contains @ or other special chars
if [[ "$ORACLE_PWD" == *"@"* ]]; then
  sqlplus -S /nolog <<SQLEOF
CONNECT "$ORACLE_USER"/"$ORACLE_PWD"@XSTRPDB
@15-generate-cdc-throughput.sql
EXIT;
SQLEOF
else
  sqlplus -S "$ORACLE_USER/$ORACLE_PWD@XSTRPDB" "@15-generate-cdc-throughput.sql"
fi
