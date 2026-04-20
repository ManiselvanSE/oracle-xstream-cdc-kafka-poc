# Monitoring and Metrics Visualization

This directory contains the monitoring stack for the Oracle XStream CDC POC.

**Full dashboard documentation:** [monitoring/docs/GRAFANA-DASHBOARD-README.md](docs/GRAFANA-DASHBOARD-README.md) – Setup, panels, PromQL queries, and troubleshooting.

--- **JMX exporters**, **Prometheus**, **Grafana**, and **Kafka Exporter**. It provides CPU, memory, throughput, latency, and consumer lag visibility with alerting.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Port Reference](#2-port-reference)
3. [Prerequisites](#3-prerequisites)
4. [Installation and Setup](#4-installation-and-setup)
5. [Configuration Files](#5-configuration-files)
6. [Verification Steps](#6-verification-steps)
7. [Grafana Dashboards](#7-grafana-dashboards)
8. [Alerting Rules](#8-alerting-rules)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  Oracle XStream CDC POC – Monitoring Stack                                        │
│                                                                                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │
│  │ kafka1      │  │ kafka2      │  │ kafka3      │  │ connect     │               │
│  │ JMX :9990   │  │ JMX :9990   │  │ JMX :9990   │  │ JMX :9991   │               │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘               │
│         │                │                │                │                      │
│  ┌──────┴──────┐  ┌──────┴──────┐                       │                      │
│  │ schema-reg  │  │ kafka-       │                       │                      │
│  │ JMX :9992   │  │ exporter    │                       │                      │
│  └──────┬──────┘  │ :9308       │                       │                      │
│         │         └──────┬──────┘                       │                      │
│         │                │                │                │                      │
│         └────────────────┴────────────────┴────────────────┘                      │
│                                    │                                              │
│                                    ▼                                              │
│                         ┌─────────────────────┐                                   │
│                         │ Prometheus :9090    │                                   │
│                         │ Scrape interval: 15s│                                   │
│                         └──────────┬──────────┘                                   │
│                                    │                                              │
│                                    ▼                                              │
│                         ┌─────────────────────┐                                   │
│                         │ Grafana :3000       │                                   │
│                         │ Dashboards + Alerts│                                   │
│                         └─────────────────────┘                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

**Data flow:**
- JMX exporters run as Java agents inside Kafka, Connect, and Schema Registry.
- Kafka Exporter scrapes Kafka cluster metadata (topics, consumer lag).
- Prometheus scrapes all exporters every 15 seconds.
- Grafana queries Prometheus and displays dashboards.

---

## 2. Port Reference

| Component        | Service Port | JMX Exporter Port | Host Port (JMX) |
|-----------------|-------------|-------------------|-----------------|
| kafka1          | 9092        | 9990              | 9990            |
| kafka2          | 9094        | 9990              | 9991            |
| kafka3          | 9095        | 9990              | 9992            |
| connect         | 8083        | 9991              | 9994            |
| schema-registry | 8081        | 9992              | 9993            |
| kafka-exporter  | —           | —                 | 9308            |
| prometheus      | —           | —                 | 9090            |
| grafana         | —           | —                 | 3000            |
| loki            | 3100        | —                 | 3100            |
| promtail        | 9080        | —                 | — (internal)    |

When using `docker/docker-compose.monitoring.yml`, **Loki** and **Promtail** start with the stack so the **Connector logs** dashboard (`connector-logs`) can query Connect/Kafka container logs.

---

## 3. Prerequisites

- Docker and Docker Compose
- Oracle XStream CDC base stack running (Kafka, Connect, Schema Registry)
- Network access from Prometheus to all JMX exporter endpoints

---

## 4. Installation and Setup

### Step 1: Build images (JMX is enabled in base `docker-compose.yml`)

From the project root:

```bash
cd docker
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml build
```

The base stack includes JMX exporters so Prometheus can scrape broker, Connect, and Schema Registry metrics. Images built:

- `kafka-jmx:7.9.0` (Kafka brokers with JMX exporter)
- `schema-registry-jmx:7.9.0` (Schema Registry with JMX exporter)
- `docker-connect` (Connect image already includes JMX exporter)

### Step 2: Start the Stack with Monitoring

```bash
# From project root
cd docker
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
```

### Step 3: Verify All Services

```bash
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml ps
```

Expected: `kafka1`, `kafka2`, `kafka3`, `schema-registry`, `connect`, `kafka-exporter`, `prometheus`, `grafana` all running.

---

## 5. Configuration Files

| File | Purpose |
|------|---------|
| `monitoring/jmx/kafka-broker.yml` | JMX Exporter config for Kafka brokers |
| `monitoring/jmx/kafka-connect.yml` | JMX Exporter config for Kafka Connect |
| `monitoring/jmx/schema-registry.yml` | JMX Exporter config for Schema Registry |
| `monitoring/prometheus/prometheus.yml` | Prometheus scrape config and targets |
| `monitoring/prometheus/alerts/kafka-alerts.yml` | Prometheus alerting rules |
| `monitoring/grafana/provisioning/datasources/datasources.yml` | Grafana Prometheus datasource |
| `monitoring/grafana/dashboards/kafka-overview.json` | Kafka overview dashboard |

---

## 6. Verification Steps

### 6.1 JMX Exporter Endpoints

From the host (replace `localhost` with VM IP if remote):

```bash
# Kafka broker 1
curl -s http://localhost:9990/metrics | head -20

# Kafka Connect
curl -s http://localhost:9994/metrics | head -20

# Schema Registry
curl -s http://localhost:9993/metrics | head -20

# Kafka Exporter
curl -s http://localhost:9308/metrics | head -20
```

### 6.2 Prometheus Targets

1. Open http://localhost:9090/targets (or `http://<vm-ip>:9090/targets`)
2. All targets should show **UP**:
   - `prometheus`
   - `kafka-broker` (3 instances)
   - `kafka-connect`
   - `schema-registry`
   - `kafka-exporter`

### 6.3 Grafana

1. Open http://localhost:3000 (or `http://<vm-ip>:3000`)
2. Login: `admin` / `admin` (change on first login)
3. Go to **Dashboards** → **Oracle XStream CDC - Kafka Overview**
4. Confirm panels show data (CPU, memory, throughput, consumer lag)

---

## 7. Grafana Dashboards

JSON dashboards under `monitoring/grafana/dashboards/` are auto-provisioned. Highlights:

| Dashboard | UID (path `/d/<uid>`) | Data source |
|-----------|------------------------|-------------|
| Oracle XStream CDC - Throughput & Performance | `xstream-throughput-performance` | Prometheus (JMX) |
| Connector Health & Status | `connector-health-status` | Prometheus (JMX) |
| Connector logs | `connector-logs` | Loki (needs Loki + Promtail) |
| Oracle Database Performance | `oracle-db-performance` | Prometheus (needs oracledb_exporter) |
| Oracle XStream CDC - Source (self-hosted) | (see file) | Prometheus |
| Kafka overview / Connect cluster | (see files) | Prometheus |

### Oracle XStream CDC - Kafka Overview

Panels include:
- **Oracle XStream CDC Throughput** – Messages/sec from RAC into CDC topics (requires JMX on Kafka)
- **Oracle XStream Connector Throughput** – Records/sec written by the connector (requires JMX on Connect)
- **CPU Usage (JVM Process)** – Kafka, Connect, Schema Registry
- **JVM Heap Memory Used** – Memory usage per component
- **Targets Up** – Health of all scrape targets
- **JVM Thread Count** – Thread usage
- **Consumer Group Lag** – From Kafka Exporter
- **Topic Partitions** – Partition count per topic
- **Kafka Throughput** – Messages in per minute
- **Kafka Bytes In** – Total bytes ingested

### Adding Grafana Alerts

1. Edit a panel → **Alert** tab
2. Create alert rule with condition (e.g., `jvm_memory_bytes_used{area="heap"}/jvm_memory_bytes_max{area="heap"} > 0.9`)
3. Configure notification channel (email, Slack, etc.)

---

## 8. Alerting Rules

Prometheus alert rules are in `monitoring/prometheus/alerts/kafka-alerts.yml`:

| Alert | Condition | Severity |
|-------|-----------|----------|
| KafkaBrokerDown | `up{job="kafka-broker"} == 0` for 1m | critical |
| KafkaBrokerHighCPU | `jvm_os_processcpuload > 0.9` for 5m | warning |
| KafkaBrokerHighMemory | Heap usage > 90% for 5m | warning |
| KafkaConnectDown | `up{job="kafka-connect"} == 0` for 1m | critical |
| KafkaConnectHighCPU | CPU > 90% for 5m | warning |
| KafkaConnectHighMemory | Heap > 90% for 5m | warning |
| SchemaRegistryDown | `up{job="schema-registry"} == 0` for 1m | critical |
| KafkaExporterDown | `up{job="kafka-exporter"} == 0` for 1m | warning |
| KafkaConsumerLagHigh | `kafka_consumergroup_lag > 10000` for 10m | warning |

To add Alertmanager for notifications, configure `alerting.alertmanagers` in `prometheus.yml`.

---

## CDC Throughput Metrics

To see **how much throughput the Oracle XStream CDC connector processes** from the RAC database:

- **Topic-level:** `sum(rate(kafka_server_brokertopicmetrics_messagesin_total{topic=~"racdb.*"}[5m]))` – messages/sec into CDC topics
- **Connector-level:** `kafka_connect_source_task_metrics_source_record_write_rate{connector="oracle-xstream-rac-connector"}` – records/sec written by the connector

Both require JMX exporters (use `docker-compose.monitoring.yml`). See [monitoring/docs/CDC-THROUGHPUT-METRICS.md](docs/CDC-THROUGHPUT-METRICS.md) for full details.

---

## 9. Troubleshooting

### JMX Exporter Not Exposing Metrics

- Ensure the Java agent JAR is present and the config path is correct.
- Check container logs: `docker logs kafka1` (or connect, schema-registry).
- Verify port is exposed: `docker port kafka1`.

### Prometheus Targets Down

- Ensure all containers are on the same Docker network.
- From Prometheus container: `docker exec prometheus wget -qO- http://kafka1:9990/metrics | head -5`.

### Grafana "No Data"

- Confirm Prometheus datasource is configured and working (Explore → run a query like `up`).
- Check time range in the dashboard.
- Verify metric names match (JMX exporter output may vary by Kafka version).
- **CDC dashboards:** `Server (topic.prefix)` / `topic.prefix` use a **custom** default (`All` = `.*`) so panels work even when Debezium label queries return nothing. Broker CDC throughput uses topic regex `*.ORDERMGMT.MTX*` (not only `racdb.*`). After changing Prometheus rules, restart Prometheus so `monitoring/prometheus/recording/*.yml` loads.

### High Memory Alerts

- Tune JVM heap for Kafka/Connect (`KAFKA_HEAP_OPTS`, `CONNECT_HEAP_OPTS`).
- Review connector task count and parallelism.

---

## Optional: Download JMX Agent Manually

If you need the JMX agent JAR outside Docker (e.g., for bare-metal):

```bash
./monitoring/scripts/download-jmx-agent.sh
```

The JAR is saved to `monitoring/agents/jmx_prometheus_javaagent-0.20.0.jar`.
