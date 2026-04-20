#!/usr/bin/env bash
# Run on the host where Prometheus runs (Docker stack with docker-compose.monitoring.yml).
# Reloads Prometheus to pick up monitoring/prometheus/recording/*.yml after git pull or rsync.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT/docker"

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running or not available. Start Docker and retry." >&2
  exit 1
fi

# Ensure recording rules directory is mounted (compose file must include ../monitoring/prometheus/recording)
if [ ! -f "$ROOT/monitoring/prometheus/recording/cdc-golden.yml" ]; then
  echo "Missing $ROOT/monitoring/prometheus/recording/cdc-golden.yml" >&2
  exit 1
fi

echo "=== Recreating Prometheus with recording rules mount (if compose changed) ==="
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d prometheus

echo "=== Reloading Prometheus config (HTTP POST /-/reload) ==="
if docker exec prometheus wget -qO- --post-data='' http://127.0.0.1:9090/-/reload 2>/dev/null; then
  echo "Reload OK."
else
  echo "WARN: reload failed (Prometheus may need --web.enable-lifecycle or container name differs). Restart manually: docker compose restart prometheus"
fi

echo "=== Quick rule check (Prometheus UI rules API) ==="
docker exec prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/rules' 2>/dev/null | head -c 400 || true
echo ""
echo "Done. In Grafana: re-import dashboards from monitoring/grafana/dashboards/ or restart Grafana if using file provisioning."
