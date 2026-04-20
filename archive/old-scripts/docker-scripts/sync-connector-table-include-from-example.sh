#!/usr/bin/env bash
# Copy only config["table.include.list"] from oracle-xstream-rac-docker.json.example into
# oracle-xstream-rac-docker.json (preserves passwords, database.service.name, etc.).
# Use after editing the example when you want the live connector JSON to match captured tables (e.g. TPCC regex).
#
# Run from repo root:
#   ./docker/scripts/sync-connector-table-include-from-example.sh
# Env:
#   CONNECTOR_JSON=xstream-connector/oracle-xstream-rac-docker.json
#   CONNECTOR_EXAMPLE=xstream-connector/oracle-xstream-rac-docker.json.example
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
: "${CONNECTOR_JSON:=$PROJECT_DIR/xstream-connector/oracle-xstream-rac-docker.json}"
: "${CONNECTOR_EXAMPLE:=$PROJECT_DIR/xstream-connector/oracle-xstream-rac-docker.json.example}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq required" >&2
  exit 1
fi
if [ ! -f "$CONNECTOR_JSON" ]; then
  echo "Missing $CONNECTOR_JSON" >&2
  exit 1
fi
if [ ! -f "$CONNECTOR_EXAMPLE" ]; then
  echo "Missing $CONNECTOR_EXAMPLE" >&2
  exit 1
fi

LIST=$(jq -r '.config["table.include.list"] // empty' "$CONNECTOR_EXAMPLE")
if [ -z "$LIST" ]; then
  echo "table.include.list empty in $CONNECTOR_EXAMPLE" >&2
  exit 1
fi

TMP="${CONNECTOR_JSON}.tmp.$$"
jq --arg list "$LIST" '.config["table.include.list"] = $list' "$CONNECTOR_JSON" > "$TMP"
mv "$TMP" "$CONNECTOR_JSON"
echo "Updated table.include.list in $CONNECTOR_JSON from $CONNECTOR_EXAMPLE"
