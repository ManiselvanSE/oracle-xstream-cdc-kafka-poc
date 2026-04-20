# New Grafana Dashboards - Oracle XStream CDC Monitoring

## Summary

Four comprehensive new dashboards have been created to fill the gaps in your Oracle XStream CDC monitoring setup:

1. **Oracle Database Performance** - Oracle-side metrics (XStream capture, SCN lag, redo logs)
2. **Connector Logs** - Centralized log aggregation and error tracking  
3. **Throughput & Performance** - End-to-end pipeline performance monitoring
4. **Connector Health & Status** - Task health, queue utilization, resource metrics

## What Was Missing (Before)

Your existing setup had:
- ✅ Basic connector metrics (JMX from Kafka Connect)
- ✅ Kafka broker metrics  
- ✅ Basic throughput visualization

What was **missing**:
- ❌ **Oracle database-side metrics** (XStream capture status, SCN lag, redo mining)
- ❌ **Log aggregation dashboard** (centralized error tracking, warnings)
- ❌ **Comprehensive throughput view** (end-to-end Oracle → Connector → Kafka)
- ❌ **Connector health dashboard** (consolidated task health, back-pressure, resources)

## What Was Created

### Files Created

```
monitoring/
├── grafana/dashboards/
│   ├── oracle-database-performance.json      # NEW - Oracle DB metrics
│   ├── connector-logs.json                   # NEW - Log aggregation
│   ├── throughput-performance.json           # NEW - E2E throughput
│   └── connector-health-status.json          # NEW - Health & status
│
├── oracle-exporter/                          # NEW - Oracle monitoring
│   ├── custom-queries.toml                   # Custom metrics queries
│   └── grants.sql                            # Database user grants
│
├── loki/                                     # NEW - Log aggregation
│   └── loki-config.yaml
│
├── promtail/                                 # NEW - Log shipper
│   └── promtail-config.yml
│
├── alertmanager/                             # NEW - Alert routing
│   └── alertmanager.yml
│
├── docker-compose-monitoring-additions.yml   # NEW - Additional services
├── DASHBOARD_SETUP_GUIDE.md                  # NEW - Complete setup guide
└── NEW_DASHBOARDS_SUMMARY.md                 # This file
```

## Dashboard Details

### 1. Oracle Database Performance
**File**: `grafana/dashboards/oracle-database-performance.json`  
**UID**: `oracle-db-performance`  
**URL**: http://137.131.53.98:3000/d/oracle-db-performance

**Metrics Displayed**:
- XStream capture status (ENABLED/DISABLED/ABORTED)
- Total messages captured & capture rate (msg/s)
- SCN progression (current vs applied)
- SCN lag monitoring
- Redo log mining rate (bytes/s)
- Archivelog generation rate
- Archivelog total size (disk usage)
- XStream outbound server status
- LogMiner active sessions
- Tablespace usage (Streams/UNDO)
- Oracle host metrics (CPU, memory, disk)

**Prerequisites**:
- Requires `oracledb_exporter` running with custom queries
- Oracle monitoring user with grants
- Prometheus scraping oracle-exporter endpoint (port 9161)

### 2. Connector Logs
**File**: `grafana/dashboards/connector-logs.json`  
**UID**: `connector-logs`  
**URL**: http://137.131.53.98:3000/d/connector-logs

**Features**:
- ERROR and WARN log rate graphs
- Live ERROR log stream
- Live WARN log stream
- XStream/Oracle-specific error filtering
- Oracle database error codes (ORA-*) tracking
- Connector task failure detection
- Task restart events
- Connection and network error tracking
- Filterable log viewer with regex search

**Prerequisites**:
- Requires Loki log aggregation server
- Promtail or Docker Loki logging driver configured
- Loki datasource configured in Grafana

### 3. Throughput & Performance
**File**: `grafana/dashboards/throughput-performance.json`  
**UID**: `xstream-throughput-performance`  
**URL**: http://137.131.53.98:3000/d/xstream-throughput-performance

**Key Performance Indicators**:
- Current connector throughput (records/sec)
- Current streaming lag (milliseconds)
- Current Kafka CDC throughput (msg/s)
- Queue utilization percentage

**Comprehensive Views**:
- End-to-end pipeline: Oracle Capture → Connector → Kafka Broker
- Producer byte rates (bytes/sec)
- Kafka broker CDC topic throughput
- DML event breakdown (INSERT/UPDATE/DELETE) with stacked visualization
- Transaction commit rates
- Average events per transaction
- Connector lag from source
- Producer request latency
- XStream callback duration
- LCRs received per callback
- Per-topic throughput breakdown

**Prerequisites**:
- JMX metrics from Kafka Connect (already configured)
- Optional: Oracle exporter for Oracle-side metrics

### 4. Connector Health & Status
**File**: `grafana/dashboards/connector-health-status.json`  
**UID**: `connector-health-status`  
**URL**: http://137.131.53.98:3000/d/connector-health-status

**Health Monitoring**:
- Kafka Connect status (UP/DOWN)
- Task running ratio (should be ~1.0)
- Active records (in-flight)
- Producer error rate
- Streaming queue capacity & utilization
- Back-pressure indicators (gauge visualization)

**Resource Monitoring**:
- JVM CPU usage
- Heap memory utilization (percentage & bytes)
- JVM thread count

**Performance Metrics**:
- Poll rate vs write rate
- Batch size averages
- Number of filtered events

**Operational Tools**:
- Health check runbook with thresholds
- Troubleshooting guide
- Common issues and actions

**Prerequisites**:
- JMX metrics from Kafka Connect (already configured)

## Setup Instructions

### Quick Setup (Automated)

All dashboards are already in the Grafana provisioning directory and will be automatically loaded when Grafana restarts.

### Additional Components Needed

#### 1. Oracle Database Exporter (for DB Performance Dashboard)

```bash
# 1. Create Oracle monitoring user
sqlplus system/password@RACDB @monitoring/oracle-exporter/grants.sql

# 2. Run oracledb_exporter with custom queries
export DATA_SOURCE_NAME="oracledb_exporter/password@//oracle-rac-scan:1521/RACDB"
export CUSTOM_METRICS="/path/to/monitoring/oracle-exporter/custom-queries.toml"
./oracledb_exporter --web.listen-address=:9161

# 3. Add to Prometheus config (monitoring/prometheus/prometheus.yml)
# See DASHBOARD_SETUP_GUIDE.md for details

# 4. Reload Prometheus
docker-compose restart prometheus
```

#### 2. Loki for Log Aggregation (for Connector Logs Dashboard)

```bash
# Deploy Loki and Promtail
docker-compose -f docker-compose.yml \
  -f monitoring/docker-compose-monitoring-additions.yml \
  up -d loki promtail

# Configure Kafka Connect logging (add to docker-compose.yml)
# See DASHBOARD_SETUP_GUIDE.md for full configuration
```

## Detailed Setup Guide

For complete step-by-step instructions, see:
**[monitoring/DASHBOARD_SETUP_GUIDE.md](./DASHBOARD_SETUP_GUIDE.md)**

The guide includes:
- Prerequisites and dependencies
- Oracle exporter installation and configuration
- Loki/Promtail setup
- Prometheus configuration updates
- Dashboard import instructions
- Troubleshooting steps
- Best practices and alerting

## Dashboard Access

Once set up, access your dashboards at:

| Dashboard | URL |
|-----------|-----|
| Oracle DB Performance | http://137.131.53.98:3000/d/oracle-db-performance |
| Connector Logs | http://137.131.53.98:3000/d/connector-logs |
| Throughput & Performance | http://137.131.53.98:3000/d/xstream-throughput-performance |
| Connector Health | http://137.131.53.98:3000/d/connector-health-status |
| **Existing Dashboards** | |
| Kafka Overview | http://137.131.53.98:3000/d/oracle-xstream-kafka-overview |
| Connect Cluster | http://137.131.53.98:3000/d/kafka-connect-cluster-sh |
| Oracle XStream Source | http://137.131.53.98:3000/d/oracle-xstream-cdc-source-sh |

## Key Metrics to Monitor

### Daily Checks
- [ ] Task running ratio ≥ 0.95 (Connector Health dashboard)
- [ ] Streaming lag < 5 seconds (Throughput dashboard)
- [ ] No ERROR logs in last 24h (Connector Logs dashboard)
- [ ] Queue utilization < 70% (Connector Health dashboard)
- [ ] Oracle capture status = ENABLED (DB Performance dashboard)

### Weekly Checks
- [ ] Review WARN logs for patterns (Connector Logs)
- [ ] Check archivelog disk usage (DB Performance)
- [ ] Verify SCN progression is healthy (DB Performance)
- [ ] Review throughput trends (Throughput dashboard)

## Alerting

Sample alert rules you should configure:

1. **ConnectorTaskDown**: Task running ratio < 0.9 for 5 minutes → **Critical**
2. **HighStreamingLag**: Lag > 60 seconds for 10 minutes → **Warning**
3. **XStreamCaptureDisabled**: Oracle capture disabled → **Critical**
4. **HighQueueUtilization**: Queue > 90% for 5 minutes → **Warning**
5. **HighErrorRate**: Producer errors > 0 for 5 minutes → **Warning**

Alert configuration files are provided in:
- `monitoring/prometheus/alerts/` (Prometheus rules)
- `monitoring/alertmanager/alertmanager.yml` (Alert routing)

## Troubleshooting

### No Data in Oracle DB Performance Dashboard
```bash
# Check if oracle-exporter is running and accessible
curl http://localhost:9161/metrics | grep oracle_xstream

# Verify Prometheus is scraping it
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job=="oracle-exporter")'

# Test Oracle connection
sqlplus oracledb_exporter/password@RACDB
SQL> SELECT * FROM v$streams_capture;
```

### No Logs in Connector Logs Dashboard
```bash
# Check Loki is running
curl http://localhost:3100/ready

# Query Loki for logs
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="kafka-connect"}' | jq

# Check Promtail is shipping logs
docker logs promtail
```

### Dashboard Shows "No Data"
1. Check time range (default: last 1 hour)
2. Verify datasources are configured (Prometheus, Loki)
3. Check that metrics exist in Prometheus: `curl http://localhost:9090/api/v1/query?query=up`
4. Verify the metric names match your JMX exporter output

## What's Next

1. **Complete the setup** following the DASHBOARD_SETUP_GUIDE.md
2. **Configure alerting** using AlertManager
3. **Customize dashboards** based on your specific needs
4. **Set up SLOs** (Service Level Objectives) for your CDC pipeline
5. **Document runbooks** for common operational tasks

## Benefits

With these new dashboards, you now have:

✅ **Complete visibility** into the entire CDC pipeline (Oracle → Connector → Kafka)  
✅ **Proactive monitoring** of Oracle database XStream capture health  
✅ **Centralized error tracking** with searchable log aggregation  
✅ **Performance insights** with detailed throughput breakdowns  
✅ **Early warning system** for task failures and resource issues  
✅ **Operational efficiency** with consolidated health monitoring  
✅ **Best practice alignment** following Confluent and Oracle recommendations

## Support & Documentation

- **Setup Guide**: [DASHBOARD_SETUP_GUIDE.md](./DASHBOARD_SETUP_GUIDE.md)
- **Existing Monitoring**: [README.md](./README.md)
- **Confluent Docs**: https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/connector-monitoring-metrics.html
- **Oracle XStream**: https://docs.oracle.com/en/database/oracle/oracle-database/19/xstrm/
- **Grafana**: https://grafana.com/docs/grafana/latest/dashboards/

---

**Created**: 2026-04-02  
**Purpose**: Oracle XStream CDC POC - Complete monitoring solution for 24-table CDC pipeline  
**Status**: Ready for deployment (requires oracle-exporter and Loki setup)
