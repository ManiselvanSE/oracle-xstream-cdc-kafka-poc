#!/bin/bash
# Streaming only — no historical table snapshot.
#
# 1) Backs up oracle-xstream-rac-docker.json (timestamped .bak next to the file)
# 2) Sets "snapshot.mode": "no_data" in that JSON
# 3) Deletes and recreates the connector (clears Connect offset storage)
#
# Use when offsets imply a completed snapshot (SnapshotResult SKIPPED) but you do NOT want
# initial backfill — only changes from the new streaming position. TPCC topic offsets stay 0
# until there is NEW DML on TPCC after this run (or run run-tpcc-cdc-smoke-test.sh).
#
# Usage (Connect VM, from repo root):
#   CONFIRM=yes ./docker/scripts/connector-recreate-streaming-only.sh
#
# Env (optional):
#   CONNECT_REST  CONNECTOR  CONNECTOR_JSON (same as connector-recreate-full-snapshot.sh)
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
: "${CONNECTOR_JSON:=$PROJECT_DIR/xstream-connector/oracle-xstream-rac-docker.json}"

if [ "${CONFIRM:-}" != "yes" ]; then
  echo "Refusing: set CONFIRM=yes to delete and recreate the connector (streaming-only, snapshot.mode=no_data)."
  echo "This clears Connect offsets but does NOT run an initial table snapshot."
  exit 1
fi

if [ ! -f "$CONNECTOR_JSON" ]; then
  echo "Missing $CONNECTOR_JSON — copy from xstream-connector/oracle-xstream-rac-docker.json.example and edit secrets." >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

BAK="${CONNECTOR_JSON}.bak.$(date +%Y%m%d%H%M%S)"
cp -a "$CONNECTOR_JSON" "$BAK"
echo "Backed up: $BAK"

jq '.config["snapshot.mode"] = "no_data"' "$CONNECTOR_JSON" > "${CONNECTOR_JSON}.tmp"
mv "${CONNECTOR_JSON}.tmp" "$CONNECTOR_JSON"
echo "Set snapshot.mode=no_data in $CONNECTOR_JSON"

export CONFIRM=yes
exec "$SCRIPT_DIR/connector-recreate-full-snapshot.sh"
