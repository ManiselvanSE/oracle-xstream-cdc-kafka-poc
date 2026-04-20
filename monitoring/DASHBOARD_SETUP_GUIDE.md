# Oracle XStream CDC - Grafana Dashboard Setup Guide

This guide explains how to set up the complete monitoring stack for your Oracle XStream CDC pipeline with the newly created dashboards.

## Overview

Four new comprehensive dashboards have been created to monitor your Oracle XStream CDC connector:

1. **Oracle Database Performance** - Oracle-side metrics (XStream, redo logs, SCN)
2. **Connector Logs** - Log aggregation and error tracking
3. **Throughput & Performance** - End-to-end pipeline performance
4. **Connector Health & Status** - Task health, queue, resource utilization

## Dashboard Files

```
monitoring/grafana/dashboards/
├── oracle-database-performance.json      # NEW - Oracle DB metrics
├── connector-logs.json                   # NEW - Log aggregation
├── throughput-performance.json           # NEW - Comprehensive throughput
├── connector-health-status.json          # NEW - Health & status
├── oracle-xstream-cdc-source-selfhosted.json  # EXISTING
├── connect-cluster-metrics.json          # EXISTING
└── kafka-overview.json                   # EXISTING
```

## Prerequisites

### 1. Existing Components (Already Set Up)
- ✅ Prometheus
- ✅ Grafana
- ✅ JMX Exporter on Kafka Connect
- ✅ Kafka Exporter

### 2. New Components Required

#### A. Oracle Database Exporter (for DB Performance Dashboard)

**Install oracledb_exporter:**
```bash
# Download from https://github.com/iamseth/oracledb_exporter
wget https://github.com/iamseth/oracledb_exporter/releases/download/v0.5.0/oracledb_exporter-0.5.0.linux-amd64.tar.gz
tar -xzf oracledb_exporter-0.5.0.linux-amd64.tar.gz
```

**Configure Oracle user and grants:**
```bash
# Run the grants SQL on your Oracle database
sqlplus system/password@your_database @monitoring/oracle-exporter/grants.sql
```

**Set up custom metrics:**
```bash
export DATA_SOURCE_NAME=oracledb_exporter/your_password@//oracle-host:1521/RACDB
export CUSTOM_METRICS=/path/to/monitoring/oracle-exporter/custom-queries.toml

# Run the exporter
./oracledb_exporter --web.listen-address=:9161 --log.level=info
```

**Add to Prometheus config:**
```yaml
scrape_configs:
  - job_name: oracle-exporter
    static_configs:
      - targets:
          - oracle-host:9161
        labels:
          component: oracle-db
    metrics_path: /metrics
    scrape_interval: 30s
```

#### B. Loki for Log Aggregation (for Connector Logs Dashboard)

**Install Loki and Promtail:**
```bash
# Using Docker Compose (recommended)
cat >> docker-compose.yml <<EOF
  loki:
    image: grafana/loki:2.9.0
    ports:
      - "3100:3100"
    command: -config.file=/etc/loki/local-config.yaml
    volumes:
      - loki-data:/loki

  promtail:
    image: grafana/promtail:2.9.0
    volumes:
      - /var/log:/var/log
      - ./monitoring/promtail-config.yml:/etc/promtail/config.yml
    command: -config.file=/etc/promtail/config.yml
EOF
```

**Configure Docker logging for Kafka Connect:**
Add to your Kafka Connect service in docker-compose.yml:
```yaml
  connect:
    # ... existing config ...
    logging:
      driver: loki
      options:
        loki-url: "http://loki:3100/loki/api/v1/push"
        labels: "job=kafka-connect,container=connect"
```

**Add Loki datasource in Grafana:**
```yaml
# monitoring/grafana/provisioning/datasources/datasources.yml
- name: loki
  type: loki
  access: proxy
  url: http://loki:3100
  isDefault: false
  editable: true
```

**Alternative: File-based logging with Promtail:**
```yaml
# monitoring/promtail-config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: kafka-connect
    static_configs:
      - targets:
          - localhost
        labels:
          job: kafka-connect
          __path__: /var/log/kafka-connect/*.log
```

## Setup Steps

### Step 1: Deploy Oracle Database Exporter

```bash
# 1. Create monitoring user in Oracle
cd /Users/maniselvank/Mani/customer/airtel/oracle-xstream-cdc-poc
sqlplus system/password@RACDB @monitoring/oracle-exporter/grants.sql

# 2. Test connection
sqlplus oracledb_exporter/your_password@RACDB
SQL> SELECT * FROM v$streams_capture;

# 3. Start exporter
export DATA_SOURCE_NAME="oracledb_exporter/your_password@//oracle-rac-scan:1521/RACDB"
export CUSTOM_METRICS="$PWD/monitoring/oracle-exporter/custom-queries.toml"
./oracledb_exporter --web.listen-address=:9161 &

# 4. Verify metrics
curl http://localhost:9161/metrics | grep oracle_xstream
```

### Step 2: Deploy Loki Stack

```bash
# 1. Start Loki and Promtail
docker-compose up -d loki promtail

# 2. Verify Loki is running
curl http://localhost:3100/ready

# 3. Configure Kafka Connect logging
# Edit docker-compose.yml and add logging driver (see above)
docker-compose up -d connect

# 4. Test log ingestion
curl -G -s "http://localhost:3100/loki/api/v1/query" --data-urlencode 'query={job="kafka-connect"}' | jq
```

### Step 3: Update Prometheus Configuration

```bash
# Edit monitoring/prometheus/prometheus.yml
vim monitoring/prometheus/prometheus.yml
```

Add the oracle-exporter job:
```yaml
scrape_configs:
  # ... existing jobs ...
  
  # Oracle Database - oracledb_exporter
  - job_name: oracle-exporter
    static_configs:
      - targets:
          - oracle-rac-node1:9161
        labels:
          component: oracle-db
          instance: oracle-rac-node1
    metrics_path: /metrics
    scrape_interval: 30s
    scrape_timeout: 10s

  # Node exporter on Oracle hosts (optional, for host metrics)
  - job_name: node-exporter
    static_configs:
      - targets:
          - oracle-rac-node1:9100
          - oracle-rac-node2:9100
        labels:
          component: node
    metrics_path: /metrics
    scrape_interval: 15s
```

Reload Prometheus:
```bash
docker-compose exec prometheus kill -HUP 1
# OR restart
docker-compose restart prometheus
```

### Step 4: Import Dashboards to Grafana

The dashboards are already in the provisioning directory and will be automatically loaded.

**Verify automatic provisioning:**
```bash
ls -la monitoring/grafana/dashboards/
# Should show all 7 dashboard JSON files

# Check provisioning config
cat monitoring/grafana/provisioning/dashboards/dashboards.yml
```

**Manual import (if provisioning doesn't work):**
1. Open Grafana: http://localhost:3000
2. Go to Dashboards → Import
3. Upload each JSON file from `monitoring/grafana/dashboards/`
4. Select "prometheus" as the datasource
5. For connector-logs.json, also select "loki" datasource

### Step 5: Verify Dashboards

Access Grafana and check each dashboard:

1. **Oracle XStream CDC - Kafka Overview** (uid: oracle-xstream-kafka-overview)
   - URL: http://localhost:3000/d/oracle-xstream-kafka-overview
   - Should show throughput, lag, and Debezium metrics

2. **Oracle Database Performance - XStream CDC** (uid: oracle-db-performance)
   - URL: http://localhost:3000/d/oracle-db-performance
   - Requires oracle-exporter metrics
   - Check XStream capture status, SCN lag, redo mining

3. **Kafka Connect & XStream Connector Logs** (uid: connector-logs)
   - URL: http://localhost:3000/d/connector-logs
   - Requires Loki
   - Should show ERROR and WARN logs

4. **Oracle XStream CDC - Throughput & Performance** (uid: xstream-throughput-performance)
   - URL: http://localhost:3000/d/xstream-throughput-performance
   - End-to-end pipeline view

5. **Kafka Connect - Connector Health & Status** (uid: connector-health-status)
   - URL: http://localhost:3000/d/connector-health-status
   - Task health, queue, resources

## Troubleshooting

### Oracle Exporter Issues

**Problem: No oracle-exporter metrics in Prometheus**
```bash
# Check if exporter is running
curl http://oracle-host:9161/metrics

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job=="oracle-exporter")'

# Check exporter logs
./oracledb_exporter --web.listen-address=:9161 --log.level=debug
```

**Problem: Custom metrics not showing**
```bash
# Verify CUSTOM_METRICS environment variable
echo $CUSTOM_METRICS

# Test queries manually
sqlplus oracledb_exporter/password@RACDB
SQL> SELECT capture_name, total_messages_captured FROM v$streams_capture;

# Check exporter output for errors
curl http://oracle-host:9161/metrics | grep oracle_xstream_capture
```

### Loki Issues

**Problem: No logs in Grafana**
```bash
# Check Loki is receiving logs
curl -G -s "http://localhost:3100/loki/api/v1/label" | jq

# Check if job label exists
curl -G -s "http://localhost:3100/loki/api/v1/label/job/values" | jq

# Check Kafka Connect logging driver
docker inspect connect | jq '.[0].HostConfig.LogConfig'

# View Promtail logs
docker logs promtail
```

**Problem: Logs not showing up in dashboard**
- Verify Loki datasource is configured in Grafana
- Check the time range in Grafana (default: last 1 hour)
- Verify log labels match: `{job="kafka-connect"}`

### Dashboard Issues

**Problem: "No data" in panels**
1. Check datasource configuration (Prometheus/Loki)
2. Verify metrics exist: `curl http://localhost:9090/api/v1/query?query=up`
3. Check time range in Grafana
4. Verify label selectors match your setup (e.g., `server=~"$server"`)

**Problem: Variables not populating**
- Check Prometheus is scraping the required metrics
- Verify the metric name in the variable query exists
- Example: `label_values(debezium_oracle_connector_total_number_of_events_seen, server)`

## Best Practices

### 1. Retention and Storage

**Prometheus retention:**
```yaml
# In docker-compose.yml or startup args
--storage.tsdb.retention.time=30d
--storage.tsdb.retention.size=50GB
```

**Loki retention:**
```yaml
# In loki-config.yaml
limits_config:
  retention_period: 168h  # 7 days

table_manager:
  retention_deletes_enabled: true
  retention_period: 168h
```

### 2. Alerting

Create alerts in Prometheus for critical metrics:
```yaml
# monitoring/prometheus/alerts/xstream-alerts.yml
groups:
  - name: xstream-cdc
    interval: 30s
    rules:
      - alert: ConnectorTaskDown
        expr: kafka_connect_connector_task_metrics_running_ratio < 0.9
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Connector task {{ $labels.connector }} is down or failing"
          
      - alert: HighStreamingLag
        expr: debezium_oracle_connector_milliseconds_behind_source > 60000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "XStream connector lag is high: {{ $value }}ms"
          
      - alert: XStreamCaptureDisabled
        expr: oracle_streams_capture_status == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "XStream capture {{ $labels.capture_name }} is DISABLED"
```

### 3. Dashboard Organization

Create a folder structure in Grafana:
- **Oracle XStream CDC** (folder)
  - Overview Dashboard (kafka-overview.json)
  - Database Performance
  - Connector Health
  - Throughput & Performance
  - Logs

### 4. Monitoring Checklist

Daily checks:
- [ ] All connector tasks running (running_ratio ≈ 1.0)
- [ ] Streaming lag < 5 seconds
- [ ] No ERROR logs in last 24h
- [ ] Queue utilization < 70%
- [ ] Oracle capture status = ENABLED

Weekly checks:
- [ ] Review WARN logs for patterns
- [ ] Check archivelog disk usage
- [ ] Verify SCN progression
- [ ] Review throughput trends

## Next Steps

1. **Set up alerting**: Configure Alertmanager to send notifications (Slack, email, PagerDuty)
2. **Add custom panels**: Extend dashboards based on your specific tables/schemas
3. **Create SLOs**: Define Service Level Objectives for lag, throughput, availability
4. **Document runbooks**: Create operational runbooks for common issues
5. **Performance tuning**: Use dashboards to identify bottlenecks and optimize

## Support

For issues or questions:
- Confluent XStream CDC docs: https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/
- Oracle XStream docs: https://docs.oracle.com/en/database/oracle/oracle-database/19/xstrm/
- Grafana dashboards: https://grafana.com/docs/
- Prometheus monitoring: https://prometheus.io/docs/

## Dashboard URLs Quick Reference

After setup, bookmark these URLs:
- Kafka Overview: http://localhost:3000/d/oracle-xstream-kafka-overview
- DB Performance: http://localhost:3000/d/oracle-db-performance
- Logs: http://localhost:3000/d/connector-logs
- Throughput: http://localhost:3000/d/xstream-throughput-performance
- Health: http://localhost:3000/d/connector-health-status
- Connect Cluster: http://localhost:3000/d/kafka-connect-cluster-sh
- Original CDC Source: http://localhost:3000/d/oracle-xstream-cdc-source-sh
