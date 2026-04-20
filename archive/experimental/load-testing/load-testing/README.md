# Kafka → Flink Throughput Load Testing Guide

Generate controlled load, run step tests to find max throughput, and identify bottlenecks in your Kafka → Flink streaming pipeline.

---

## Quick Start

```bash
# From project root
cd oracle-xstream-cdc-poc

# Create test topic (if needed)
docker exec kafka1 kafka-topics --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 \
  --create --topic test-throughput --partitions 6 --replication-factor 3

# Single load: 5K events/sec, 1KB msg, 60 seconds
./load-testing/scripts/run-load-from-docker.sh test-throughput 5000 1024 60

# Step test: 5K → 10K → 25K → 50K → 75K → 100K events/sec
./load-testing/scripts/step-load-test.sh test-throughput 1024
```

---

## 1. Load Generation

### Option A: `kafka-producer-perf-test` (recommended)

```bash
# From host (Docker)
./load-testing/scripts/run-load-from-docker.sh <topic> <rate-events-per-sec> [message-size] [duration]

# Examples
./load-testing/scripts/run-load-from-docker.sh test-throughput 5000 1024 60   # 5K/s, 1KB, 1min
./load-testing/scripts/run-load-from-docker.sh test-throughput 50000 1024 300 # 50K/s, 5min
```

### Option B: Direct Docker command

```bash
docker exec kafka1 kafka-producer-perf-test \
  --topic test-throughput \
  --num-records 300000 \
  --record-size 1024 \
  --throughput 5000 \
  --producer-props bootstrap.servers=kafka1:29092,kafka2:29092,kafka3:29092
```

### Option C: Custom JSON producer (Python)

For CDC-like JSON payloads, use the Python script:

```bash
pip install confluent-kafka
python load-testing/scripts/json-producer.py test-throughput 5000 1024 60
```

---

## 2. Step Test Plan (5K → 10K → 50K → 100K events/sec)

| Step | Rate (events/sec) | Message Size | Duration | Total Records |
|------|-------------------|--------------|----------|---------------|
| 1 | 5,000 | 1 KB | 2 min | 600,000 |
| 2 | 10,000 | 1 KB | 2 min | 1,200,000 |
| 3 | 25,000 | 1 KB | 2 min | 3,000,000 |
| 4 | 50,000 | 1 KB | 2 min | 6,000,000 |
| 5 | 75,000 | 1 KB | 2 min | 9,000,000 |
| 6 | 100,000 | 1 KB | 2 min | 12,000,000 |

**Run:** `./load-testing/scripts/step-load-test.sh test-throughput 1024`

**Between steps:** Wait 30s to observe lag stabilization before increasing load.

---

## 3. Metrics to Monitor

### Kafka (Prometheus / Grafana)

| Metric | PromQL | What to watch |
|--------|--------|---------------|
| **Messages in/sec** | `rate(kafka_server_brokertopicmetrics_messagesin_total{topic="<topic>"}[5m])` | Producer throughput |
| **Bytes in/sec** | `rate(kafka_server_brokertopicmetrics_bytesin_total{topic="<topic>"}[5m])` | Data volume |
| **Consumer lag** | `kafka_consumergroup_lag{job="kafka-exporter",topic="<topic>"}` | Flink falling behind |
| **Under-replicated partitions** | `kafka_server_replicamanager_underreplicatedpartitions` | Replication issues |

### Flink

| Metric | Location | What to watch |
|--------|----------|---------------|
| **Backpressure** | Flink UI → Job → Backpressure | High = bottleneck |
| **Records in/sec** | Flink Metrics → `numRecordsInPerSecond` | Consumer throughput |
| **Records out/sec** | `numRecordsOutPerSecond` | Processing throughput |
| **Latency** | `latency` (source/sink) | End-to-end delay |
| **Checkpoint duration** | `checkpoint_duration` | State overhead |
| **Task CPU** | Flink Metrics / JMX | CPU saturation |

### Grafana Dashboard

Use **Oracle XStream CDC - Kafka Overview**:

- **Consumer Group Lag** – Flink consumer lag
- **Kafka Throughput** – Messages in
- **Oracle XStream CDC Throughput** – If using CDC topics (`racdb.*`)

---

## 4. Bottleneck Identification

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| **Consumer lag growing** | Flink can't keep up | Scale Flink parallelism, optimize operators |
| **Backpressure at source** | Kafka consumer slow | Increase `source parallelism`, check deserialization |
| **Backpressure at operator** | Compute/state bottleneck | Add parallelism, optimize UDFs |
| **High CPU on Flink** | Processing bottleneck | Scale out, optimize logic |
| **High CPU on Kafka** | Broker saturation | Add partitions, add brokers |
| **Under-replicated partitions** | Disk/network issues | Check broker health, disk I/O |
| **Checkpoint duration spikes** | State too large | Tune state backend, reduce state size |

### Quick checks

```bash
# Consumer lag (Flink consumer group)
docker exec kafka1 kafka-consumer-groups --bootstrap-server kafka1:29092 \
  --group <flink-consumer-group> --describe

# Topic partition count (increase if needed)
docker exec kafka1 kafka-topics --bootstrap-server kafka1:29092 \
  --describe --topic test-throughput
```

---

## 5. Test Topic Setup

```bash
# Create topic with enough partitions for parallelism (e.g. 6 for Flink parallelism 6)
docker exec kafka1 kafka-topics --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 \
  --create --topic test-throughput \
  --partitions 6 \
  --replication-factor 3

# Verify
docker exec kafka1 kafka-topics --bootstrap-server kafka1:29092 \
  --describe --topic test-throughput
```

---

## 6. Sample Test Plan (Copy-Paste)

```
1. Prerequisites
   - Kafka cluster running
   - Flink job deployed and consuming from <topic>
   - Grafana/Prometheus monitoring up

2. Baseline (no load)
   - Record: consumer lag, Flink backpressure, CPU
   - Duration: 2 min

3. Step 1: 5K events/sec
   - Run: ./run-load-from-docker.sh test-throughput 5000 1024 120
   - Monitor: lag, backpressure, throughput
   - Record: max lag, any backpressure

4. Step 2: 10K events/sec
   - Run: ./run-load-from-docker.sh test-throughput 10000 1024 120
   - Same monitoring

5. Step 3: 50K events/sec
   - Run: ./run-load-from-docker.sh test-throughput 50000 1024 120
   - Watch for: lag growth, backpressure

6. Step 4: 100K events/sec (if previous step stable)
   - Run: ./run-load-from-docker.sh test-throughput 100000 1024 120
   - Identify: max sustainable throughput

7. Analysis
   - Max throughput before lag grows: _____ events/sec
   - Bottleneck: [ ] Kafka  [ ] Flink source  [ ] Flink operator  [ ] Sink
   - Recommended parallelism: _____
```

---

## 7. PromQL Queries for Grafana Explore

**Throughput (messages/sec):**
```promql
sum(rate(kafka_server_brokertopicmetrics_messagesin_total{topic="test-throughput"}[5m]))
```

**Consumer lag (Flink):**
```promql
kafka_consumergroup_lag{job="kafka-exporter",topic="test-throughput"}
```

**Bytes/sec:**
```promql
sum(rate(kafka_server_brokertopicmetrics_bytesin_total{topic="test-throughput"}[5m]))
```

---

## 8. Files in This Directory

| File | Purpose |
|------|---------|
| `scripts/run-load-from-docker.sh` | Single load run |
| `scripts/step-load-test.sh` | Step test (5K→100K) |
| `scripts/kafka-load-generator.sh` | Wrapper (local or Docker) |
| `scripts/json-producer.py` | Custom JSON producer (optional) |
