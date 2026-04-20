#!/bin/bash
# Set snapshot.mode=initial on the running connector and restart (request table snapshot).
# Use when you need existing Oracle rows emitted to Kafka (e.g. after import), not only new DML.
#
# If offsets were already committed under no_data, a PUT alone may not re-snapshot everything —
# then use connector-recreate-full-snapshot.sh with CONFIRM=yes after editing your connector
# JSON so "snapshot.mode": "initial" (see docs/HAMMERDB-RAC-LOAD.md §8.3).
#
# Usage (Connect VM): ./docker/scripts/connector-apply-initial-snapshot.sh
# Env: CONNECT_REST=http://localhost:8083  CONNECTOR=oracle-xstream-rac-connector

set -e
: "${CONNECT_REST:=http://localhost:8083}"
: "${CONNECTOR:=oracle-xstream-rac-connector}"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

CFG=$(curl -sf "${CONNECT_REST}/connectors/${CONNECTOR}/config") || {
  echo "Failed to GET ${CONNECTOR} config" >&2
  exit 1
}

echo "$CFG" | jq '. + {"snapshot.mode": "initial"}' > /tmp/conn_initial_snap.json
HTTP=$(curl -s -o /tmp/conn_initial_snap_resp.txt -w "%{http_code}" -X PUT -H "Content-Type: application/json" \
  -d @/tmp/conn_initial_snap.json "${CONNECT_REST}/connectors/${CONNECTOR}/config")
echo "PUT snapshot.mode=initial → HTTP $HTTP"
[ "$HTTP" = "200" ] || { cat /tmp/conn_initial_snap_resp.txt >&2; exit 1; }

curl -s -X POST "${CONNECT_REST}/connectors/${CONNECTOR}/restart?includeTasks=true" || true
echo "Restart requested. Status: curl -s ${CONNECT_REST}/connectors/${CONNECTOR}/status | jq ."
echo "Note: if topics stay empty, connector may have already committed offsets — see HAMMERDB-RAC-LOAD.md §8.3"
