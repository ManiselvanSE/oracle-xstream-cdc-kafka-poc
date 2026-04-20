#!/bin/bash
# Check which metrics are available in Prometheus for dashboard troubleshooting

set -e

PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
JMX_CONNECT_URL="${JMX_CONNECT_URL:-http://localhost:9994}"

echo "=== Prometheus Metrics Check ==="
echo "Prometheus URL: $PROMETHEUS_URL"
echo ""

echo "1. Checking Prometheus availability..."
if curl -s "$PROMETHEUS_URL/-/healthy" > /dev/null 2>&1; then
    echo "✓ Prometheus is healthy"
else
    echo "✗ Prometheus is not accessible at $PROMETHEUS_URL"
    echo "  Try: export PROMETHEUS_URL=http://<your-host>:9090"
    exit 1
fi

echo ""
echo "2. Checking JMX exporter metrics from Kafka Connect..."
if curl -s "$JMX_CONNECT_URL/metrics" > /dev/null 2>&1; then
    echo "✓ JMX exporter accessible"
    echo ""
    echo "Available JVM metrics:"
    curl -s "$JMX_CONNECT_URL/metrics" | grep "^jvm_" | cut -d'{' -f1 | sort -u
    echo ""
    echo "Available Kafka Connect metrics:"
    curl -s "$JMX_CONNECT_URL/metrics" | grep "^kafka_connect_" | cut -d'{' -f1 | sort -u | head -20
    echo ""
    echo "Available Debezium metrics:"
    curl -s "$JMX_CONNECT_URL/metrics" | grep "^debezium_" | cut -d'{' -f1 | sort -u | head -20
else
    echo "✗ JMX exporter not accessible at $JMX_CONNECT_URL"
    echo "  Try: export JMX_CONNECT_URL=http://<your-host>:9994"
fi

echo ""
echo "3. Querying Prometheus for available metric names..."
METRICS=$(curl -s "$PROMETHEUS_URL/api/v1/label/__name__/values" | jq -r '.data[]' 2>/dev/null || echo "")

if [ -n "$METRICS" ]; then
    echo ""
    echo "JVM metrics in Prometheus:"
    echo "$METRICS" | grep "^jvm_" | sort
    echo ""
    echo "Kafka Connect metrics in Prometheus:"
    echo "$METRICS" | grep "^kafka_connect_" | sort | head -20
    echo ""
    echo "Debezium metrics in Prometheus:"
    echo "$METRICS" | grep "^debezium_" | sort | head -20
    echo ""
    echo "Oracle exporter metrics in Prometheus:"
    echo "$METRICS" | grep "^oracle_" | sort
else
    echo "✗ Could not query Prometheus API"
fi

echo ""
echo "4. Testing specific metric queries..."
echo ""

# Heap: dashboards use standard JVM metrics (exporter emits these on Kafka/Connect)
echo -n "Testing jvm_memory_bytes_used (heap): "
RESULT=$(curl -sG "$PROMETHEUS_URL/api/v1/query" --data-urlencode 'query=jvm_memory_bytes_used{area="heap"}' | jq -r '.data.result | length' 2>/dev/null || echo "0")
if [ "$RESULT" -gt 0 ]; then
    echo "✓ Found $RESULT series (dashboards use this)"
else
    echo "✗ No data"
    echo -n "  Optional custom JMX rule jvm_memory_heap_used: "
    RESULT2=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=jvm_memory_heap_used" | jq -r '.data.result | length' 2>/dev/null || echo "0")
    if [ "$RESULT2" -gt 0 ]; then
        echo "✓ Found $RESULT2 series"
    else
        echo "✗ No data"
    fi
fi

# CPU: lowercaseOutputName on JMX rules → jvm_os_processcpuload
echo -n "Testing jvm_os_processcpuload: "
RESULT=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=jvm_os_processcpuload" | jq -r '.data.result | length' 2>/dev/null || echo "0")
if [ "$RESULT" -gt 0 ]; then
    echo "✓ Found $RESULT series (dashboards use this)"
else
    echo "✗ No data"
fi

# Test Connector task metrics
echo -n "Testing kafka_connect_connector_task_metrics_running_ratio: "
RESULT=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=kafka_connect_connector_task_metrics_running_ratio" | jq -r '.data.result | length' 2>/dev/null || echo "0")
if [ "$RESULT" -gt 0 ]; then
    echo "✓ Found $RESULT series"
else
    echo "✗ No data - Check if connector is running"
fi

# Test Debezium metrics
echo -n "Testing debezium_oracle_connector_total_number_of_events_seen: "
RESULT=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=debezium_oracle_connector_total_number_of_events_seen" | jq -r '.data.result | length' 2>/dev/null || echo "0")
if [ "$RESULT" -gt 0 ]; then
    echo "✓ Found $RESULT series"
else
    echo "✗ No data - Check if connector is running and JMX config includes debezium.confluent.oracle"
fi

echo ""
echo "=== Summary ==="
echo "If metrics show '✗ No data':"
echo "1. Check that services are running: docker ps"
echo "2. Verify JMX exporter ports are exposed: docker port connect"
echo "3. Check Prometheus targets: $PROMETHEUS_URL/targets"
echo "4. Verify connector is running: curl http://localhost:8083/connectors/oracle-xstream-rac-connector/status"
echo "5. Check JMX config includes required MBeans: monitoring/jmx/kafka-connect.yml"
