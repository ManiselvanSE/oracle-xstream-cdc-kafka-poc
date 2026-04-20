#!/bin/bash
# Remote Server Diagnostic Script
# Run this on your Kafka Connect server (129.146.31.189)

set -e

echo "======================================================================"
echo "  Oracle XStream CDC - Remote Diagnostic"
echo "======================================================================"
echo ""

# Step 1: Find the project directory
echo "=== Step 1: Locating Project Directory ==="
POSSIBLE_DIRS=(
    "/home/opc/oracle-xstream-cdc-poc"
    "/opt/oracle-xstream-cdc-poc"
    "$HOME/oracle-xstream-cdc-poc"
    "$(pwd)"
)

PROJECT_DIR=""
for dir in "${POSSIBLE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker/docker-compose.yml" ]; then
            PROJECT_DIR="$dir"
            echo "✅ Found project at: $PROJECT_DIR"
            break
        fi
    fi
done

if [ -z "$PROJECT_DIR" ]; then
    echo "❌ Could not find project directory"
    echo "Please run this script from the project root, or set PROJECT_DIR manually:"
    echo "export PROJECT_DIR=/path/to/oracle-xstream-cdc-poc"
    exit 1
fi

cd "$PROJECT_DIR"
echo "Working directory: $(pwd)"
echo ""

# Step 2: Check Docker containers
echo "=== Step 2: Checking Docker Containers ==="
echo ""
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAME|connect|kafka|prometheus" || echo "No containers found"
echo ""

# Step 3: Check connector status
echo "=== Step 3: Checking Connector Status ==="
CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status 2>/dev/null || echo "")

if [ -n "$CONNECTOR_STATUS" ]; then
    echo "Connector Name: oracle-xstream-rac-connector"
    echo "Connector State: $(echo "$CONNECTOR_STATUS" | jq -r '.connector.state' 2>/dev/null || echo 'UNKNOWN')"
    echo "Task States:"
    echo "$CONNECTOR_STATUS" | jq -r '.tasks[] | "  Task \(.id): \(.state)"' 2>/dev/null || echo "  Could not parse tasks"

    CONNECTOR_STATE=$(echo "$CONNECTOR_STATUS" | jq -r '.connector.state' 2>/dev/null)
    if [ "$CONNECTOR_STATE" = "RUNNING" ]; then
        echo "✅ Connector is RUNNING"
    else
        echo "⚠️  Connector state: $CONNECTOR_STATE"
    fi
else
    echo "❌ Could not reach Kafka Connect REST API at localhost:8083"
    echo "   or connector 'oracle-xstream-rac-connector' not found"
fi
echo ""

# Step 4: Check JMX exporter endpoint
echo "=== Step 4: Checking JMX Exporter ==="
JMX_TEST=$(curl -s http://localhost:9994/metrics 2>/dev/null | head -5)

if [ -n "$JMX_TEST" ]; then
    echo "✅ JMX exporter accessible at localhost:9994"
    echo ""

    # Count metric types
    JVM_COUNT=$(curl -s http://localhost:9994/metrics 2>/dev/null | grep -c "^jvm_" || echo "0")
    KAFKA_CONNECT_COUNT=$(curl -s http://localhost:9994/metrics 2>/dev/null | grep -c "^kafka_connect_" || echo "0")
    DEBEZIUM_COUNT=$(curl -s http://localhost:9994/metrics 2>/dev/null | grep -c "^debezium_oracle_connector" || echo "0")

    echo "Metric counts:"
    echo "  JVM metrics: $JVM_COUNT types"
    echo "  Kafka Connect metrics: $KAFKA_CONNECT_COUNT types"
    echo "  Debezium metrics: $DEBEZIUM_COUNT types"
    echo ""

    if [ "$DEBEZIUM_COUNT" -eq 0 ]; then
        echo "❌ CRITICAL: NO Debezium metrics found!"
        echo "   This is why dashboards show 'No Data'"
    else
        echo "✅ Debezium metrics are available"
        echo ""
        echo "Sample Debezium metrics:"
        curl -s http://localhost:9994/metrics 2>/dev/null | grep "^debezium_oracle_connector" | head -5
    fi
else
    echo "❌ JMX exporter not accessible at localhost:9994"
fi
echo ""

# Step 5: Check JMX configuration
echo "=== Step 5: Checking JMX Configuration ==="

# Check if config file exists
if [ -f "monitoring/jmx/kafka-connect.yml" ]; then
    echo "✅ Found JMX config: monitoring/jmx/kafka-connect.yml"
    echo ""

    echo "Checking whitelistObjectNames:"
    grep -A 10 "whitelistObjectNames:" monitoring/jmx/kafka-connect.yml | head -12
    echo ""

    # Check for Debezium pattern
    if grep -q "debezium.confluent.oracle" monitoring/jmx/kafka-connect.yml; then
        echo "✅ Config includes: debezium.confluent.oracle:*"
    else
        echo "❌ Config MISSING: debezium.confluent.oracle:*"
        echo ""
        echo "THIS IS THE PROBLEM!"
        echo ""
        echo "Fix: Add this line to whitelistObjectNames in monitoring/jmx/kafka-connect.yml:"
        echo '  - "debezium.confluent.oracle:*"'
    fi
else
    echo "⚠️  JMX config not found at monitoring/jmx/kafka-connect.yml"
fi
echo ""

# Step 6: Check if config is mounted in container
echo "=== Step 6: Checking Container JMX Config ==="

CONTAINER_CONFIG=$(docker exec connect cat /opt/jmx_exporter/kafka-connect.yml 2>/dev/null || echo "")

if [ -n "$CONTAINER_CONFIG" ]; then
    echo "✅ JMX config is mounted in container"

    if echo "$CONTAINER_CONFIG" | grep -q "debezium.confluent.oracle"; then
        echo "✅ Container config includes Debezium patterns"
    else
        echo "❌ Container config MISSING Debezium patterns"
        echo ""
        echo "The config on disk may be correct, but the container is using an old version"
        echo "Solution: Restart Kafka Connect to reload the config"
    fi
else
    echo "❌ Cannot read JMX config from container"
fi
echo ""

# Step 7: Check docker-compose configuration
echo "=== Step 7: Checking Docker Compose Configuration ==="

COMPOSE_FILE="docker-compose.yml"
if [ -f "docker/docker-compose.yml" ]; then
    COMPOSE_FILE="docker/docker-compose.yml"
fi

if [ -f "$COMPOSE_FILE" ]; then
    echo "Found compose file: $COMPOSE_FILE"

    # Check for JMX agent configuration
    if grep -A 20 "^  connect:" "$COMPOSE_FILE" | grep -q "javaagent.*jmx_prometheus_javaagent"; then
        echo "✅ JMX agent configured in docker-compose"

        # Show the actual config
        echo ""
        echo "JMX configuration:"
        grep -A 20 "^  connect:" "$COMPOSE_FILE" | grep -B 2 -A 2 "javaagent.*jmx_prometheus_javaagent"
    else
        echo "⚠️  JMX agent may not be configured in docker-compose"
    fi

    # Check for volume mount
    if grep -A 30 "^  connect:" "$COMPOSE_FILE" | grep -q "kafka-connect.yml"; then
        echo "✅ JMX config file is mounted"
    else
        echo "⚠️  JMX config file may not be mounted"
    fi
else
    echo "⚠️  Could not find docker-compose.yml"
fi
echo ""

# Step 8: Summary and recommendations
echo "======================================================================"
echo "  SUMMARY AND RECOMMENDATIONS"
echo "======================================================================"
echo ""

if [ "$DEBEZIUM_COUNT" -eq 0 ]; then
    echo "❌ PROBLEM: Debezium metrics are NOT being collected"
    echo ""
    echo "This is why your Grafana dashboards show 'No Data'"
    echo ""
    echo "🔧 FIX STEPS:"
    echo ""
    echo "1. Edit the JMX config file:"
    echo "   vi monitoring/jmx/kafka-connect.yml"
    echo ""
    echo "2. Add this line under whitelistObjectNames:"
    echo '   - "debezium.confluent.oracle:*"'
    echo ""
    echo "3. Restart Kafka Connect:"
    echo "   docker-compose restart connect"
    echo ""
    echo "4. Wait 30 seconds and verify:"
    echo "   curl http://localhost:9994/metrics | grep debezium_oracle_connector | head -5"
    echo ""
    echo "5. Check Prometheus (from your local machine):"
    echo "   curl http://137.131.53.98:9090/api/v1/query?query=debezium_oracle_connector_total_number_of_events_seen"
    echo ""
else
    echo "✅ Debezium metrics are being collected!"
    echo ""
    echo "Metrics available: $DEBEZIUM_COUNT types"
    echo ""
    echo "If Grafana still shows 'No Data':"
    echo "1. Check Prometheus targets: http://137.131.53.98:9090/targets"
    echo "2. Verify Prometheus can scrape Connect: Should show 'kafka-connect' job as UP"
    echo "3. Test query in Prometheus: debezium_oracle_connector_total_number_of_events_seen"
    echo "4. Wait 15-30 seconds for Prometheus to scrape"
    echo "5. Refresh Grafana dashboards"
fi

echo ""
echo "======================================================================"
echo "  QUICK VERIFICATION COMMANDS"
echo "======================================================================"
echo ""
echo "# Test JMX endpoint directly:"
echo "curl http://localhost:9994/metrics | grep debezium_oracle_connector | head -10"
echo ""
echo "# Check connector status:"
echo "curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq"
echo ""
echo "# View Connect logs:"
echo "docker logs connect --tail 100"
echo ""
echo "# Restart Connect (if you made config changes):"
echo "docker-compose restart connect"
echo ""

echo "======================================================================"
echo "Diagnostic complete!"
echo "======================================================================"
