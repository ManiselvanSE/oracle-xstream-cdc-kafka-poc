#!/bin/bash
# Diagnose and fix missing Debezium metrics in JMX exporter
# Run this script on your Kafka Connect server

set -e

echo "=== Debezium Metrics Diagnostic and Fix Tool ==="
echo ""

# Configuration
CONNECT_HOST="${CONNECT_HOST:-localhost}"
CONNECT_REST_PORT="${CONNECT_REST_PORT:-8083}"
CONNECT_JMX_PORT="${CONNECT_JMX_PORT:-9994}"
CONNECTOR_NAME="${CONNECTOR_NAME:-oracle-xstream-rac-connector}"

echo "Configuration:"
echo "  Connect REST API: http://$CONNECT_HOST:$CONNECT_REST_PORT"
echo "  Connect JMX Exporter: http://$CONNECT_HOST:$CONNECT_JMX_PORT"
echo "  Connector Name: $CONNECTOR_NAME"
echo ""

# Step 1: Check connector status
echo "=== Step 1: Checking Connector Status ==="
CONNECTOR_STATUS=$(curl -s "http://$CONNECT_HOST:$CONNECT_REST_PORT/connectors/$CONNECTOR_NAME/status" 2>/dev/null || echo "")

if [ -z "$CONNECTOR_STATUS" ]; then
    echo "❌ ERROR: Cannot reach Kafka Connect REST API"
    echo "   Check that Connect is running: docker ps | grep connect"
    echo "   Verify port $CONNECT_REST_PORT is accessible"
    exit 1
fi

CONNECTOR_STATE=$(echo "$CONNECTOR_STATUS" | jq -r '.connector.state' 2>/dev/null || echo "UNKNOWN")
TASK_STATE=$(echo "$CONNECTOR_STATUS" | jq -r '.tasks[0].state' 2>/dev/null || echo "UNKNOWN")

echo "Connector State: $CONNECTOR_STATE"
echo "Task 0 State: $TASK_STATE"

if [ "$CONNECTOR_STATE" != "RUNNING" ] || [ "$TASK_STATE" != "RUNNING" ]; then
    echo "⚠️  WARNING: Connector or task is not RUNNING"
    echo "   Debezium metrics are only available when connector is running"
    echo ""
    echo "   To start the connector:"
    echo "   curl -X POST http://$CONNECT_HOST:$CONNECT_REST_PORT/connectors \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d @xstream-connector/oracle-xstream-rac.json"
    echo ""

    read -p "Do you want to continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo "✅ Connector is RUNNING"
fi

# Step 2: Check JMX exporter endpoint
echo ""
echo "=== Step 2: Checking JMX Exporter Endpoint ==="

JMX_METRICS=$(curl -s "http://$CONNECT_HOST:$CONNECT_JMX_PORT/metrics" 2>/dev/null || echo "")

if [ -z "$JMX_METRICS" ]; then
    echo "❌ ERROR: Cannot reach JMX exporter at http://$CONNECT_HOST:$CONNECT_JMX_PORT/metrics"
    echo "   Possible causes:"
    echo "   1. JMX exporter not configured in Kafka Connect"
    echo "   2. Port $CONNECT_JMX_PORT not exposed"
    echo "   3. JMX exporter agent not loaded"
    echo ""
    echo "   Check docker-compose.yml for:"
    echo "   environment:"
    echo "     KAFKA_OPTS: \"-javaagent:/path/to/jmx_prometheus_javaagent.jar=$CONNECT_JMX_PORT:/path/to/kafka-connect.yml\""
    exit 1
fi

echo "✅ JMX exporter is accessible"

# Step 3: Check for JVM metrics
echo ""
echo "=== Step 3: Checking Basic JVM Metrics ==="

JVM_COUNT=$(echo "$JMX_METRICS" | grep -c "^jvm_" || echo "0")
echo "Found $JVM_COUNT JVM metric types"

if [ "$JVM_COUNT" -lt 10 ]; then
    echo "⚠️  WARNING: Very few JVM metrics found"
    echo "   JMX exporter may not be working correctly"
else
    echo "✅ JVM metrics available"
fi

# Step 4: Check for Kafka Connect metrics
echo ""
echo "=== Step 4: Checking Kafka Connect Metrics ==="

CONNECT_WRITE_RATE=$(echo "$JMX_METRICS" | grep "kafka_connect_source_task_metrics_source_record_write_rate" || echo "")
CONNECT_TASK_RUNNING=$(echo "$JMX_METRICS" | grep "kafka_connect_connector_task_metrics_running_ratio" || echo "")

if [ -n "$CONNECT_WRITE_RATE" ]; then
    echo "✅ Found: kafka_connect_source_task_metrics_source_record_write_rate"
else
    echo "❌ Missing: kafka_connect_source_task_metrics_source_record_write_rate"
fi

if [ -n "$CONNECT_TASK_RUNNING" ]; then
    echo "✅ Found: kafka_connect_connector_task_metrics_running_ratio"
else
    echo "❌ Missing: kafka_connect_connector_task_metrics_running_ratio"
    echo "   This metric is needed for task health monitoring"
fi

# Step 5: Check for Debezium metrics (CRITICAL)
echo ""
echo "=== Step 5: Checking Debezium Oracle Metrics (CRITICAL) ==="

DEBEZIUM_COUNT=$(echo "$JMX_METRICS" | grep -c "^debezium_oracle_connector" || echo "0")

if [ "$DEBEZIUM_COUNT" -eq 0 ]; then
    echo "❌ PROBLEM FOUND: NO Debezium metrics available!"
    echo ""
    echo "This is why your dashboards show 'No Data'"
    echo ""
    echo "Possible causes:"
    echo "1. JMX exporter config doesn't include debezium.confluent.oracle:* pattern"
    echo "2. Connector is not running (checked above)"
    echo "3. Wrong connector type (not Confluent Oracle XStream CDC)"
    echo ""
else
    echo "✅ Found $DEBEZIUM_COUNT Debezium metric types"
    echo ""
    echo "Sample Debezium metrics:"
    echo "$JMX_METRICS" | grep "^debezium_oracle_connector" | head -5
fi

# Step 6: Check JMX config file
echo ""
echo "=== Step 6: Checking JMX Exporter Configuration ==="

# Try to find the config in the container
if command -v docker &> /dev/null; then
    echo "Checking JMX config in Docker container..."

    JMX_CONFIG=$(docker exec connect cat /opt/jmx_exporter/kafka-connect.yml 2>/dev/null || echo "")

    if [ -n "$JMX_CONFIG" ]; then
        echo "✅ Found JMX config file"

        # Check if it includes Debezium patterns
        DEBEZIUM_PATTERN=$(echo "$JMX_CONFIG" | grep -i "debezium" || echo "")

        if [ -n "$DEBEZIUM_PATTERN" ]; then
            echo "✅ Config includes Debezium patterns:"
            echo "$DEBEZIUM_PATTERN"
        else
            echo "❌ PROBLEM: Config does NOT include Debezium patterns!"
            echo ""
            echo "The JMX config should include:"
            echo "whitelistObjectNames:"
            echo "  - \"debezium.confluent.oracle:*\""
            echo ""
            echo "Fix: Update monitoring/jmx/kafka-connect.yml and restart Kafka Connect"
        fi
    else
        echo "⚠️  Cannot read JMX config from container"
        echo "   Check manually: docker exec connect cat /opt/jmx_exporter/kafka-connect.yml"
    fi
else
    echo "⚠️  Docker not available, skipping container check"
fi

# Step 7: Recommendations
echo ""
echo "=== Step 7: Recommendations ==="
echo ""

if [ "$DEBEZIUM_COUNT" -eq 0 ]; then
    echo "🔧 REQUIRED FIX: Add Debezium metrics to JMX exporter"
    echo ""
    echo "1. Verify your monitoring/jmx/kafka-connect.yml includes:"
    echo ""
    cat << 'EOF'
whitelistObjectNames:
  - "kafka.connect:*"
  - "kafka.consumer:*"
  - "kafka.producer:*"
  - "debezium.confluent.oracle:*"    # <-- This line is critical!
  - "java.lang:*"
EOF
    echo ""
    echo "2. Ensure the config is mounted in docker-compose.yml:"
    echo ""
    cat << 'EOF'
services:
  connect:
    volumes:
      - ./monitoring/jmx/kafka-connect.yml:/opt/jmx_exporter/kafka-connect.yml:ro
    environment:
      KAFKA_OPTS: "-javaagent:/opt/jmx_exporter/jmx_prometheus_javaagent.jar=9991:/opt/jmx_exporter/kafka-connect.yml"
EOF
    echo ""
    echo "3. Restart Kafka Connect:"
    echo "   docker-compose restart connect"
    echo ""
    echo "4. Wait 30 seconds and run this script again to verify"
    echo ""
else
    echo "✅ Debezium metrics are available!"
    echo ""
    echo "If dashboards still show 'No Data':"
    echo "1. Check Prometheus is scraping: http://prometheus:9090/targets"
    echo "2. Verify metric exists in Prometheus: http://prometheus:9090/graph"
    echo "   Query: debezium_oracle_connector_total_number_of_events_seen"
    echo "3. Wait for Prometheus to scrape (default: every 15 seconds)"
    echo "4. Refresh Grafana dashboards"
fi

# Step 8: Quick test queries
echo ""
echo "=== Step 8: Quick Test Queries ==="
echo ""

if [ "$DEBEZIUM_COUNT" -gt 0 ]; then
    echo "Test these queries in Grafana Explore or Prometheus:"
    echo ""
    echo "# Total events captured:"
    echo "debezium_oracle_connector_total_number_of_events_seen{job=\"kafka-connect\",context=\"streaming\"}"
    echo ""
    echo "# Streaming lag (milliseconds):"
    echo "debezium_oracle_connector_milliseconds_behind_source{job=\"kafka-connect\",context=\"streaming\"}"
    echo ""
    echo "# Connector throughput:"
    echo "kafka_connect_source_task_metrics_source_record_write_rate{job=\"kafka-connect\"}"
fi

echo ""
echo "=== Diagnostic Complete ==="
echo ""
echo "For more help, see:"
echo "  - monitoring/TROUBLESHOOTING_NO_DATA.md"
echo "  - monitoring/DIAGNOSIS_REPORT.md"
