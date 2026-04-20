#!/bin/bash
# Set snapshot.mode=no_data on the running connector (streaming only, no initial table snapshot).
# Usage (Connect VM): ./docker/scripts/connector-apply-streaming-only.sh
# Env: CONNECT_REST=http://localhost:8083  CONNECTOR=oracle-xstream-rac-connector
#
# Also patches xstream-connector/oracle-xstream-rac-docker.json on disk so scripts like
# onboard-tables-deploy-on-vm.sh (which PUT .config from that file) do not revert to initial.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONNECTOR_JSON="$PROJECT_DIR/xstream-connector/oracle-xstream-rac-docker.json"
: "${CONNECT_REST:=http://localhost:8083}"
: "${CONNECTOR:=oracle-xstream-rac-connector}"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

CFG=$(curl -sf "${CONNECT_REST}/connectors/${CONNECTOR}/config") || {
  echo "Failed to GET ${CONNECTOR} config" >&2
  exit 1
}

echo "$CFG" | jq '. + {"snapshot.mode": "no_data"}' > /tmp/conn_no_snap.json
HTTP=$(curl -s -o /tmp/conn_no_snap_resp.txt -w "%{http_code}" -X PUT -H "Content-Type: application/json" \
  -d @/tmp/conn_no_snap.json "${CONNECT_REST}/connectors/${CONNECTOR}/config")
echo "PUT snapshot.mode=no_data → HTTP $HTTP"
[ "$HTTP" = "200" ] || { cat /tmp/conn_no_snap_resp.txt >&2; exit 1; }

if [ -f "$CONNECTOR_JSON" ]; then
  jq '.config["snapshot.mode"] = "no_data"' "$CONNECTOR_JSON" > "${CONNECTOR_JSON}.tmp" && mv "${CONNECTOR_JSON}.tmp" "$CONNECTOR_JSON"
  echo "Updated on-disk $CONNECTOR_JSON → snapshot.mode=no_data"
fi

curl -s -X POST "${CONNECT_REST}/connectors/${CONNECTOR}/restart?includeTasks=true" || true
echo "Verify: curl -s ${CONNECT_REST}/connectors/${CONNECTOR}/config | jq -r '.[\"snapshot.mode\"]'"
curl -sf "${CONNECT_REST}/connectors/${CONNECTOR}/config" | jq -r '"Live snapshot.mode = " + (.["snapshot.mode"] // "null")'
echo "Restart requested. Status: curl -s ${CONNECT_REST}/connectors/${CONNECTOR}/status | jq ."
