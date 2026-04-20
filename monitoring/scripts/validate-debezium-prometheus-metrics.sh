#!/usr/bin/env bash
# Check that Debezium Oracle streaming MBean metrics are present in Prometheus
# (after JMX exporter rules in monitoring/jmx/kafka-connect.yml are applied).
#
# Usage:
#   export PROMETHEUS_URL='http://127.0.0.1:9090'
#   ./monitoring/scripts/validate-debezium-prometheus-metrics.sh
set -euo pipefail
PROMETHEUS_URL="${PROMETHEUS_URL:-http://127.0.0.1:9090}"
BASE="${PROMETHEUS_URL%/}"

check() {
  local name="$1"
  local out
  out="$(curl -fsS -G "${BASE}/api/v1/query" --data-urlencode "query=${name}" 2>/dev/null || echo '{}')"
  local status
  status="$(echo "$out" | jq -r '.status // "error"')"
  local n
  n="$(echo "$out" | jq '[.data.result[]?] | length')"
  if [[ "$status" == "success" && "$n" -gt 0 ]]; then
    echo "OK  $name ($n series)"
  else
    echo "MISSING or empty: $name (Prometheus status=$status, series=$n)"
    return 1
  fi
}

echo "Checking ${BASE} ..."
fail=0
check debezium_oracle_connector_milliseconds_behind_source || fail=1
check debezium_oracle_connector_commit_milliseconds_behind_source || fail=1
check debezium_oracle_connector_milliseconds_since_last_event || fail=1
check debezium_oracle_connector_total_number_of_events_seen || fail=1
check debezium_oracle_connector_total_number_of_create_events_seen || fail=1
check debezium_oracle_connector_total_number_of_update_events_seen || fail=1
check debezium_oracle_connector_total_number_of_delete_events_seen || fail=1
check debezium_oracle_connector_number_of_committed_transactions || fail=1
check debezium_oracle_connector_queue_remaining_capacity || fail=1
check debezium_oracle_connector_queue_total_capacity || fail=1

if [[ "$fail" -ne 0 ]]; then
  echo >&2 ""
  echo >&2 "Fix: ensure Kafka Connect runs with JMX exporter + monitoring/jmx/kafka-connect.yml,"
  echo >&2 "whitelist debezium.confluent.oracle:*, and Prometheus scrapes the Connect JMX port."
  exit 1
fi
echo "All Debezium Oracle connector streaming metrics found."
