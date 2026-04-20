#!/usr/bin/env bash
# Run on the host where Prometheus listens (e.g. localhost:9090).
# Explains "only JVM works" vs missing Debezium / broker throughput series.
set -euo pipefail
BASE="${PROM_URL:-http://127.0.0.1:9090}"

q() {
  curl -fsS -G "$BASE/api/v1/query" --data-urlencode "query=$1" | jq -r '.data.result | length' 2>/dev/null || echo "ERR"
}

echo "Prometheus: $BASE"
echo "--- Series counts (0 = nothing scraped / wrong job / connector down) ---"
echo "debezium_oracle_connector_total_number_of_events_seen: $(q 'debezium_oracle_connector_total_number_of_events_seen')"
echo "kafka_connect_source_task_metrics_source_record_write_rate: $(q 'kafka_connect_source_task_metrics_source_record_write_rate')"
echo "kafka_server_brokertopicmetrics_messagesin_total: $(q 'kafka_server_brokertopicmetrics_messagesin_total')"
echo "kafka_producer_record_send_rate (any job): $(q 'kafka_producer_record_send_rate')"
echo ""
echo "If Debezium=0: ensure monitoring/jmx/kafka-connect.yml has debezium.confluent.oracle:* and restart Connect."
echo "If broker messagesin=0: check kafka-broker scrape targets; brokers must expose BrokerTopicMetrics."
echo "If all non-zero but Grafana empty: re-import kafka-overview.json and check time range."
