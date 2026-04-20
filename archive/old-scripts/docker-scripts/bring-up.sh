#!/bin/bash
# Bring up the full Oracle XStream CDC stack: Kafka + Connect + Prometheus + Grafana + Connector
# Run from project root: ./docker/scripts/bring-up.sh
# Or from VM via SSH: ssh opc@<vm-ip> "cd ~/oracle-xstream-cdc-poc && ./docker/scripts/bring-up.sh"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "=== Oracle XStream CDC – Full Bring-Up ==="

# 1. Stop any existing stack (base + monitoring)
echo ""
echo "[1/6] Stopping any existing containers..."
docker compose -f "$DOCKER_DIR/docker-compose.yml" -f "$DOCKER_DIR/docker-compose.monitoring.yml" down 2>/dev/null || true
sleep 3

# Remove orphans from previous runs
for c in kafka-exporter prometheus grafana kafka1 kafka2 kafka3 connect schema-registry; do
  docker rm -f "$c" 2>/dev/null || true
done
sleep 2

# 2. Ensure .env exists
if [ ! -f "$DOCKER_DIR/.env" ]; then
  if [ -f "$DOCKER_DIR/.env.example" ]; then
    cp "$DOCKER_DIR/.env.example" "$DOCKER_DIR/.env"
    echo "Created docker/.env from .env.example. Edit docker/.env to set ORACLE_INSTANTCLIENT_PATH."
  fi
fi

# 3. Build and start cluster with monitoring
echo ""
echo "[2/6] Building and starting cluster (Kafka, Connect, Prometheus, Grafana)..."
docker compose -f "$DOCKER_DIR/docker-compose.yml" -f "$DOCKER_DIR/docker-compose.monitoring.yml" build

docker compose -f "$DOCKER_DIR/docker-compose.yml" -f "$DOCKER_DIR/docker-compose.monitoring.yml" up -d

# 4. Wait for Kafka
echo ""
echo "[3/6] Waiting for Kafka (up to 90s)..."
for i in $(seq 1 18); do
  if docker exec -e KAFKA_OPTS= kafka1 kafka-broker-api-versions --bootstrap-server localhost:9092 2>/dev/null | head -1 | grep -q "9092"; then
    echo "Kafka ready."
    break
  fi
  [ $i -eq 18 ] && { echo "Kafka failed to start. Check: docker logs kafka1"; exit 1; }
  sleep 5
done

# 5. Wait for Connect
echo ""
echo "[4/6] Waiting for Connect REST API (up to 90s)..."
for i in $(seq 1 18); do
  if curl -s -H "Accept: application/json" --max-time 5 http://localhost:8083/connectors 2>/dev/null | grep -qE '^\['; then
    echo "Connect ready."
    break
  fi
  [ $i -eq 18 ] && { echo "Connect failed to start. Check: docker logs connect"; exit 1; }
  sleep 5
done

# 6. Pre-create topics
echo ""
echo "[5/6] Pre-creating CDC topics..."
"$SCRIPT_DIR/precreate-topics.sh"

# 7. Deploy or restart connector
echo ""
echo "[6/6] Deploying connector..."

CONNECTOR_JSON="$PROJECT_DIR/xstream-connector/oracle-xstream-rac-docker.json"
CONNECTOR_EXAMPLE="$PROJECT_DIR/xstream-connector/oracle-xstream-rac-docker.json.example"

# Sync table.include.list from .example into user config (keeps credentials)
if [ -f "$CONNECTOR_JSON" ] && [ -f "$CONNECTOR_EXAMPLE" ] && command -v jq >/dev/null 2>&1; then
  NEW_LIST=$(jq -r '.config["table.include.list"]' "$CONNECTOR_EXAMPLE" 2>/dev/null)
  if [ -n "$NEW_LIST" ] && [ "$NEW_LIST" != "null" ]; then
    jq --arg list "$NEW_LIST" '.config["table.include.list"] = $list' "$CONNECTOR_JSON" > "${CONNECTOR_JSON}.tmp" && mv "${CONNECTOR_JSON}.tmp" "$CONNECTOR_JSON"
  fi
fi

if [ ! -f "$CONNECTOR_JSON" ]; then
  if [ -f "$CONNECTOR_EXAMPLE" ]; then
    cp "$CONNECTOR_EXAMPLE" "$CONNECTOR_JSON"
    echo "Created oracle-xstream-rac-docker.json from example. EDIT IT with database.password, database.hostname, database.service.name before deploying."
    echo "Skipping connector deploy. After editing, run: ./docker/scripts/complete-migration-on-vm.sh"
  else
    echo "WARNING: Neither oracle-xstream-rac-docker.json nor .example found. Create config and run: ./docker/scripts/complete-migration-on-vm.sh"
  fi
else
  # Warn if config has placeholder password
  if grep -q "YOUR_PASSWORD" "$CONNECTOR_JSON" 2>/dev/null; then
    echo "WARNING: oracle-xstream-rac-docker.json contains YOUR_PASSWORD. Edit it with real credentials, then run: ./docker/scripts/complete-migration-on-vm.sh"
    echo "Skipping connector deploy."
  # Check if connector already exists
  elif curl -s http://localhost:8083/connectors 2>/dev/null | grep -q "oracle-xstream-rac-connector"; then
    echo "Connector exists. Restarting..."
    curl -s -X POST http://localhost:8083/connectors/oracle-xstream-rac-connector/restart || true
  else
    echo "Creating connector..."
    curl -s -X POST -H "Content-Type: application/json" \
      --data @"$CONNECTOR_JSON" \
      --max-time 60 http://localhost:8083/connectors || true
  fi
fi

# 8. Status summary
echo ""
echo "=== Bring-Up Complete ==="
echo ""
echo "Services:"
echo "  Kafka:         localhost:9092, 9094, 9095"
echo "  Connect:       http://localhost:8083"
echo "  Schema Reg:    http://localhost:8081"
echo "  Prometheus:    http://localhost:9090"
echo "  Grafana:       http://localhost:3000 (admin/admin)"
echo "  Kafka Exporter: http://localhost:9308/metrics"
echo ""
echo "Connector status:"
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status 2>/dev/null | head -5 || echo "  (run: curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq .)"
echo ""
echo "From your Mac, use SSH port forwarding to access:"
echo "  ssh -i <key> -L 3000:localhost:3000 -L 8083:localhost:8083 -L 9090:localhost:9090 opc@<vm-ip>"
echo "  Then open: http://localhost:3000 (Grafana), http://localhost:8083 (Connect), http://localhost:9090 (Prometheus)"
