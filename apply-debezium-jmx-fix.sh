#!/usr/bin/env bash
# Apply updated monitoring/jmx/kafka-connect.yml and restart Connect so JMX exports Debezium metrics.
#
# Run on the machine where the stack runs (the VM with docker compose), after:
#   git pull   # or copy monitoring/jmx/kafka-connect.yml into place
#
# Usage:
#   ./apply-debezium-jmx-fix.sh
#   PROMETHEUS_URL=http://127.0.0.1:9090 ./apply-debezium-jmx-fix.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT/docker"

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not available on this machine." >&2
  echo "Copy this repo to your Connect VM (or sync monitoring/jmx/kafka-connect.yml), then run:" >&2
  echo "  cd /path/to/oracle-xstream-cdc-poc && ./apply-debezium-jmx-fix.sh" >&2
  exit 1
fi

echo "==> Restarting connect (reloads JMX config from bind mount)..."
docker compose restart connect

echo "==> Waiting for Connect JMX (20s)..."
sleep 20

echo "==> Debezium lines from JMX /metrics (sample):"
if docker compose exec -T connect curl -fsS http://127.0.0.1:9991/metrics 2>/dev/null | grep -E '^debezium_oracle_connector_' | head -15; then
  :
else
  echo "(none — connector may be DOWN or MBean name still differs; see monitoring/jmx/kafka-connect.yml)" >&2
fi

PROMETHEUS_URL="${PROMETHEUS_URL:-}"
if [[ -n "$PROMETHEUS_URL" ]]; then
  echo "==> Checking Prometheus at $PROMETHEUS_URL ..."
  export PROMETHEUS_URL
  "$ROOT/monitoring/scripts/validate-debezium-prometheus-metrics.sh" && echo "Prometheus OK."
else
  echo "Optional: set PROMETHEUS_URL (e.g. http://127.0.0.1:9090) to validate Prometheus after scrape interval."
fi
