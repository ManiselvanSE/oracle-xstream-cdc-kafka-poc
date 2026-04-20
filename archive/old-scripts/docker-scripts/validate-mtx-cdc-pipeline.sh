#!/bin/bash
# Validate ORDERMGMT.MTX* CDC path on the Kafka Connect VM (no Oracle access required).
# Usage: ./docker/scripts/validate-mtx-cdc-pipeline.sh
# Env: CONNECT_REST=http://localhost:8083  KAFKA_BS=kafka1:29092,kafka2:29092,kafka3:29092

set -e
: "${CONNECT_REST:=http://localhost:8083}"
: "${CONNECTOR:=oracle-xstream-rac-connector}"
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
echo "=== 3) table.include.list is ORDERMGMT.MTX* (regex) ==="
CFG=$(curl -sf "${CONNECT_REST}/connectors/${CONNECTOR}/config") || { echo "FAIL: GET config"; exit 1; }
LIST=$(echo "$CFG" | jq -r '.["table.include.list"] // empty')
if [ -z "$LIST" ]; then
  echo "FAIL: table.include.list empty"
  exit 1
fi
if echo "$LIST" | grep -q 'ORDERMGMT' && echo "$LIST" | grep -q 'MTX'; then
  echo "OK: ORDERMGMT + MTX in table.include.list (e.g. ORDERMGMT\\.MTX.* or ORDERMGMT\\.MTX_TRANSACTION_ITEMS)"
else
  echo "FAIL: expected ORDERMGMT.MTX* regex — sync from xstream-connector/oracle-xstream-rac-docker.json.example"
  exit 1
fi
if echo "$LIST" | grep -qE 'TPCC|tpcc'; then
  echo "WARN: TPCC still present in table.include.list (MTX-only policy may want it removed)"
fi

echo ""
echo "=== 4) Kafka end offsets (sample MTX topics) ==="
MTX_TOPICS=(
  racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS
  racdb.ORDERMGMT.MTX_TRANSACTION_HEADER
)
N_NONZERO=0
for TOPIC in "${MTX_TOPICS[@]}"; do
  OFFSET_OUT=$(docker exec -e KAFKA_OPTS= kafka1 kafka-get-offsets --bootstrap-server "$KAFKA_BS" --topic "$TOPIC" --time -1 2>/dev/null || true)
  if echo "$OFFSET_OUT" | grep -q .; then
    SUM=$(echo "$OFFSET_OUT" | awk -F: '{sum+=$3} END{print sum+0}')
    echo "$TOPIC → end offset: $SUM"
    if [ "${SUM:-0}" -gt 0 ] 2>/dev/null; then
      N_NONZERO=$((N_NONZERO + 1))
    fi
  else
    echo "$TOPIC → (could not read offsets — topic may not exist yet)"
  fi
done
if [ "$N_NONZERO" -eq 0 ]; then
  echo "WARN: MTX sample topic offsets are 0 — run HammerDB MTX load + confirm XStream rules (verify-mtx-xstream-rules.sql)"
else
  echo "OK: $N_NONZERO / ${#MTX_TOPICS[@]} sample MTX topics have messages"
fi

echo ""
echo "=== Summary ==="
echo "Oracle: run oracle-database/verify-mtx-xstream-rules.sql (SYSDBA) to confirm outbound rules for ORDERMGMT.MTX*."
