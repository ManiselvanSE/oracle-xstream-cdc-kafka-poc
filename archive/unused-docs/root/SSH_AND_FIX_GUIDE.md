# SSH to Server and Fix Dashboard Issues

## Step 1: SSH to Your Server

Run this command from your Mac:

```bash
ssh -i /Users/maniselvank/Desktop/Mani/ssh-key-2026-03-12.key opc@129.146.31.189
```

## Step 2: Copy the Diagnostic Script to Server

Once connected, run these commands:

```bash
# Create a temporary script
cat > /tmp/diagnostic.sh << 'EOF'
#!/bin/bash
# Quick diagnostic - paste this entire script

echo "=== Quick Diagnostic ==="

# Find project directory
for dir in /home/opc/oracle-xstream-cdc-poc /opt/oracle-xstream-cdc-poc ~/oracle-xstream-cdc-poc; do
    if [ -d "$dir" ]; then
        cd "$dir" 2>/dev/null && break
    fi
done

echo "Working directory: $(pwd)"
echo ""

# Check containers
echo "Docker containers:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAME|connect|kafka|prometheus"
echo ""

# Check connector
echo "Connector status:"
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status 2>/dev/null | jq -r '{state: .connector.state, task: .tasks[0].state}' 2>/dev/null || echo "Not accessible"
echo ""

# Check JMX metrics
echo "JMX exporter test:"
DEBEZIUM_COUNT=$(curl -s http://localhost:9994/metrics 2>/dev/null | grep -c "^debezium_oracle_connector" || echo "0")
echo "Debezium metrics found: $DEBEZIUM_COUNT"

if [ "$DEBEZIUM_COUNT" -eq 0 ]; then
    echo "❌ NO Debezium metrics - this is the problem!"
    echo ""
    echo "Checking JMX config..."
    if [ -f "monitoring/jmx/kafka-connect.yml" ]; then
        if grep -q "debezium.confluent.oracle" monitoring/jmx/kafka-connect.yml; then
            echo "✅ Config has Debezium pattern (may need restart)"
        else
            echo "❌ Config MISSING Debezium pattern - needs to be added"
        fi
    fi
else
    echo "✅ Debezium metrics available!"
    curl -s http://localhost:9994/metrics 2>/dev/null | grep "^debezium_oracle_connector" | head -3
fi

echo ""
echo "=== What to do next ==="
if [ "$DEBEZIUM_COUNT" -eq 0 ]; then
    echo "1. Check if monitoring/jmx/kafka-connect.yml exists"
    echo "2. Edit it to include: debezium.confluent.oracle:*"
    echo "3. Restart: docker-compose restart connect"
fi
EOF

chmod +x /tmp/diagnostic.sh
/tmp/diagnostic.sh
```

## Step 3: Based on the Output

### If you see "❌ NO Debezium metrics"

**Option A: Edit the JMX config file**

```bash
# Find and navigate to project directory
cd /home/opc/oracle-xstream-cdc-poc  # or wherever your project is

# Edit the JMX config
vi monitoring/jmx/kafka-connect.yml

# Add this line under whitelistObjectNames (use 'i' to insert, 'ESC :wq' to save):
#   - "debezium.confluent.oracle:*"

# Restart Kafka Connect
docker-compose restart connect

# Wait 30 seconds
sleep 30

# Test if it worked
curl http://localhost:9994/metrics | grep debezium_oracle_connector | head -5
```

**Option B: Quick fix with sed (automated)**

```bash
cd /home/opc/oracle-xstream-cdc-poc

# Backup the original
cp monitoring/jmx/kafka-connect.yml monitoring/jmx/kafka-connect.yml.backup

# Add the Debezium pattern if not already there
if ! grep -q "debezium.confluent.oracle" monitoring/jmx/kafka-connect.yml; then
    sed -i '/whitelistObjectNames:/a\  - "debezium.confluent.oracle:*"' monitoring/jmx/kafka-connect.yml
    echo "✅ Added Debezium pattern to JMX config"
else
    echo "Pattern already exists"
fi

# Show what changed
echo "New config:"
grep -A 10 "whitelistObjectNames:" monitoring/jmx/kafka-connect.yml

# Restart Connect
docker-compose restart connect

# Wait for restart
echo "Waiting 30 seconds for Connect to restart..."
sleep 30

# Verify
echo "Testing metrics..."
curl http://localhost:9994/metrics | grep debezium_oracle_connector | head -5
```

### If you see "✅ Debezium metrics available!"

Great! The metrics are being collected. The issue might be with Prometheus scraping.

```bash
# From your server, check if Prometheus can reach the metrics
curl http://localhost:9994/metrics | grep debezium_oracle_connector_total_number_of_events_seen
```

Then from your **local machine**, test Prometheus:

```bash
# From your Mac
curl -s "http://137.131.53.98:9090/api/v1/query?query=debezium_oracle_connector_total_number_of_events_seen" | jq
```

## Step 4: Verify the Fix

**On the server:**

```bash
# Should return Debezium metrics
curl http://localhost:9994/metrics | grep debezium_oracle_connector | head -10

# Check specific metrics
curl http://localhost:9994/metrics | grep -E "debezium_oracle_connector_(total_number_of_events_seen|milliseconds_behind_source)"
```

**From your local machine:**

```bash
# Check Prometheus has the data
curl -s "http://137.131.53.98:9090/api/v1/query?query=debezium_oracle_connector_total_number_of_events_seen" | jq '.data.result'

# Should show non-empty result array
```

**In Grafana:**

1. Open: http://137.131.53.98:3000/d/oracle-xstream-kafka-overview
2. Wait 15-30 seconds for Prometheus to scrape
3. Refresh the page (Ctrl+R or F5)
4. Panels should now show data!

## Step 5: If Still Not Working

**Check the actual JMX config in the container:**

```bash
# On the server
docker exec connect cat /opt/jmx_exporter/kafka-connect.yml | grep -A 10 "whitelistObjectNames"
```

**Check Docker Compose configuration:**

```bash
# Verify JMX agent is configured
docker inspect connect | grep -A 5 KAFKA_OPTS

# Or check docker-compose file
grep -A 30 "^  connect:" docker-compose.yml | grep -B 2 -A 2 javaagent
```

**View Connect logs for errors:**

```bash
docker logs connect --tail 100 | grep -E "ERROR|WARN"
```

## Common Issues

### Issue: Config file not mounted

Check volumes in docker-compose.yml:

```bash
docker inspect connect | grep -A 20 Mounts | grep kafka-connect.yml
```

Should show the config file is mounted.

### Issue: Connector not running

```bash
# Check status
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq

# If FAILED, restart it
curl -X POST http://localhost:8083/connectors/oracle-xstream-rac-connector/restart
```

### Issue: Wrong connector name

```bash
# List all connectors
curl -s http://localhost:8083/connectors | jq

# If your connector has a different name, update CONNECTOR_NAME in the fix commands
```

## Complete Fix Example

Here's a complete sequence that should work:

```bash
# SSH to server
ssh -i /Users/maniselvank/Desktop/Mani/ssh-key-2026-03-12.key opc@129.146.31.189

# Navigate to project
cd /home/opc/oracle-xstream-cdc-poc  # adjust path if needed

# Check current JMX config
cat monitoring/jmx/kafka-connect.yml | grep -A 10 "whitelistObjectNames"

# If debezium.confluent.oracle:* is missing, add it
# Edit manually or use sed:
sed -i '/whitelistObjectNames:/a\  - "debezium.confluent.oracle:*"' monitoring/jmx/kafka-connect.yml

# Verify it was added
cat monitoring/jmx/kafka-connect.yml | grep -A 10 "whitelistObjectNames"

# Restart Kafka Connect
docker-compose restart connect

# Wait for restart (check logs)
docker logs -f connect
# Press Ctrl+C when you see "Kafka Connect started"

# Test metrics (should see Debezium metrics)
curl http://localhost:9994/metrics | grep debezium_oracle_connector | wc -l
# Should show a number > 0

# Exit SSH
exit
```

Then from your Mac:

```bash
# Verify Prometheus has the data
curl -s "http://137.131.53.98:9090/api/v1/query?query=debezium_oracle_connector_total_number_of_events_seen" | jq '.data.result | length'

# Should return > 0

# Refresh Grafana
open http://137.131.53.98:3000/d/oracle-xstream-kafka-overview
```

## Need More Help?

After running the diagnostic, paste the output here and I can give you specific commands to fix your issue.

Key files to check:
- `monitoring/jmx/kafka-connect.yml` - JMX exporter config
- `docker-compose.yml` - Docker configuration
- `docker logs connect` - Container logs

---

**Quick Summary:**
1. SSH to server
2. Run diagnostic script
3. Add `debezium.confluent.oracle:*` to JMX config if missing
4. Restart Connect: `docker-compose restart connect`
5. Verify: `curl localhost:9994/metrics | grep debezium`
6. Refresh Grafana dashboards
