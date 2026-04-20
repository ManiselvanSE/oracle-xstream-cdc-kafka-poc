#!/bin/bash
# Run heavy CDC load generator against Oracle
# Usage: ./run-generate-heavy-cdc-load.sh [rows]
#   rows: optional, default 10000 (e.g. 50000 for heavier load)
# Set ORDMGMT_PWD if password has special chars: ORDMGMT_PWD='YourP@ssw0rd123' ./run-generate-heavy-cdc-load.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ROWS="${1:-10000}"

# Connection from connector config (edit if different)
ORACLE_USER="${ORACLE_USER:-ordermgmt}"
ORACLE_PWD="${ORDMGMT_PWD:-YourP@ssw0rd123}"

export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-/opt/oracle/instantclient/instantclient_19_30}:$LD_LIBRARY_PATH"
export PATH="${ORACLE_INSTANTCLIENT_PATH:-/opt/oracle/instantclient/instantclient_19_30}:$PATH"
export TNS_ADMIN="$SCRIPT_DIR"

echo "Heavy CDC Load - $ROWS inserts"
echo "Connecting to $ORACLE_USER@XSTRPDB (TNS)"
echo "Watch Grafana: Connector Throughput, CDC Throughput"
echo ""

# Use quoted password if it contains @ or other special chars
if [[ "$ORACLE_PWD" == *"@"* ]]; then
  sqlplus -S /nolog <<SQLEOF
CONNECT "$ORACLE_USER"/"$ORACLE_PWD"@XSTRPDB
@16-generate-heavy-cdc-load.sql $ROWS
EXIT;
SQLEOF
else
  sqlplus -S "$ORACLE_USER/$ORACLE_PWD@XSTRPDB" "@16-generate-heavy-cdc-load.sql" "$ROWS"
fi
