#!/usr/bin/env bash
# Restart Kafka Connect so the JVM reloads monitoring/jmx/kafka-connect.yml (read at process start).
# Run from repo root or pass path to docker-compose dir.
set -euo pipefail
COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$COMPOSE_DIR"
echo "Restarting connect..."
docker compose restart connect
echo "Waiting for REST + JMX (15s)..."
sleep 15
echo "Sample Debezium Prometheus lines (expect non-empty after connector RUNNING):"
docker compose exec -T connect curl -fsS http://127.0.0.1:9991/metrics 2>/dev/null | grep -E 'debezium_oracle_connector_(milliseconds_behind_source|total_number_of_events_seen)' | head -8 || {
  echo "(no debezium_* lines yet — confirm connector status and topic.prefix; check ObjectName in JConsole if still empty)"
  exit 1
}
