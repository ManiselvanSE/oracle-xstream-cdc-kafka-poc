#!/bin/bash
# Nuclear option: DELETE connector and POST it again from JSON — clears Connect offsets.
# With snapshot.mode=initial in JSON, re-snapshots ALL tables (slow; PoC only).
# Repo defaults to snapshot.mode=no_data (streaming only); this script is rarely needed.
#
# Usage (on Connect VM, from repo root):
#   ./docker/scripts/connector-recreate-full-snapshot.sh
# Env:
#   CONNECT_REST=http://localhost:8083
#   CONNECTOR_JSON=xstream-connector/oracle-xstream-rac-docker.json
#   CONFIRM=yes   required to actually run

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
: "${CONNECT_REST:=http://localhost:8083}"
: "${CONNECTOR:=oracle-xstream-rac-connector}"
: "${CONNECTOR_JSON:=$PROJECT_DIR/xstream-connector/oracle-xstream-rac-docker.json}"

if [ "${CONFIRM:-}" != "yes" ]; then
  echo "Refusing: set CONFIRM=yes to delete and recreate ${CONNECTOR}."
  echo "This re-snapshots every table in table.include.list and can take a long time."
  exit 1
fi

if [ ! -f "$CONNECTOR_JSON" ]; then
  echo "Missing $CONNECTOR_JSON" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  SM=$(jq -r '.config["snapshot.mode"] // empty' "$CONNECTOR_JSON" 2>/dev/null || echo "")
  if [ "$SM" = "no_data" ] || [ -z "$SM" ]; then
    echo "WARNING: $CONNECTOR_JSON has snapshot.mode=${SM:-unset}. For full table backfill to Kafka, set \"snapshot.mode\": \"initial\" in that file before running." >&2
  fi
fi

echo "Deleting ${CONNECTOR}..."
curl -s -X DELETE "${CONNECT_REST}/connectors/${CONNECTOR}" || true
sleep 5

echo "Creating ${CONNECTOR}..."
curl -s -X POST -H "Content-Type: application/json" --data @"$CONNECTOR_JSON" \
  --max-time 300 "${CONNECT_REST}/connectors"

echo ""
curl -s "${CONNECT_REST}/connectors/${CONNECTOR}/status" | jq . 2>/dev/null || true
