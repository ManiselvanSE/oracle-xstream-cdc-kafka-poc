#!/usr/bin/env bash
# =============================================================================
# Grafana Metrics Collection Script
# Captures metrics from Grafana API for the test period
# =============================================================================

set -euo pipefail

GRAFANA_HOST="137.131.53.98"
GRAFANA_PORT="3000"
GRAFANA_URL="http://${GRAFANA_HOST}:${GRAFANA_PORT}"

# Dashboard UID (extract from URL if different)
DASHBOARD_UID="xstream-throughput-performance"

# Test period (pass as arguments or use defaults)
START_TIME="${1:-$(date -u -v-1H +%s)000}"  # 1 hour ago in milliseconds
END_TIME="${2:-$(date -u +%s)000}"          # now in milliseconds

OUTPUT_DIR="${3:-grafana-metrics-$(date +%Y%m%d_%H%M%S)}"

mkdir -p "${OUTPUT_DIR}"

echo "=========================================="
echo "Grafana Metrics Collection"
echo "=========================================="
echo ""
echo "Grafana: ${GRAFANA_URL}"
echo "Dashboard: ${DASHBOARD_UID}"
echo "Time Range: $(date -r $((START_TIME/1000))) to $(date -r $((END_TIME/1000)))"
echo "Output: ${OUTPUT_DIR}"
echo ""

# Function to query Prometheus via Grafana
query_prometheus() {
    local query="$1"
    local output_file="$2"

    echo "Querying: ${query}"

    curl -s -G "${GRAFANA_URL}/api/datasources/proxy/1/api/v1/query_range" \
        --data-urlencode "query=${query}" \
        --data-urlencode "start=$((START_TIME/1000))" \
        --data-urlencode "end=$((END_TIME/1000))" \
        --data-urlencode "step=30" \
        -o "${OUTPUT_DIR}/${output_file}"

    if [ -f "${OUTPUT_DIR}/${output_file}" ]; then
        echo "  ✓ Saved to ${output_file}"
    else
        echo "  ✗ Failed to save ${output_file}"
    fi
}

echo "=== Collecting Oracle Metrics ==="
echo ""

# Oracle redo rate
query_prometheus \
    "rate(oracledb_redo_size_bytes[5m])" \
    "oracle-redo-rate.json"

# Archive log generation
query_prometheus \
    "oracledb_archivelog_count" \
    "oracle-archivelog-count.json"

# Session count
query_prometheus \
    "oracledb_sessions_value" \
    "oracle-sessions.json"

echo ""
echo "=== Collecting Kafka Metrics ==="
echo ""

# Kafka consumer lag
query_prometheus \
    "kafka_consumer_group_lag" \
    "kafka-consumer-lag.json"

# Kafka topic bytes in
query_prometheus \
    "rate(kafka_server_brokertopicmetrics_bytesin_total[5m])" \
    "kafka-bytes-in.json"

# Kafka messages in
query_prometheus \
    "rate(kafka_server_brokertopicmetrics_messagesin_total[5m])" \
    "kafka-messages-in.json"

echo ""
echo "=== Collecting XStream Connector Metrics ==="
echo ""

# Connector throughput
query_prometheus \
    "rate(kafka_connect_source_task_source_record_write_total[5m])" \
    "connector-throughput.json"

# Connector errors
query_prometheus \
    "kafka_connect_source_task_source_record_poll_total" \
    "connector-errors.json"

echo ""
echo "=== Processing Metrics ==="
echo ""

# Parse JSON and extract key statistics
cat > "${OUTPUT_DIR}/metrics-summary.txt" <<EOF
Metrics Summary
===============

Test Period: $(date -r $((START_TIME/1000))) to $(date -r $((END_TIME/1000)))

Oracle Redo Generation:
EOF

# Extract max redo rate if jq is available
if command -v jq &> /dev/null; then
    echo "  Processing with jq..."

    # Oracle redo rate stats
    if [ -f "${OUTPUT_DIR}/oracle-redo-rate.json" ]; then
        MAX_REDO=$(jq -r '.data.result[0].values | map(.[1] | tonumber) | max' "${OUTPUT_DIR}/oracle-redo-rate.json" 2>/dev/null || echo "N/A")
        AVG_REDO=$(jq -r '.data.result[0].values | map(.[1] | tonumber) | add / length' "${OUTPUT_DIR}/oracle-redo-rate.json" 2>/dev/null || echo "N/A")

        cat >> "${OUTPUT_DIR}/metrics-summary.txt" <<EOF
  Max Redo Rate: ${MAX_REDO} bytes/sec
  Avg Redo Rate: ${AVG_REDO} bytes/sec
EOF
    fi

    # Kafka lag stats
    if [ -f "${OUTPUT_DIR}/kafka-consumer-lag.json" ]; then
        MAX_LAG=$(jq -r '.data.result[0].values | map(.[1] | tonumber) | max' "${OUTPUT_DIR}/kafka-consumer-lag.json" 2>/dev/null || echo "N/A")
        AVG_LAG=$(jq -r '.data.result[0].values | map(.[1] | tonumber) | add / length' "${OUTPUT_DIR}/kafka-consumer-lag.json" 2>/dev/null || echo "N/A")

        cat >> "${OUTPUT_DIR}/metrics-summary.txt" <<EOF

Kafka Consumer Lag:
  Max Lag: ${MAX_LAG} messages
  Avg Lag: ${AVG_LAG} messages
EOF
    fi

    # Connector throughput
    if [ -f "${OUTPUT_DIR}/connector-throughput.json" ]; then
        MAX_THROUGHPUT=$(jq -r '.data.result[0].values | map(.[1] | tonumber) | max' "${OUTPUT_DIR}/connector-throughput.json" 2>/dev/null || echo "N/A")
        AVG_THROUGHPUT=$(jq -r '.data.result[0].values | map(.[1] | tonumber) | add / length' "${OUTPUT_DIR}/connector-throughput.json" 2>/dev/null || echo "N/A")

        cat >> "${OUTPUT_DIR}/metrics-summary.txt" <<EOF

Connector Throughput:
  Max Rate: ${MAX_THROUGHPUT} records/sec
  Avg Rate: ${AVG_THROUGHPUT} records/sec
EOF
    fi
else
    echo "  jq not installed - skipping JSON parsing"
    cat >> "${OUTPUT_DIR}/metrics-summary.txt" <<EOF

(Install jq for detailed statistics: brew install jq)

Raw JSON files available in ${OUTPUT_DIR}/
EOF
fi

# Create a CSV for easy import to Excel
echo ""
echo "=== Creating CSV Export ==="

cat > "${OUTPUT_DIR}/metrics.csv" <<EOF
Metric,Value,Unit
Test Start,$(date -r $((START_TIME/1000))),
Test End,$(date -r $((END_TIME/1000))),
Duration,$((END_TIME/1000 - START_TIME/1000)),seconds
EOF

if command -v jq &> /dev/null; then
    [ -n "${MAX_REDO:-}" ] && echo "Max Redo Rate,${MAX_REDO},bytes/sec" >> "${OUTPUT_DIR}/metrics.csv"
    [ -n "${AVG_REDO:-}" ] && echo "Avg Redo Rate,${AVG_REDO},bytes/sec" >> "${OUTPUT_DIR}/metrics.csv"
    [ -n "${MAX_LAG:-}" ] && echo "Max Consumer Lag,${MAX_LAG},messages" >> "${OUTPUT_DIR}/metrics.csv"
    [ -n "${AVG_LAG:-}" ] && echo "Avg Consumer Lag,${AVG_LAG},messages" >> "${OUTPUT_DIR}/metrics.csv"
    [ -n "${MAX_THROUGHPUT:-}" ] && echo "Max Throughput,${MAX_THROUGHPUT},records/sec" >> "${OUTPUT_DIR}/metrics.csv"
    [ -n "${AVG_THROUGHPUT:-}" ] && echo "Avg Throughput,${AVG_THROUGHPUT},records/sec" >> "${OUTPUT_DIR}/metrics.csv"
fi

echo "  ✓ Created metrics.csv"

# Display summary
echo ""
cat "${OUTPUT_DIR}/metrics-summary.txt"

echo ""
echo "=========================================="
echo "Collection Complete!"
echo "=========================================="
echo ""
echo "Files created:"
ls -lh "${OUTPUT_DIR}/"
echo ""
echo "Summary: ${OUTPUT_DIR}/metrics-summary.txt"
echo "CSV: ${OUTPUT_DIR}/metrics.csv"
echo ""
echo "Grafana Dashboard: ${GRAFANA_URL}/d/${DASHBOARD_UID}"
echo ""
echo "To capture screenshots, open the dashboard and use:"
echo "  From: $(date -r $((START_TIME/1000)) '+%Y-%m-%d %H:%M:%S')"
echo "  To:   $(date -r $((END_TIME/1000)) '+%Y-%m-%d %H:%M:%S')"
