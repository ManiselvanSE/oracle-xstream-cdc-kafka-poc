#!/bin/bash
# Complete migration - deploy connector (run on VM after Docker cluster is up)
# Usage: ./docker/scripts/complete-migration-on-vm.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

CONNECTOR_JSON="$PROJECT_DIR/xstream-connector/oracle-xstream-rac-docker.json"
CONNECTOR_EXAMPLE="$PROJECT_DIR/xstream-connector/oracle-xstream-rac-docker.json.example"
if [ ! -f "$CONNECTOR_JSON" ]; then
  if [ -f "$CONNECTOR_EXAMPLE" ]; then
    cp "$CONNECTOR_EXAMPLE" "$CONNECTOR_JSON"
    echo "Created oracle-xstream-rac-docker.json from .example. Edit it with database.password, database.hostname, database.service.name, then run this script again."
    exit 1
  fi
fi
if [ ! -f "$CONNECTOR_JSON" ]; then
  echo "ERROR: xstream-connector/oracle-xstream-rac-docker.json not found."
  echo "  cp xstream-connector/oracle-xstream-rac-docker.json.example xstream-connector/oracle-xstream-rac-docker.json"
  echo "  Edit with credentials, then run again."
  exit 1
fi
if grep -q "YOUR_PASSWORD" "$CONNECTOR_JSON" 2>/dev/null; then
  echo "ERROR: Edit oracle-xstream-rac-docker.json and replace YOUR_PASSWORD with the real database password."
  exit 1
fi
echo "Deploying Oracle XStream connector..."
curl -s -X POST -H "Content-Type: application/json" \
  --max-time 180 \
  --data @"$CONNECTOR_JSON" \
  http://localhost:8083/connectors

echo ""
echo "Check status: curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq ."
