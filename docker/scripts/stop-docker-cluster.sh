#!/bin/bash
# Stop Kafka cluster (with or without monitoring)
# Run from project root: ./docker/scripts/stop-docker-cluster.sh
# Use --monitoring to also stop Prometheus, Grafana, Kafka Exporter

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$(cd "$SCRIPT_DIR/../.." && pwd)"

USE_MONITORING=false
[ "$1" = "--monitoring" ] && USE_MONITORING=true

echo "=== Stopping Docker cluster ==="
if [ "$USE_MONITORING" = true ]; then
  docker compose -f "$DOCKER_DIR/docker-compose.yml" -f "$DOCKER_DIR/docker-compose.monitoring.yml" down
else
  docker compose -f "$DOCKER_DIR/docker-compose.yml" -f "$DOCKER_DIR/docker-compose.monitoring.yml" down 2>/dev/null || \
  docker compose -f "$DOCKER_DIR/docker-compose.yml" down
fi

echo "Done. Data is preserved in Docker volumes."
echo "To remove volumes: docker compose -f docker/docker-compose.yml -f docker/docker-compose.monitoring.yml down -v"
