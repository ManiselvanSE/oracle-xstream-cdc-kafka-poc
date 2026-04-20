#!/bin/bash
# Deploy Oracle XStream connector to Connect (Docker)
# Run from project root: ./docker/scripts/deploy-connector.sh
# Requires: oracle-xstream-rac.json in xstream-connector/ with correct bootstrap.servers for Docker

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Use oracle-xstream-rac-docker.json; create from .example if missing
CONNECTOR_JSON="$PROJECT_DIR/xstream-connector/oracle-xstream-rac-docker.json"
CONNECTOR_EXAMPLE="$PROJECT_DIR/xstream-connector/oracle-xstream-rac-docker.json.example"
if [ ! -f "$CONNECTOR_JSON" ]; then
  if [ -f "$CONNECTOR_EXAMPLE" ]; then
    cp "$CONNECTOR_EXAMPLE" "$CONNECTOR_JSON"
    echo "Created oracle-xstream-rac-docker.json from .example. Edit it with database.password, database.hostname, database.service.name, then run this script again."
    exit 1
  else
    CONNECTOR_JSON="$PROJECT_DIR/xstream-connector/oracle-xstream-rac.json"
  fi
fi
if [ ! -f "$CONNECTOR_JSON" ]; then
  echo "ERROR: Connector config not found."
  echo "  cp xstream-connector/oracle-xstream-rac-docker.json.example xstream-connector/oracle-xstream-rac-docker.json"
  echo "  Edit oracle-xstream-rac-docker.json with database credentials, then run this script again."
  exit 1
fi
if grep -q "YOUR_PASSWORD" "$CONNECTOR_JSON" 2>/dev/null; then
  echo "ERROR: Edit oracle-xstream-rac-docker.json and replace YOUR_PASSWORD with the real database password."
  exit 1
fi
if grep -q "your-domain\|YOUR_DOMAIN\|your-domain" "$CONNECTOR_JSON" 2>/dev/null; then
  echo "ERROR: oracle-xstream-rac-docker.json still has placeholder database.hostname/service."
  echo "  Fix: ./docker/scripts/sync-docker-connector-oracle-from-rac-json.sh"
  echo "  or edit database.hostname to match docker-compose extra_hosts (see docker/.env.example)."
  exit 1
fi

echo "Deploying connector from $CONNECTOR_JSON..."
curl -s -X POST -H "Content-Type: application/json" \
  --data @"$CONNECTOR_JSON" \
  http://localhost:8083/connectors

echo ""
echo "Check status: curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq ."
