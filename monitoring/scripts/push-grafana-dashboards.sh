#!/usr/bin/env bash
# Push dashboard JSON files to Grafana HTTP API (Grafana 9+).
# Usage:
#   export GRAFANA_URL='http://137.131.53.98:3000'
#   export GRAFANA_USER='admin'
#   export GRAFANA_PASS='your-password'
#   ./monitoring/scripts/push-grafana-dashboards.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DASH_DIR="${ROOT}/monitoring/grafana/dashboards"

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:?Set GRAFANA_PASS}"

for f in kafka-overview.json oracle-xstream-cdc-source-selfhosted.json connect-cluster-metrics.json; do
  path="${DASH_DIR}/${f}"
  if [[ ! -f "$path" ]]; then
    echo "Skip (missing): $path" >&2
    continue
  fi
  echo "Importing $f ..."
  jq --argjson dash "$(cat "$path")" -n '{dashboard: $dash, overwrite: true}' \
    | curl -fsS -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
      -H "Content-Type: application/json" \
      -X POST "${GRAFANA_URL%/}/api/dashboards/db" \
      -d @- | jq -r '.status // .message // .'
done
echo "Done."
