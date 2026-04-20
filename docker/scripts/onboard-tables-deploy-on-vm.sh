#!/bin/bash
# Deploy onboarded tables to Kafka: pre-create topics, sync connector config, restart connector
# Run on VM after Oracle onboarding (ug-prod-ordermgmt-drop-and-create.sql + ug-prod-onboard-xstream.sh)
# Usage: ./docker/scripts/onboard-tables-deploy-on-vm.sh
# Prereq: Docker cluster running (Kafka, Connect), connector config exists

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

CONNECTOR_JSON="$PROJECT_DIR/xstream-connector/oracle-xstream-rac-docker.json"
CONNECTOR_EXAMPLE="$PROJECT_DIR/xstream-connector/oracle-xstream-rac-docker.json.example"

cd "$PROJECT_DIR"

echo "=== Onboard Tables – Deploy to Kafka (VM) ==="

# 1. Pre-create topics
echo ""
echo "[1/3] Pre-creating CDC topics..."
"$SCRIPT_DIR/precreate-topics.sh"

# 2. Sync table.include.list from .example into user config (preserve credentials)
if [ -f "$CONNECTOR_EXAMPLE" ] && [ -f "$CONNECTOR_JSON" ]; then
  echo ""
  echo "[2/3] Syncing table.include.list from template..."
  if command -v jq >/dev/null 2>&1; then
    NEW_LIST=$(jq -r '.config["table.include.list"]' "$CONNECTOR_EXAMPLE")
    jq --arg list "$NEW_LIST" '.config["table.include.list"] = $list' "$CONNECTOR_JSON" > "${CONNECTOR_JSON}.tmp"
    mv "${CONNECTOR_JSON}.tmp" "$CONNECTOR_JSON"
    echo "Updated table.include.list"
  else
    echo "jq not found – skipping table.include.list sync. Manually update $CONNECTOR_JSON from $CONNECTOR_EXAMPLE"
  fi
else
  echo "[2/3] Config files missing – ensure oracle-xstream-rac-docker.json exists"
fi

# 3. Update connector config and restart
echo ""
echo "[3/3] Updating connector and restarting..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8083/connectors/oracle-xstream-rac-connector 2>/dev/null | grep -q 200; then
  # Connector exists – PUT updated config and restart
  if command -v jq >/dev/null 2>&1; then
    jq -c '.config' "$CONNECTOR_JSON" 2>/dev/null | \
      curl -s -X PUT -H "Content-Type: application/json" -d @- \
      http://localhost:8083/connectors/oracle-xstream-rac-connector/config && echo "Config updated."
  fi
  echo "Restarting connector..."
  curl -s -X POST "http://localhost:8083/connectors/oracle-xstream-rac-connector/restart?includeTasks=true" || true
else
  # Connector not deployed – create it
  if [ -f "$CONNECTOR_JSON" ] && ! grep -q "YOUR_PASSWORD" "$CONNECTOR_JSON" 2>/dev/null; then
    echo "Creating connector..."
    curl -s -X POST -H "Content-Type: application/json" \
      --data @"$CONNECTOR_JSON" \
      --max-time 180 http://localhost:8083/connectors || true
  else
    echo "Skipping connector deploy (missing config or YOUR_PASSWORD). Run complete-migration-on-vm.sh after editing credentials."
  fi
fi

echo ""
echo "=== Done ==="
echo "Topics: docker exec kafka2 kafka-topics --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 --list | grep racdb"
echo "Load data: cd oracle-database && ./run-generate-ug-prod-cdc-load.sh  # populates UG prod tables for CDC"
