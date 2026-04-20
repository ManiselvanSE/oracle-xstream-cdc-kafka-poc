# Quick Fix: Dashboards Showing "No Data"

## Problem

Your Grafana dashboards are showing "No Data" because **Debezium metrics are not being collected**.

## What's Working ✅

- Prometheus is running and healthy
- All scrape targets are UP (kafka-connect, kafka-broker, kafka-exporter)
- Basic JVM metrics are available (CPU, memory)
- Kafka broker metrics are available
- Basic connector metrics (poll_rate, write_rate)

## What's Missing ❌

**ALL Debezium Oracle connector metrics** - these are critical for the dashboards:
- debezium_oracle_connector_total_number_of_events_seen
- debezium_oracle_connector_milliseconds_behind_source (lag)
- debezium_oracle_connector_queue_remaining_capacity
- debezium_oracle_connector_*_events_seen (CREATE/UPDATE/DELETE)

## Root Cause

The JMX exporter on Kafka Connect is **not collecting Debezium MBean metrics**.

## Quick Fix (3 Steps)

### Step 1: Run Diagnostic Script

```bash
# SSH to your server (137.131.53.98)
cd /path/to/oracle-xstream-cdc-poc

# Run the diagnostic
chmod +x monitoring/scripts/diagnose-and-fix-jmx.sh
./monitoring/scripts/diagnose-and-fix-jmx.sh
```

This will tell you exactly what's wrong.

### Step 2: Check Connector is Running

```bash
# Check connector status
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq

# Should show:
# {
#   "connector": { "state": "RUNNING" },
#   "tasks": [{ "state": "RUNNING" }]
# }
```

**If not running**, start it:
```bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @xstream-connector/oracle-xstream-rac.json
```

### Step 3: Verify and Fix JMX Configuration

**Check your JMX config includes Debezium patterns:**

```bash
# On your server, check the JMX config
cat monitoring/jmx/kafka-connect.yml | grep -A 5 "whitelistObjectNames"
```

**Must include** this line:
```yaml
whitelistObjectNames:
  - "kafka.connect:*"
  - "kafka.consumer:*"
  - "kafka.producer:*"
  - "debezium.confluent.oracle:*"    # <-- CRITICAL!
  - "java.lang:*"
```

**If missing**, add it and restart:
```bash
# Edit the file to add debezium.confluent.oracle:*
vim monitoring/jmx/kafka-connect.yml

# Restart Kafka Connect
docker-compose restart connect

# Wait 30 seconds
sleep 30

# Verify metrics now appear
curl http://localhost:9994/metrics | grep debezium_oracle_connector
```

## Testing After Fix

### 1. Check JMX Exporter Directly

```bash
# Should return Debezium metrics
curl http://137.131.53.98:9994/metrics | grep "debezium_oracle_connector" | head -10
```

Expected output:
```
debezium_oracle_connector_total_number_of_events_seen{context="streaming",server="racdb"} 12345.0
debezium_oracle_connector_milliseconds_behind_source{context="streaming",server="racdb"} 150.0
...
```

### 2. Check in Prometheus

Open: http://137.131.53.98:9090/graph

Query:
```promql
debezium_oracle_connector_total_number_of_events_seen
```

Should return data.

### 3. Refresh Grafana Dashboards

- Open: http://137.131.53.98:3000/d/oracle-xstream-kafka-overview
- Wait 15-30 seconds for Prometheus to scrape
- Refresh the page (Ctrl+R)
- Panels should now show data

## Temporary Workaround (While Fixing)

Some panels CAN work with available metrics:

### Working Panels

**Kafka Broker Throughput** (works now):
```promql
sum(kafka_server_brokertopicmetrics_messagesin_oneminuterate{topic=~"racdb\\..*"})
```

**Connector Write Rate** (works now):
```promql
kafka_connect_source_task_metrics_source_record_write_rate
```

**JVM CPU** (works now):
```promql
jvm_os_processcpuload{job="kafka-connect"}
```

**JVM Heap** (works now):
```promql
jvm_memory_bytes_used{job="kafka-connect",area="heap"} / jvm_memory_bytes_max{job="kafka-connect",area="heap"}
```

## Expected Results After Fix

Once Debezium metrics are available:

### Oracle XStream CDC - Kafka Overview
http://137.131.53.98:3000/d/oracle-xstream-kafka-overview

✅ Oracle XStream CDC Throughput (events/sec)  
✅ Streaming Lag (milliseconds)  
✅ Event & DML rates (INSERT/UPDATE/DELETE)  
✅ Queue capacity  
✅ Committed transactions  
✅ CPU and memory (already working)  
✅ Kafka broker throughput (already working)  

### Throughput & Performance
http://137.131.53.98:3000/d/xstream-throughput-performance

✅ Current throughput  
✅ Streaming lag  
✅ End-to-end pipeline view  
✅ DML event breakdown  
✅ Transaction commit rates  

### Connector Health & Status
http://137.131.53.98:3000/d/connector-health-status

✅ Task running ratio  
✅ Queue utilization  
✅ Active records  
✅ Resource utilization  

### Oracle Database Performance
http://137.131.53.98:3000/d/oracle-db-performance

⚠️ This dashboard requires **oracle-exporter** to be deployed separately.  
See: `monitoring/DASHBOARD_SETUP_GUIDE.md` for instructions.

## Still Not Working?

### Common Issues

**1. Metrics appear in JMX endpoint but not in Prometheus**

Check Prometheus scrape config:
```bash
curl -s http://137.131.53.98:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="kafka-connect")'
```

Verify `scrapeUrl` points to correct JMX port (usually 9991 or 9994).

**2. Connector shows FAILED state**

Check logs:
```bash
docker logs connect | tail -100
```

Common issues:
- Oracle connection failed
- XStream not configured properly
- table.include.list doesn't match tables

**3. Metrics are all zero**

- Check if there's actual data flowing (run some DML on Oracle)
- Verify table.include.list matches your schema/tables
- Check Oracle XStream is capturing changes

## Detailed Documentation

For more information:
- **Complete Diagnosis**: `monitoring/DIAGNOSIS_REPORT.md`
- **Troubleshooting Guide**: `monitoring/TROUBLESHOOTING_NO_DATA.md`
- **Setup Guide**: `monitoring/DASHBOARD_SETUP_GUIDE.md`

## Summary

**The Fix**:
1. ✅ Ensure connector is RUNNING
2. ✅ Add `debezium.confluent.oracle:*` to JMX whitelist
3. ✅ Restart Kafka Connect
4. ✅ Wait 30 seconds and verify metrics appear

**Time Required**: 5-10 minutes

**Impact**: All dashboard panels (except Oracle DB Performance) will start showing data

---

**Need Help?** Run the diagnostic script first:
```bash
./monitoring/scripts/diagnose-and-fix-jmx.sh
```
