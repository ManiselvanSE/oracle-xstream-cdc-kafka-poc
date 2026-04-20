# Oracle XStream CDC - Grafana Dashboards Quick Start

## 🎯 What Was Created

Four new comprehensive Grafana dashboards for your Oracle XStream CDC pipeline:

| Dashboard | Purpose | Status |
|-----------|---------|--------|
| **Oracle DB Performance** | Oracle XStream capture metrics, SCN lag, redo logs | ⚠️ Needs oracle-exporter |
| **Connector Logs** | Centralized log aggregation, error tracking | ⚠️ Needs Loki |
| **Throughput & Performance** | End-to-end pipeline throughput | ✅ Ready (uses existing JMX) |
| **Connector Health & Status** | Task health, queue, resources | ✅ Ready (uses existing JMX) |

## 📂 Files Created

```
monitoring/
├── grafana/dashboards/
│   ├── oracle-database-performance.json      # Oracle DB metrics
│   ├── connector-logs.json                   # Log aggregation
│   ├── throughput-performance.json           # E2E throughput
│   └── connector-health-status.json          # Health monitoring
│
├── oracle-exporter/
│   ├── custom-queries.toml                   # Oracle metric queries
│   └── grants.sql                            # DB user setup
│
├── loki/
│   └── loki-config.yaml                      # Loki config
│
├── promtail/
│   └── promtail-config.yml                   # Log shipper config
│
├── alertmanager/
│   └── alertmanager.yml                      # Alert routing
│
├── docker-compose-monitoring-additions.yml   # Deploy new services
├── DASHBOARD_SETUP_GUIDE.md                  # Complete setup guide
└── NEW_DASHBOARDS_SUMMARY.md                 # Dashboard details
```

## 🚀 Quick Start (3 Steps)

### Step 1: Access Dashboards That Work Now ✅

These dashboards work with your existing JMX setup (no additional configuration needed):

```bash
# Throughput & Performance Dashboard
open http://137.131.53.98:3000/d/xstream-throughput-performance

# Connector Health & Status Dashboard
open http://137.131.53.98:3000/d/connector-health-status
```

**What you'll see**:
- Current throughput (records/sec)
- Streaming lag (milliseconds)
- Task health (running ratio)
- Queue utilization
- JVM resources (CPU, heap)
- End-to-end pipeline view

### Step 2: Set Up Oracle Database Monitoring (Optional) 🔧

For the **Oracle DB Performance** dashboard, you need to deploy the Oracle exporter:

```bash
cd /Users/maniselvank/Mani/customer/airtel/oracle-xstream-cdc-poc

# 1. Create Oracle monitoring user
sqlplus system/password@RACDB @monitoring/oracle-exporter/grants.sql

# 2. Deploy Oracle exporter (choose one method):

# METHOD A: Docker (recommended)
docker-compose -f docker-compose.yml \
  -f monitoring/docker-compose-monitoring-additions.yml \
  up -d oracle-exporter

# METHOD B: Standalone binary
export DATA_SOURCE_NAME="oracledb_exporter/your_password@//oracle-rac-scan:1521/RACDB"
export CUSTOM_METRICS="$PWD/monitoring/oracle-exporter/custom-queries.toml"
./oracledb_exporter --web.listen-address=:9161 &

# 3. Add to Prometheus config (monitoring/prometheus/prometheus.yml)
# Add under scrape_configs:
#   - job_name: oracle-exporter
#     static_configs:
#       - targets: ['oracle-exporter:9161']

# 4. Reload Prometheus
docker-compose restart prometheus

# 5. Access dashboard
open http://137.131.53.98:3000/d/oracle-db-performance
```

### Step 3: Set Up Log Aggregation (Optional) 📊

For the **Connector Logs** dashboard, deploy Loki:

```bash
# 1. Deploy Loki and Promtail
docker-compose -f docker-compose.yml \
  -f monitoring/docker-compose-monitoring-additions.yml \
  up -d loki promtail

# 2. Configure Kafka Connect to send logs to Loki
# Edit your docker-compose.yml and add under the 'connect' service:
#   logging:
#     driver: loki
#     options:
#       loki-url: "http://loki:3100/loki/api/v1/push"
#       labels: "job=kafka-connect,container=connect"

# 3. Restart Kafka Connect
docker-compose restart connect

# 4. Add Loki datasource to Grafana (if not auto-provisioned)
# Grafana UI → Configuration → Data Sources → Add Loki
# URL: http://loki:3100

# 5. Access dashboard
open http://137.131.53.98:3000/d/connector-logs
```

## 📊 Dashboard URLs

| Dashboard | URL | Prerequisites |
|-----------|-----|---------------|
| Throughput & Performance | http://137.131.53.98:3000/d/xstream-throughput-performance | ✅ JMX (already configured) |
| Connector Health | http://137.131.53.98:3000/d/connector-health-status | ✅ JMX (already configured) |
| Oracle DB Performance | http://137.131.53.98:3000/d/oracle-db-performance | ⚠️ oracle-exporter required |
| Connector Logs | http://137.131.53.98:3000/d/connector-logs | ⚠️ Loki required |
| **Existing Dashboards** | | |
| Kafka Overview | http://137.131.53.98:3000/d/oracle-xstream-kafka-overview | ✅ Working |
| Connect Cluster | http://137.131.53.98:3000/d/kafka-connect-cluster-sh | ✅ Working |

## 🎯 Key Metrics to Check Daily

Use these dashboards for your daily health checks:

### Connector Health Dashboard
- [ ] Task running ratio ≥ 0.95 (should be close to 1.0)
- [ ] Queue utilization < 70%
- [ ] CPU usage < 80%
- [ ] Heap utilization < 80%

### Throughput Dashboard
- [ ] Current throughput matches expected load
- [ ] Streaming lag < 5 seconds
- [ ] No sudden drops in throughput

### Connector Logs (if Loki is set up)
- [ ] Zero ERROR logs in last 24 hours
- [ ] Review WARN logs for patterns

### Oracle DB Performance (if exporter is set up)
- [ ] XStream capture status = ENABLED
- [ ] SCN lag is reasonable
- [ ] Archivelog disk space is sufficient

## ⚡ Minimal Setup (What Works Now)

If you want to **start immediately without additional setup**:

1. **Access the Throughput & Performance dashboard**
   - Shows: end-to-end throughput, lag, DML breakdown
   - URL: http://137.131.53.98:3000/d/xstream-throughput-performance

2. **Access the Connector Health dashboard**
   - Shows: task health, queue, CPU, memory
   - URL: http://137.131.53.98:3000/d/connector-health-status

These two dashboards provide 80% of what you need for monitoring your CDC pipeline!

## 🔍 Troubleshooting

### Dashboard shows "No Data"
```bash
# 1. Check time range (top-right in Grafana) - default is last 1 hour
# 2. Verify Prometheus is collecting metrics
curl http://137.131.53.98:9090/api/v1/query?query=up

# 3. Check JMX metrics from Kafka Connect
curl http://localhost:9994/metrics | grep kafka_connect
```

### Want Oracle DB metrics but dashboard is empty
```bash
# Verify oracle-exporter is running
curl http://localhost:9161/metrics | grep oracle_xstream

# If not, deploy it (see Step 2 above)
```

### Want logs but dashboard is empty
```bash
# Verify Loki is running
curl http://localhost:3100/ready

# If not, deploy it (see Step 3 above)
```

## 📚 Full Documentation

For complete setup instructions and advanced configuration:
- **Complete Setup Guide**: [monitoring/DASHBOARD_SETUP_GUIDE.md](monitoring/DASHBOARD_SETUP_GUIDE.md)
- **Dashboard Details**: [monitoring/NEW_DASHBOARDS_SUMMARY.md](monitoring/NEW_DASHBOARDS_SUMMARY.md)
- **Existing Monitoring**: [monitoring/README.md](monitoring/README.md)

## 🎁 What You Get

### Immediate Benefits (No Setup Required)
✅ End-to-end pipeline throughput visibility  
✅ Connector task health monitoring  
✅ Queue and back-pressure tracking  
✅ Resource utilization (CPU, heap, threads)  
✅ DML event breakdown (INSERT/UPDATE/DELETE)  
✅ Lag monitoring from source  

### With Oracle Exporter Setup
✅ XStream capture health monitoring  
✅ SCN lag tracking  
✅ Redo log mining metrics  
✅ Archivelog monitoring  
✅ Database-side performance metrics  

### With Loki Setup
✅ Centralized log aggregation  
✅ ERROR and WARN tracking  
✅ Oracle error code (ORA-*) monitoring  
✅ Task failure detection  
✅ Connection issue tracking  
✅ Searchable log history  

## 💡 Next Steps

1. ✅ **Done**: Dashboards are created and in `monitoring/grafana/dashboards/`
2. ✅ **Done**: Configuration files for oracle-exporter and Loki are ready
3. 🔲 **Your Action**: Access the two ready dashboards (Throughput & Health)
4. 🔲 **Optional**: Deploy oracle-exporter for DB metrics
5. 🔲 **Optional**: Deploy Loki for log aggregation
6. 🔲 **Recommended**: Set up alerting with AlertManager

## 🆘 Need Help?

1. **Quick issues**: Check troubleshooting section above
2. **Setup help**: See [monitoring/DASHBOARD_SETUP_GUIDE.md](monitoring/DASHBOARD_SETUP_GUIDE.md)
3. **Metrics not showing**: Verify Prometheus targets at http://137.131.53.98:9090/targets

---

**TL;DR**: Two dashboards work now (Throughput & Health). For Oracle DB metrics, deploy oracle-exporter. For logs, deploy Loki. Full guide: `monitoring/DASHBOARD_SETUP_GUIDE.md`
