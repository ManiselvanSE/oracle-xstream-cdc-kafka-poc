#!/bin/bash
# Verify Kafka Connect connector config vs repo expectations (ORDERMGMT.MTX*; TPCC optional).
# Does NOT query Oracle — run oracle-database/verify-ordermgmt-vs-tpcc-cdc-prereqs.sql on DB.
#
# Usage (Connect VM): ./docker/scripts/verify-cdc-stack.sh
# Env: CONNECT_REST=http://localhost:8083  CONNECTOR=oracle-xstream-rac-connector
#
set -euo pipefail
: "${CONNECT_REST:=http://localhost:8083}"
: "${CONNECTOR:=oracle-xstream-rac-connector}"

echo "=== 1) Connect REST ==="
code=$(curl -s -o /tmp/vcdc_cfg.json -w "%{http_code}" "${CONNECT_REST}/connectors/${CONNECTOR}/config") || true
if [ "$code" != "200" ]; then
  echo "FAIL: GET /connectors/${CONNECTOR}/config → HTTP $code"
  exit 1
fi
echo "OK: connector config HTTP 200"

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required"; exit 1; }

echo ""
echo "=== 2) Required connector keys ==="
for key in \
  connector.class \
  database.pdb.name \
  database.out.server.name \
  database.service.name \
  topic.prefix \
  snapshot.mode \
  "table.include.list"; do
  v=$(jq -r --arg k "$key" '.[$k] // empty' /tmp/vcdc_cfg.json)
  if [ -z "$v" ]; then
    echo "FAIL: missing or empty: $key"
  else
    echo "OK: $key = ${v:0:120}$([ ${#v} -gt 120 ] && echo ...)"
  fi
done

echo ""
echo "=== 3) table.include.list — ORDERMGMT.MTX* (repo default) or TPCC (optional) ==="
LIST=$(jq -r '.["table.include.list"] // empty' /tmp/vcdc_cfg.json)
TPCC_EXPECT='TPCC\.\(DISTRICT|CUSTOMER|HISTORY|ITEM|WAREHOUSE|STOCK|ORDERS|NEW_ORDER|ORDER_LINE\)'
if echo "$LIST" | grep -qE 'ORDERMGMT\\\.MTX|ORDERMGMT\.MTX'; then
  echo "OK: ORDERMGMT.MTX* pattern present (MTX-only CDC)"
elif echo "$LIST" | grep -q 'TPCC' && echo "$LIST" | grep -qE "$TPCC_EXPECT"; then
  echo "OK: TPCC nine-table regex present"
elif echo "$LIST" | grep -q 'TPCC'; then
  echo "WARN: TPCC substring but pattern may not match hammerdb-tpcc-onboard-xstream.sh"
else
  echo "WARN: neither ORDERMGMT.MTX* nor TPCC detected — compare to oracle-xstream-rac-docker.json.example"
fi

echo ""
echo "=== 4) snapshot.mode (streaming-only PoC uses no_data) ==="
SM=$(jq -r '.["snapshot.mode"] // empty' /tmp/vcdc_cfg.json)
echo "  snapshot.mode = $SM"
if [ "$SM" = "no_data" ]; then
  echo "  INFO: no_data → existing rows are not backfilled; need DML + XStream rules for new changes."
fi

echo ""
echo "=== 5) Connector + task RUNNING ==="
curl -sf "${CONNECT_REST}/connectors/${CONNECTOR}/status" -o /tmp/vcdc_st.json || { echo "FAIL: status"; exit 1; }
CS=$(jq -r '.connector.state // empty' /tmp/vcdc_st.json)
TS=$(jq -r '.tasks[0].state // empty' /tmp/vcdc_st.json)
echo "  connector.state = $CS"
echo "  tasks[0].state = $TS"
if [ "$CS" = "RUNNING" ] && [ "$TS" = "RUNNING" ]; then
  echo "OK"
else
  echo "WARN: not fully RUNNING — check docker logs connect"
fi

echo ""
echo "=== 6) Oracle (manual) — run as SYSDBA in PDB/CDB ==="
echo "  sqlplus ... @oracle-database/verify-mtx-xstream-rules.sql"
echo "  sqlplus ... @oracle-database/verify-ordermgmt-vs-tpcc-cdc-prereqs.sql"
echo "  sqlplus ... @oracle-database/verify-xstream-rules-detail.sql"
echo "MTX-only onboarding: ORACLE_PWD=... ./oracle-database/ug-prod-onboard-xstream.sh"
echo "TPCC (if used): oracle-database/hammerdb-tpcc-onboard-xstream.sh"
echo ""
echo "Done."
