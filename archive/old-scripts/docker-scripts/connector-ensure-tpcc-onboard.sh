#!/bin/bash
# On Kafka Connect VM: merge TPCC into table.include.list, PUT config, restart connector.
# Not used for MTX-only CDC (table.include.list=ORDERMGMT.MTX.*) — use oracle-xstream-rac-docker.json.example instead.
# Does NOT fix Oracle — run hammerdb-tpcc-onboard-xstream.sql + hammerdb-tpcc-onboard-xstream.sh first.
# Usage: ./docker/scripts/connector-ensure-tpcc-onboard.sh
# Env: CONNECT_REST=http://localhost:8083  CONNECTOR=oracle-xstream-rac-connector

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
: "${CONNECT_REST:=http://localhost:8083}"
: "${CONNECTOR:=oracle-xstream-rac-connector}"

TPCC_SUFFIX='|TPCC\\.(DISTRICT|CUSTOMER|HISTORY|ITEM|WAREHOUSE|STOCK|ORDERS|NEW_ORDER|ORDER_LINE)'

echo "=== Ensure TPCC in table.include.list and restart ==="

if ! command -v jq >/dev/null 2>&1; then
  echo "jq required" >&2
  exit 1
fi

CFG=$(curl -s "${CONNECT_REST}/connectors/${CONNECTOR}/config")
if [ -z "$CFG" ] || ! echo "$CFG" | jq -e . >/dev/null 2>&1; then
  echo "Failed to GET connector config from ${CONNECT_REST}" >&2
  exit 1
fi

CUR=$(echo "$CFG" | jq -r '.["table.include.list"] // empty')
if [ -z "$CUR" ]; then
  echo "table.include.list is empty in live config — fix connector JSON first." >&2
  exit 1
fi
if echo "$CUR" | grep -q 'TPCC'; then
  echo "table.include.list already references TPCC."
else
  echo "Appending TPCC pattern to table.include.list..."
  NEW="${CUR}${TPCC_SUFFIX}"
  echo "$CFG" | jq --arg list "$NEW" '.["table.include.list"] = $list' > /tmp/conn_cfg_put.json
  HTTP=$(curl -s -o /tmp/conn_put_resp.txt -w "%{http_code}" -X PUT -H "Content-Type: application/json" \
    -d @/tmp/conn_cfg_put.json "${CONNECT_REST}/connectors/${CONNECTOR}/config")
  echo "HTTP $HTTP"
  if [ "$HTTP" != "200" ]; then
    head -c 500 /tmp/conn_put_resp.txt >&2
    echo "" >&2
    exit 1
  fi
  head -c 200 /tmp/conn_put_resp.txt
  echo ""
fi

echo "Restarting connector..."
curl -s -X POST "${CONNECT_REST}/connectors/${CONNECTOR}/restart?includeTasks=true" || true
echo ""
echo "Done. Check: curl -s ${CONNECT_REST}/connectors/${CONNECTOR}/status | jq ."
echo "If topics stay empty, run Oracle verify: sqlplus ... @oracle-database/verify-tpcc-cdc-prereqs.sql"
echo "If Oracle is OK but still no historical rows, see HAMMERDB-RAC-LOAD.md § TPC-C → Kafka CDC (full resnapshot)."
