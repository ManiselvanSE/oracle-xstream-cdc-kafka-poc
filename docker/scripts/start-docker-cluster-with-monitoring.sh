#!/bin/bash
# Start 3-broker Kafka cluster + Schema Registry + Connect + Monitoring (Prometheus, Grafana, JMX)
# Run from project root: ./docker/scripts/start-docker-cluster-with-monitoring.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# Remove conflicting containers from previous standalone monitoring setup (if any)
for c in kafka-exporter prometheus grafana; do
  docker rm -f "$c" 2>/dev/null || true
done

# Ensure .env exists for ORACLE_INSTANTCLIENT_PATH
if [ ! -f "$DOCKER_DIR/.env" ]; then
  if [ -f "$DOCKER_DIR/.env.example" ]; then
    cp "$DOCKER_DIR/.env.example" "$DOCKER_DIR/.env"
    echo "Created docker/.env from .env.example. Edit docker/.env to set ORACLE_INSTANTCLIENT_PATH."
  fi
fi

echo "=== Building JMX-enabled images (first run may take a few minutes) ==="
docker compose -f "$DOCKER_DIR/docker-compose.yml" -f "$DOCKER_DIR/docker-compose.monitoring.yml" build

echo ""
echo "=== Starting cluster with monitoring ==="
docker compose -f "$DOCKER_DIR/docker-compose.yml" -f "$DOCKER_DIR/docker-compose.monitoring.yml" up -d

echo ""
echo "Waiting for Kafka brokers (up to 90s)..."
for i in $(seq 1 18); do
  if docker exec -e KAFKA_OPTS= kafka1 kafka-broker-api-versions --bootstrap-server localhost:9092 2>/dev/null | head -1 | grep -q "9092"; then
    echo "Kafka ready."
    break
  fi
  [ $i -eq 18 ] && echo "Kafka may still be starting. Check: docker logs kafka1"
  sleep 5
done

echo ""
echo "Waiting for Connect REST API (up to 60s)..."
for i in $(seq 1 12); do
  if curl -s -H "Accept: application/json" --max-time 5 http://localhost:8083/connectors 2>/dev/null | grep -qE '^\['; then
    echo "Connect ready."
    break
  fi
  [ $i -eq 12 ] && echo "Connect may still be starting. Check: docker logs connect"
  sleep 5
done

echo ""
echo "=== Cluster with monitoring started ==="
echo "Kafka: localhost:9092, 9094, 9095"
echo "Schema Registry: http://localhost:8081"
echo "Connect: http://localhost:8083"
echo "Prometheus: http://localhost:9090"
echo "Grafana: http://localhost:3000 (admin/admin)"
echo "Kafka Exporter: http://localhost:9308/metrics"
echo ""
echo "See monitoring/README.md for full setup and verification."
