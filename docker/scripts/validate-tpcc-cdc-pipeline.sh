#!/bin/bash
# Validate TPCC CDC path on the Kafka Connect VM (no Oracle access required).
# For ORDERMGMT.MTX* only, use: ./validate-mtx-cdc-pipeline.sh
# Usage: ./docker/scripts/validate-tpcc-cdc-pipeline.sh
# Env: CONNECT_REST=http://localhost:8083  KAFKA_BS=kafka1:29092,kafka2:29092,kafka3:29092

set -e
: "${CONNECT_REST:=http://localhost:8083}"
: "${CONNECTOR:=oracle-xstream-rac-connector}"
# Bootstrap for kafka-get-offsets (Kafka 3.7+ removed kafka.tools.GetOffsetShell)
: "${KAFKA_BS:=kafka1:29092}"

echo "=== 1) Connect REST ==="
code=$(curl -s -o /tmp/v_curl.txt -w "%{http_code}" "${CONNECT_REST}/" || true)
if [ "$code" != "200" ]; then
  echo "FAIL: Connect REST ${CONNECT_REST} HTTP $code"
  cat /tmp/v_curl.txt 2>/dev/null | head -5
  exit 1
fi
echo "OK: Connect REST reachable"

echo ""
echo "=== 2) Connector status ==="
STATUS=$(curl -sf "${CONNECT_REST}/connectors/${CONNECTOR}/status") || { echo "FAIL: GET /connectors/${CONNECTOR}/status"; exit 1; }
echo "$STATUS" | jq .
STATE=$(echo "$STATUS" | jq -r '.connector.state // empty')
TASK=$(echo "$STATUS" | jq -r '.tasks[0].state // empty')
if [ "$STATE" != "RUNNING" ] || [ "$TASK" != "RUNNING" ]; then
  echo "WARN: connector state=$STATE task=$TASK (expected RUNNING/RUNNING)"
else
  echo "OK: connector and task RUNNING"
fi

echo ""
echo "=== 3) table.include.list contains TPCC ==="
CFG=$(curl -sf "${CONNECT_REST}/connectors/${CONNECTOR}/config") || { echo "FAIL: GET config"; exit 1; }
LIST=$(echo "$CFG" | jq -r '.["table.include.list"] // empty')
if [ -z "$LIST" ]; then
  echo "FAIL: table.include.list empty"
  exit 1
fi
if echo "$LIST" | grep -qE 'TPCC|tpcc'; then
  echo "OK: TPCC referenced in table.include.list"
else
  echo "FAIL: TPCC not in table.include.list — run connector-ensure-tpcc-onboard.sh"
  exit 1
fi

echo ""
echo "=== 4) Kafka end offsets (all TPCC topics) ==="
# Clear KAFKA_OPTS: broker image sets JMX javaagent; without this, CLI JVMs try to bind :9990 and fail.
# Use kafka-get-offsets (Kafka 3.7+); kafka.tools.GetOffsetShell no longer exists.
TPCC_TOPICS=(
  racdb.TPCC.DISTRICT
  racdb.TPCC.CUSTOMER
  racdb.TPCC.HISTORY
  racdb.TPCC.ITEM
  racdb.TPCC.WAREHOUSE
  racdb.TPCC.STOCK
  racdb.TPCC.ORDERS
  racdb.TPCC.NEW_ORDER
  racdb.TPCC.ORDER_LINE
)
N_NONZERO=0
for TOPIC in "${TPCC_TOPICS[@]}"; do
  OFFSET_OUT=$(docker exec -e KAFKA_OPTS= kafka1 kafka-get-offsets --bootstrap-server "$KAFKA_BS" --topic "$TOPIC" --time -1 2>/dev/null || true)
  if echo "$OFFSET_OUT" | grep -q .; then
    SUM=$(echo "$OFFSET_OUT" | awk -F: '{sum+=$3} END{print sum+0}')
    echo "$TOPIC → end offset: $SUM"
    if [ "${SUM:-0}" -gt 0 ] 2>/dev/null; then
      N_NONZERO=$((N_NONZERO + 1))
    fi
  else
    echo "$TOPIC → (could not read offsets)"
  fi
done
if [ "$N_NONZERO" -eq 0 ]; then
  echo "WARN: all TPCC end offsets are 0 — see HAMMERDB-RAC-LOAD.md §8 (snapshot.mode=no_data, XStream rules, DML after cutover)"
else
  echo "OK: $N_NONZERO / ${#TPCC_TOPICS[@]} TPCC topics have at least one message"
fi

echo ""
echo "=== Summary ==="
echo "Connector config and REST checks passed. If offsets are 0, fix Oracle XStream + snapshot policy + workload timing, not this script."
