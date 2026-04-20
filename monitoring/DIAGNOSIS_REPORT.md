# Dashboard "No Data" - Diagnostic Report

**Date**: 2026-04-02  
**Environment**: http://137.131.53.98:3000

## Summary

**Problem**: Most dashboard panels showing "No Data"  
**Root Cause**: Debezium and extended Kafka Connect metrics are NOT being collected by JMX exporter

## What's Working ✅

1. **Prometheus**: Healthy and scraping all targets
2. **All Targets UP**:
   - ✅ kafka-broker (kafka1, kafka2, kafka3) - UP
   - ✅ kafka-connect (connect:9991) - UP
   - ✅ kafka-exporter - UP
   - ✅ prometheus - UP

3. **JVM Metrics**: Available
   - ✅ jvm_os_processcpuload
   - ✅ jvm_memory_bytes_used{area="heap"}
   - ✅ jvm_memory_bytes_max{area="heap"}
   - ✅ jvm_threads_count

4. **Basic Kafka Connect Metrics**: Available (but limited)
   - ✅ kafka_connect_source_task_metrics_source_record_poll_rate
   - ✅ kafka_connect_source_task_metrics_source_record_write_rate

5. **Kafka Broker Metrics**: Available
   - ✅ kafka_server_brokertopicmetrics_messagesin_total
   - ✅ kafka_server_brokertopicmetrics_messagesin_oneminuterate
   - ✅ Topic-level metrics for racdb.* topics

## What's Missing ❌

### Critical Missing Metrics

**Debezium Oracle Connector Metrics** (ALL MISSING):
- ❌ debezium_oracle_connector_total_number_of_events_seen
- ❌ debezium_oracle_connector_milliseconds_behind_source
- ❌ debezium_oracle_connector_queue_remaining_capacity
- ❌ debezium_oracle_connector_total_number_of_create_events_seen
- ❌ debezium_oracle_connector_total_number_of_update_events_seen
- ❌ debezium_oracle_connector_total_number_of_delete_events_seen
- ❌ debezium_oracle_connector_number_of_committed_transactions

**Extended Kafka Connect Metrics** (MISSING):
- ❌ kafka_connect_connector_task_metrics_running_ratio
- ❌ kafka_connect_source_task_metrics_source_record_active_count
- ❌ kafka_connect_source_task_metrics_batch_size_avg

**Oracle Exporter Metrics** (EXPECTED - not set up yet):
- ❌ oracle_xstream_capture_* (expected, oracle-exporter not deployed)

## Impact on Dashboards

### Oracle XStream CDC - Kafka Overview
**URL**: http://137.131.53.98:3000/d/oracle-xstream-kafka-overview

| Panel | Status | Reason |
|-------|--------|--------|
| Oracle XStream CDC Throughput | ❌ No Data | Missing debezium metrics |
| Connector Throughput | ⚠️ Partial | Only has write_rate, missing other metrics |
| CPU Usage | ✅ Working | JVM metrics available |
| JVM Heap Memory | ✅ Working | JVM metrics available |
| Targets Up | ✅ Working | Prometheus targets available |
| Consumer Group Lag | ⚠️ May work | Kafka Exporter metrics available |
| Kafka Throughput | ✅ Working | Broker metrics available |
| Lag - streaming | ❌ No Data | Missing debezium_oracle_connector_milliseconds_behind_source |
| Event & DML rates | ❌ No Data | Missing debezium CREATE/UPDATE/DELETE metrics |
| Queue capacity | ❌ No Data | Missing debezium queue metrics |

### Oracle Database Performance
**URL**: http://137.131.53.98:3000/d/oracle-db-performance

| Panel | Status | Reason |
|-------|--------|--------|
| ALL Oracle Panels | ❌ No Data | oracle-exporter not deployed (EXPECTED) |

### Connector Health & Status
**URL**: http://137.131.53.98:3000/d/connector-health-status

| Panel | Status | Reason |
|-------|--------|--------|
| Task Running Ratio | ❌ No Data | Missing kafka_connect_connector_task_metrics_running_ratio |
| Active Records | ❌ No Data | Missing kafka_connect_source_task_metrics_source_record_active_count |
| CPU/Heap Metrics | ✅ Working | JVM metrics available |
| Queue Utilization | ❌ No Data | Missing debezium queue metrics |

### Throughput & Performance
**URL**: http://137.131.53.98:3000/d/xstream-throughput-performance

| Panel | Status | Reason |
|-------|--------|--------|
| Current Throughput | ⚠️ Partial | Has write_rate, missing others |
| Streaming Lag | ❌ No Data | Missing debezium lag metrics |
| Pipeline Throughput | ⚠️ Partial | Missing debezium event metrics |
| DML Breakdown | ❌ No Data | Missing CREATE/UPDATE/DELETE metrics |

## Root Cause Analysis

The JMX exporter on Kafka Connect is:
1. ✅ **Running** (we see it scraping at connect:9991)
2. ✅ **Collecting basic Java metrics** (JVM metrics present)
3. ✅ **Collecting some Kafka Connect metrics** (poll_rate, write_rate)
4. ❌ **NOT collecting Debezium metrics** (debezium.confluent.oracle MBeans)
5. ❌ **NOT collecting extended Connect metrics** (task running ratio, active count, etc.)

**Likely Causes**:
1. JMX exporter config file (`kafka-connect.yml`) may not be mounted correctly
2. Debezium MBeans might not be registered (connector not running or using different version)
3. JMX whitelist patterns might not match the actual MBean names

## Fix Steps

### Step 1: Verify Connector is Running

```bash
# SSH to your server and run:
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq

# Expected output:
# {
#   "name": "oracle-xstream-rac-connector",
#   "connector": { "state": "RUNNING" },
#   "tasks": [{ "id": 0, "state": "RUNNING" }]
# }
```

If connector is NOT running, start it:
```bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @xstream-connector/oracle-xstream-rac.json
```

### Step 2: Check JMX Exporter Configuration

```bash
# SSH to your server

# Check if JMX config is mounted in container
docker exec connect ls -la /opt/jmx_exporter/

# Should show:
# kafka-connect.yml

# Check the actual config being used
docker exec connect cat /opt/jmx_exporter/kafka-connect.yml | grep -A 2 "whitelistObjectNames"

# Should include:
#   - "debezium.confluent.oracle:*"
```

### Step 3: Check Available MBeans in Connector

```bash
# Install jmxterm or use JConsole to connect to connect:9991
# Or check logs for MBean registration

docker logs connect 2>&1 | grep -i "mbean\|debezium" | tail -20
```

### Step 4: Verify JMX Metrics at Source

```bash
# Direct query to JMX exporter endpoint
curl -s http://137.131.53.98:9994/metrics | grep debezium

# If this returns nothing, the JMX exporter isn't seeing the Debezium MBeans
# If this returns data, then Prometheus isn't scraping it correctly
```

### Step 5: Check Prometheus Scrape Config

```bash
# Verify Prometheus is configured to scrape Connect JMX
curl -s http://137.131.53.98:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="kafka-connect")'

# Verify the scrape URL and labels
```

## Immediate Workaround

For dashboards that CAN work with available metrics, use these queries:

### Working Metrics

**Throughput** (use Kafka broker metrics instead):
```promql
# Total CDC throughput from broker side
sum(rate(kafka_server_brokertopicmetrics_messagesin_total{topic=~"racdb\\..*"}[5m]))

# Or use the OneMinuteRate gauge
sum(kafka_server_brokertopicmetrics_messagesin_oneminuterate{topic=~"racdb\\..*"})
```

**Connector Write Rate** (this works):
```promql
kafka_connect_source_task_metrics_source_record_write_rate{job="kafka-connect"}
```

**CPU and Memory** (working):
```promql
# CPU
jvm_os_processcpuload{job="kafka-connect"}

# Heap
jvm_memory_bytes_used{job="kafka-connect",area="heap"} / jvm_memory_bytes_max{job="kafka-connect",area="heap"}
```

## Next Actions

**Priority 1 - Critical** (Get Debezium metrics):
1. ✅ Verify connector is RUNNING
2. ✅ Check JMX config includes debezium.confluent.oracle patterns
3. ✅ Restart Kafka Connect if JMX config was updated
4. ✅ Verify metrics appear at JMX endpoint

**Priority 2 - Oracle DB Metrics** (Optional):
1. Deploy oracle-exporter (see DASHBOARD_SETUP_GUIDE.md)
2. Add to Prometheus scrape config
3. Verify oracle metrics appear

**Priority 3 - Logs** (Optional):
1. Deploy Loki + Promtail
2. Add Loki datasource to Grafana

## Testing After Fix

```bash
# 1. Check JMX endpoint has Debezium metrics
curl -s http://137.131.53.98:9994/metrics | grep "debezium_oracle_connector" | head -10

# 2. Wait 30 seconds for Prometheus to scrape

# 3. Query Prometheus
curl -s "http://137.131.53.98:9090/api/v1/query?query=debezium_oracle_connector_total_number_of_events_seen" | jq

# 4. Refresh Grafana dashboards
```

## Dashboard-Specific Fixes

Once Debezium metrics are available, these dashboards will automatically populate:

- ✅ **Oracle XStream CDC - Kafka Overview**: Will show lag, events, throughput
- ✅ **Throughput & Performance**: Will show full pipeline metrics
- ✅ **Connector Health & Status**: Will show queue, task health

For **Oracle Database Performance** dashboard, oracle-exporter deployment is required separately.

---

**Generated**: 2026-04-02  
**Next Step**: Verify connector status and JMX configuration
