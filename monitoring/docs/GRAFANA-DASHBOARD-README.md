# Oracle XStream CDC – Grafana Dashboard Setup Guide

A comprehensive guide for setting up and using the **"Oracle XStream CDC - Kafka Overview"** Grafana dashboard to monitor a Change Data Capture (CDC) pipeline from Oracle RAC to Apache Kafka.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Architecture Overview](#2-architecture-overview)
3. [Prerequisites](#3-prerequisites)
4. [Project Structure](#4-project-structure)
5. [Step-by-Step Setup](#5-step-by-step-setup)
6. [Docker Compose Configuration](#6-docker-compose-configuration)
7. [Running the Stack](#7-running-the-stack)
8. [Grafana Dashboard: Oracle XStream CDC - Kafka Overview](#8-grafana-dashboard-oracle-xstream-cdc---kafka-overview)
9. [Monitoring & Alerting](#9-monitoring--alerting)
10. [Troubleshooting](#10-troubleshooting)
11. [Best Practices](#11-best-practices)
12. [Conclusion](#12-conclusion)

---

## 1. Introduction

### 1.1 Overview of Oracle XStream CDC and Kafka Integration

Oracle XStream CDC (Change Data Capture) streams DML and DDL changes from Oracle databases (including RAC) to Apache Kafka in real time. The Confluent Oracle XStream CDC Source Connector runs inside Kafka Connect and:

- Captures INSERT, UPDATE, DELETE operations from Oracle tables
- Streams changes to Kafka topics in Debezium JSON format
- Supports snapshot and streaming phases
- Integrates with Oracle XStream Out (outbound server) and redo logs

### 1.2 Purpose of the "Oracle XStream CDC - Kafka Overview" Dashboard

This dashboard provides a single pane of glass for:

- **Infrastructure health** – Kafka brokers, Connect, Schema Registry, Prometheus, Kafka Exporter
- **CDC throughput** – Messages per second from Oracle RAC into Kafka topics
- **Consumer lag** – How far behind consumers are
- **JVM metrics** – CPU, heap memory, thread count for Java components
- **Topic and partition visibility** – CDC topic layout and activity

### 1.3 Insights This Dashboard Provides

| Insight | Source | Use Case |
|---------|--------|----------|
| **Throughput (messages/sec)** | Kafka broker JMX | CDC events flowing from Oracle into Kafka |
| **Consumer lag** | Kafka Exporter | Downstream processing delay |
| **Topic partitions** | Kafka Exporter | CDC topic structure and growth |
| **JVM health** | JMX Exporter | CPU, memory, GC pressure |
| **Target availability** | Prometheus `up` | Service health at a glance |
| **Connector throughput** | Kafka Connect JMX | Records written by Oracle XStream connector |

---

## 2. Architecture Overview

### 2.1 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  Oracle RAC Database                                                                      │
│  ┌─────────────────────┐                                                                  │
│  │ Redo Log / XStream  │                                                                  │
│  │ Capture → LCRs       │                                                                  │
│  └──────────┬──────────┘                                                                  │
└─────────────┼────────────────────────────────────────────────────────────────────────────┘
             │ 1521/TCP (XStream API)
             ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  Connector VM (Docker)                                                                    │
│                                                                                          │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐   │
│  │  Kafka Connect + Oracle XStream CDC Connector                                      │   │
│  │  (JMX Exporter optional)                                                           │   │
│  └────────────────────────────────┬─────────────────────────────────────────────────┘   │
│                                   │ produce                                               │
│  ┌────────────────────────────────▼─────────────────────────────────────────────────┐   │
│  │  3-Broker Kafka Cluster (JMX Exporter :9990)                                        │   │
│  │  Topics: racdb.ORDERMGMT.*, _connect-*, _schemas                                   │   │
│  └────────────────────────────────┬─────────────────────────────────────────────────┘   │
│                                   │                                                       │
│  ┌────────────────────────────────▼─────────────────────────────────────────────────┐   │
│  │  Schema Registry (JMX Exporter :9992)                                              │   │
│  └──────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                          │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐   │
│  │  Kafka Exporter (:9308) – scrapes Kafka metadata (topics, consumer lag)           │   │
│  └────────────────────────────────┬─────────────────────────────────────────────────┘   │
│                                   │                                                       │
│  ┌────────────────────────────────▼─────────────────────────────────────────────────┐   │
│  │  Prometheus (:9090) – scrapes JMX exporters + Kafka Exporter every 15s           │   │
│  └────────────────────────────────┬─────────────────────────────────────────────────┘   │
│                                   │                                                       │
│  ┌────────────────────────────────▼─────────────────────────────────────────────────┐   │
│  │  Grafana (:3000) – "Oracle XStream CDC - Kafka Overview" dashboard                 │   │
│  └──────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Metrics Flow

```
Oracle RAC → XStream Out → Kafka Connect (Oracle XStream Connector) → Kafka Topics
                                                                           │
                    JMX Exporter (Kafka brokers) ──────────────────────────┘
                    Kafka Exporter ────────────────────────────────────────┘
                                    │
                                    ▼
                              Prometheus
                                    │
                                    ▼
                               Grafana
```

---

## 3. Prerequisites

- **Docker** and **Docker Compose** (v2+)
- **Oracle RAC** with XStream Out configured and supplemental logging enabled
- **Kafka cluster** (3 brokers recommended for production)
- **Kafka Connect** with Oracle XStream CDC connector deployed and running
- **Schema Registry** (optional but recommended)
- Network connectivity from Prometheus to all scrape targets (JMX exporters, Kafka Exporter)

---

## 4. Project Structure

```
oracle-xstream-cdc-poc/
├── docker/
│   ├── docker-compose.yml              # Base: Kafka, Schema Registry, Connect
│   ├── docker-compose.monitoring.yml    # Monitoring: JMX, Prometheus, Grafana, Kafka Exporter
│   ├── Dockerfile.kafka-jmx            # Kafka broker + JMX Exporter
│   ├── Dockerfile.schema-registry-jmx   # Schema Registry + JMX Exporter
│   └── Dockerfile.connect               # Kafka Connect + Oracle XStream connector
├── monitoring/
│   ├── jmx/                            # JMX Exporter configs
│   │   ├── kafka-broker.yml
│   │   ├── kafka-connect.yml
│   │   └── schema-registry.yml
│   ├── prometheus/
│   │   ├── prometheus.yml              # Scrape config
│   │   └── alerts/
│   │       └── kafka-alerts.yml        # Alert rules
│   ├── grafana/
│   │   ├── provisioning/
│   │   │   ├── datasources/
│   │   │   │   └── datasources.yml     # Prometheus datasource
│   │   │   └── dashboards/
│   │   │       └── dashboards.yml       # Dashboard provisioning
│   │   └── dashboards/
│   │       └── kafka-overview.json     # "Oracle XStream CDC - Kafka Overview"
│   └── docs/
│       ├── GRAFANA-DASHBOARD-README.md # This file
│       └── CDC-THROUGHPUT-METRICS.md
└── xstream-connector/                  # Connector config (oracle-xstream-rac-docker.json)
```

---

## 5. Step-by-Step Setup

### 5.1 Prometheus Setup

**File:** `monitoring/prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/alerts/*.yml

scrape_configs:
  # Self-monitoring
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  # Kafka brokers – JMX Exporter (CPU, memory, throughput)
  - job_name: kafka-broker
    static_configs:
      - targets: ["kafka1:9990", "kafka2:9990", "kafka3:9990"]
    metrics_path: /metrics
    scrape_interval: 15s

  # Kafka Connect – JMX Exporter (connector throughput)
  - job_name: kafka-connect
    static_configs:
      - targets: ["connect:9991"]
    metrics_path: /metrics
    scrape_interval: 15s

  # Schema Registry – JMX Exporter
  - job_name: schema-registry
    static_configs:
      - targets: ["schema-registry:9992"]
    metrics_path: /metrics
    scrape_interval: 15s

  # Kafka Exporter – topic partitions, consumer lag
  - job_name: kafka-exporter
    static_configs:
      - targets: ["kafka-exporter:9308"]
    metrics_path: /metrics
    scrape_interval: 15s
```

**Jobs explained:**

| Job | Targets | Metrics |
|-----|---------|---------|
| `prometheus` | Prometheus itself | Self-monitoring |
| `kafka-broker` | Kafka brokers JMX :9990 | Throughput, JVM, broker stats |
| `kafka-connect` | Connect JMX :9991 | Connector records/sec (if JMX enabled) |
| `schema-registry` | Schema Registry JMX :9992 | JVM, schema metrics |
| `kafka-exporter` | Kafka Exporter :9308 | Consumer lag, topic partitions |

---

### 5.2 JMX Exporter Setup

JMX Exporter runs as a Java agent inside each JVM and exposes `/metrics` for Prometheus.

**Kafka broker config:** `monitoring/jmx/kafka-broker.yml`

```yaml
lowercaseOutputName: true
whitelistObjectNames:
  - "kafka.server:*"
  - "kafka.network:*"
  - "kafka.log:*"
  - "java.lang:*"
rules:
  - pattern: kafka.server<type=(.+), name=(.+), topic=(.+), partition=(.*)><>Count
    name: kafka_server_$1_$2
    labels: { topic: "$3", partition: "$4" }
    type: COUNTER
  - pattern: java.lang<type=Memory><>HeapMemoryUsage\.(used|committed|max)
    name: jvm_memory_heap_$1
    type: GAUGE
  - pattern: java.lang<type=OperatingSystem><>ProcessCpuLoad
    name: jvm_os_ProcessCpuLoad
    type: GAUGE
  - pattern: java.lang<type=Threading><>ThreadCount
    name: jvm_threads_count
    type: GAUGE
```

**Attaching JMX Exporter to Kafka brokers:**

```yaml
environment:
  KAFKA_OPTS: "-javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=9990:/opt/jmx-exporter/kafka-broker.yml"
```

**Attaching to Schema Registry:**

```yaml
environment:
  SCHEMA_REGISTRY_OPTS: "-javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=9992:/opt/jmx-exporter/schema-registry.yml"
```

**Kafka Connect** (optional; requires JMX agent JAR in image):

```yaml
environment:
  KAFKA_OPTS: "-javaagent:/usr/share/java/jmx_prometheus_javaagent.jar=9991:/opt/jmx-exporter/kafka-connect.yml"
```

---

### 5.3 Grafana Setup

**Docker:** Grafana runs as a container, with Prometheus as the datasource.

**Datasource provisioning:** `monitoring/grafana/provisioning/datasources/datasources.yml`

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    uid: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
```

**Manual setup (if not using provisioning):**

1. Open Grafana → **Connections** → **Data sources**
2. Add **Prometheus**
3. URL: `http://prometheus:9090` (use Docker service name when both run in same network)
4. Save & test

---

## 6. Docker Compose Configuration

**Full monitoring stack:** Use base compose + monitoring override:

```yaml
# docker-compose.monitoring.yml (merge with base docker-compose.yml)
services:
  kafka1:
    build: { context: ., dockerfile: Dockerfile.kafka-jmx }
    image: kafka-jmx:7.9.0
    environment:
      KAFKA_OPTS: "-javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=9990:/opt/jmx-exporter/kafka-broker.yml"
    ports: ["9092:9092", "9990:9990"]
    volumes: [../monitoring/jmx/kafka-broker.yml:/opt/jmx-exporter/kafka-broker.yml:ro]

  schema-registry:
    build: { context: ., dockerfile: Dockerfile.schema-registry-jmx }
    environment:
      SCHEMA_REGISTRY_OPTS: "-javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=9992:/opt/jmx-exporter/schema-registry.yml"
    ports: ["8081:8081", "9993:9992"]
    volumes: [../monitoring/jmx/schema-registry.yml:/opt/jmx-exporter/schema-registry.yml:ro]

  kafka-exporter:
    image: danielqsj/kafka-exporter:latest
    command:
      - --kafka.server=kafka1:29092
      - --kafka.server=kafka2:29092
      - --kafka.server=kafka3:29092
      - --web.listen-address=:9308
    ports: ["9308:9308"]
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:v2.47.0
    command: [--config.file=/etc/prometheus/prometheus.yml, --storage.tsdb.path=/prometheus]
    ports: ["9090:9090"]
    volumes:
      - ../monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ../monitoring/prometheus/alerts:/etc/prometheus/alerts:ro
      - prometheus-data:/prometheus
    restart: unless-stopped

  grafana:
    image: grafana/grafana:10.2.0
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: <set-secure-password>
    ports: ["3000:3000"]
    volumes:
      - grafana-data:/var/lib/grafana
      - ../monitoring/grafana/provisioning:/etc/grafana/provisioning:ro
      - ../monitoring/grafana/dashboards:/var/lib/grafana/dashboards:ro
    depends_on: [prometheus]
    restart: unless-stopped

volumes:
  prometheus-data:
  grafana-data:
```

**Ports:**

| Service | Port | Purpose |
|---------|------|---------|
| Prometheus | 9090 | Web UI, metrics API |
| Grafana | 3000 | Dashboards |
| Kafka Exporter | 9308 | /metrics |
| Kafka JMX | 9990 (each broker) | JMX Exporter /metrics |
| Schema Registry JMX | 9992 | JMX Exporter /metrics |

---

## 7. Running the Stack

### Start with monitoring

```bash
cd oracle-xstream-cdc-poc
./docker/scripts/start-docker-cluster-with-monitoring.sh
```

Or manually:

```bash
docker compose -f docker/docker-compose.yml -f docker/docker-compose.monitoring.yml build
docker compose -f docker/docker-compose.yml -f docker/docker-compose.monitoring.yml up -d
```

### Verify services

```bash
# Containers
docker ps

# Prometheus targets (all should be UP)
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Kafka Exporter metrics
curl -s http://localhost:9308/metrics | grep kafka_topic_partitions

# Grafana
open http://localhost:3000   # or http://<vm-ip>:3000
```

---

## 8. Grafana Dashboard: Oracle XStream CDC - Kafka Overview

### 8.1 Dashboard Overview

**Purpose:** Single view for CDC pipeline health, throughput, and lag.

**Key KPIs:**

- Targets Up (Prometheus scrape health)
- Oracle XStream CDC Throughput (messages/sec from RAC)
- Consumer Group Lag
- JVM health (CPU, heap, threads)

### 8.2 Panels Explanation

| Panel | Query / Source | Description |
|-------|----------------|-------------|
| **CPU Usage (JVM Process)** | `jvm_os_ProcessCpuLoad{job=~"kafka-broker\|kafka-connect\|schema-registry"}` | CPU load per component (0–1) |
| **JVM Heap Memory Used** | `jvm_memory_heap_used{job=~"kafka-broker\|kafka-connect\|schema-registry"}` | Heap usage in bytes |
| **Targets Up** | `up{job=~"kafka-broker\|kafka-connect\|schema-registry\|kafka-exporter\|prometheus"}` | Scrape target health (1=up, 0=down) |
| **JVM Thread Count** | `jvm_threads_count{job=~"kafka-broker\|kafka-connect\|schema-registry"}` | Active JVM threads |
| **Consumer Group Lag** | `kafka_consumergroup_lag{job="kafka-exporter"}` | Messages behind per consumer group/topic |
| **Topic Partitions** | `kafka_topic_partitions{job="kafka-exporter"}` | Partition count per topic |
| **Kafka Throughput (Messages In/min)** | `rate(kafka_server_brokertopicmetrics_messagesin_total[5m]) * 60` | Messages per minute per broker |
| **Kafka Bytes In (total)** | `kafka_server_brokertopicmetrics_bytesin_total` | Cumulative bytes in |
| **Oracle XStream CDC Throughput** | `sum(rate(kafka_server_brokertopicmetrics_messagesin_total{topic=~"racdb.*"}[5m]))` | CDC messages/sec into `racdb.*` topics |
| **Oracle XStream Connector Throughput** | `kafka_connect_source_task_metrics_source_record_write_rate{connector="oracle-xstream-rac-connector"}` | Records/sec written by connector (requires Connect JMX) |

**SCN and redo throughput:** Oracle XStream does not expose SCN or redo bytes directly to Prometheus. CDC throughput is approximated by `racdb.*` topic message rate and connector record rate.

### 8.3 Sample Prometheus Queries

**Throughput (messages/sec into CDC topics):**

```promql
sum(rate(kafka_server_brokertopicmetrics_messagesin_total{topic=~"racdb.*"}[5m]))
```

**Throughput (bytes/sec):**

```promql
sum(rate(kafka_server_brokertopicmetrics_bytesin_total{topic=~"racdb.*"}[5m]))
```

**Consumer lag (total):**

```promql
sum(kafka_consumergroup_lag{job="kafka-exporter"})
```

**JVM heap usage (fraction):**

```promql
jvm_memory_heap_used{job="kafka-broker"} / jvm_memory_heap_max{job="kafka-broker"}
```

**Target availability:**

```promql
up{job=~"kafka-broker|kafka-connect|kafka-exporter"}
```

### 8.4 Dashboard Import

**Option A: File import**

1. Grafana → **Dashboards** → **New** → **Import**
2. **Upload JSON file** → select `monitoring/grafana/dashboards/kafka-overview.json`
3. Choose **Prometheus** datasource
4. Click **Import**

**Option B: Paste JSON**

1. Grafana → **Dashboards** → **New** → **Import**
2. **Import via panel json** → paste contents of `kafka-overview.json`
3. Choose **Prometheus** datasource
4. Click **Import**

---

## 9. Monitoring & Alerting

### 9.1 Suggested Alerts

| Alert | Condition | Severity |
|-------|-----------|----------|
| KafkaBrokerDown | `up{job="kafka-broker"} == 0` for 1m | critical |
| KafkaBrokerHighCPU | `jvm_os_ProcessCpuLoad{job="kafka-broker"} > 0.9` for 5m | warning |
| KafkaBrokerHighMemory | Heap usage > 90% for 5m | warning |
| KafkaConnectDown | `up{job="kafka-connect"} == 0` for 1m | critical |
| SchemaRegistryDown | `up{job="schema-registry"} == 0` for 1m | critical |
| KafkaExporterDown | `up{job="kafka-exporter"} == 0` for 1m | warning |
| KafkaConsumerLagHigh | `kafka_consumergroup_lag > 10000` for 10m | warning |

### 9.2 Example Alert Rules

**File:** `monitoring/prometheus/alerts/kafka-alerts.yml`

```yaml
groups:
  - name: kafka-broker
    rules:
      - alert: KafkaBrokerDown
        expr: up{job="kafka-broker"} == 0
        for: 1m
        labels: { severity: critical }
        annotations:
          summary: "Kafka broker {{ $labels.instance }} is down"

      - alert: KafkaConsumerLagHigh
        expr: kafka_consumergroup_lag{job="kafka-exporter"} > 10000
        for: 10m
        labels: { severity: warning }
        annotations:
          summary: "High consumer lag for {{ $labels.consumergroup }}"
```

---

## 10. Troubleshooting

### No metrics in Grafana

- **Datasource:** Ensure Prometheus URL is `http://prometheus:9090` when both run in Docker.
- **Time range:** Use "Last 1 hour" or wider.
- **Targets:** Check http://localhost:9090/targets for DOWN targets.

### JMX Exporter not exposing data

- **Port:** Confirm JMX Exporter port is exposed and reachable from Prometheus.
- **Config:** Validate JMX config YAML and MBean patterns.
- **JAR:** Ensure `jmx_prometheus_javaagent.jar` exists at the path used in `KAFKA_OPTS` / `SCHEMA_REGISTRY_OPTS`.

### Kafka lag issues

- **Consumer groups:** `kafka_consumergroup_lag` only appears for active consumer groups.
- **Throughput:** Compare consumer lag with `rate(kafka_server_brokertopicmetrics_messagesin_total{topic=~"racdb.*"}[5m])` to see if producers outpace consumers.

### Connect JMX not working

- Connect may not include the JMX agent JAR. The dashboard works without Connect JMX; Kafka Exporter and broker JMX provide most metrics.

---

## 11. Best Practices

- **Scrape interval:** 15s is a good default; avoid < 5s for JMX.
- **Retention:** Configure Prometheus `--storage.tsdb.retention.time` for long-term storage.
- **Security:** Do not expose Prometheus/Grafana publicly without auth; use VPN or private network.
- **Scaling:** Run one Kafka Exporter per cluster; JMX exporters scale with broker/Connect instances.

---

## 12. Conclusion

The **"Oracle XStream CDC - Kafka Overview"** dashboard gives visibility into CDC throughput, consumer lag, and infrastructure health. Use it together with Prometheus alerting to operate the Oracle XStream CDC pipeline reliably.

For more detail on CDC throughput metrics, see [CDC-THROUGHPUT-METRICS.md](CDC-THROUGHPUT-METRICS.md).
