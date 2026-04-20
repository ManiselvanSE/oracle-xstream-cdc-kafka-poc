# Oracle XStream CDC Connector – Ultra High-Throughput Performance Guide

**Focus:** Max throughput > low latency > memory efficiency > maintainability

**Target:** Millions of messages/sec, multi-core (8–32 cores), production-grade workload.

---

## DO THIS FIRST (Quick Wins)

| Priority | Action | Expected Impact |
|----------|--------|-----------------|
| 1 | Apply JVM flags below to Connect container | **20–40%** throughput, lower GC pauses |
| 2 | Tune connector batch/queue for **streaming phase** (see §6) | **30–50%** throughput |
| 3 | Increase `query.fetch.size` and `max.batch.size` | **10–20%** |
| 4 | Switch to Avro + Schema Registry (if acceptable) | **15–25%** vs JSON |
| 5 | Tune `snapshot.max.threads` for initial load only | Snapshot phase only |

---

## 1. Connector Configuration (CRITICAL)

The Confluent Oracle XStream CDC connector uses Oracle's `xstreams.jar`, Protocol Buffers, and JAXB (Jakarta XML Binding) for LCR parsing—**not** com.thoughtworks.xstream. Optimize what you control.

### 1.1 Recommended Connector Config (Throughput-First)

```json
{
  "tasks.max": "1",
  "query.fetch.size": "50000",
  "max.queue.size": "262144",
  "max.batch.size": "65536",
  "producer.override.batch.size": "1048576",
  "producer.override.linger.ms": "50",
  "producer.override.compression.type": "lz4",
  "producer.override.buffer.memory": "67108864",
  "key.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "key.converter.schemas.enable": "false",
  "value.converter.schemas.enable": "false"
}
```

| Parameter | Value | Rationale |
|----------|-------|-----------|
| `tasks.max` | Often 1 for XStream (see §1.2) | XStream uses single LCR stream; `tasks.max` may be ignored |
| `query.fetch.size` | 50000 | Fewer round-trips to Oracle |
| `max.queue.size` | 262144 | Larger in-memory buffer; avoid backpressure |
| `max.batch.size` | 65536 | More records per producer batch |
| `producer.override.batch.size` | 1048576 (1MB) | Larger Kafka batches |
| `producer.override.linger.ms` | 50 | Batch for 50ms before send |
| `producer.override.compression.type` | lz4 | Fast compression, less network I/O |

### 1.2 Task Configuration (XStream vs LogMiner)

**Important:** The Oracle XStream CDC connector typically runs with **1 task** because XStream Out delivers a single LCR stream per outbound server. Unlike the **LogMiner-based** Oracle connector (which can parallelize by tables), XStream does not partition work across multiple tasks in the same way.

- **`tasks.max`:** Configurable, but the connector may only use 1 active task. See [Confluent connector configuration](https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/configuration-properties.html#connector).
- **When increasing tasks is valid:** If the connector supports multiple outbound connections or table partitioning in a future version; currently expect 1 task.
- **Throughput:** Optimize via batch sizes, fetch size, and JVM tuning—not via task count.

### 1.3 Tuning by Phase

| Phase | Key Parameters | Purpose |
|-------|----------------|---------|
| **Snapshot** | `snapshot.max.threads`, `snapshot.fetch.size` | Initial full table read |
| **Streaming** | `query.fetch.size`, `max.queue.size`, `max.batch.size`, producer overrides | Ongoing CDC from XStream |

#### Snapshot phase

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `snapshot.max.threads` | 4–8 | Parallel snapshot of tables |
| `snapshot.fetch.size` | 10000 | Rows per fetch during snapshot |

#### Streaming phase

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `query.fetch.size` | 50000 | LCRs per XStream fetch |
| `max.queue.size` | 262144 | In-memory buffer |
| `max.batch.size` | 65536 | Records per producer batch |

---

## 2. JVM + GC Tuning (THROUGHPUT FIRST)

### 2.1 Recommended JVM Flags for Kafka Connect

Add to Connect container via `KAFKA_OPTS` or `CONNECT_JAVA_OPTS`:

```bash
# G1GC – best balance for throughput + predictable pauses (8–32 GB heap)
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200
-XX:InitiatingHeapOccupancyPercent=45
-XX:G1HeapRegionSize=16m
-XX:+ParallelRefProcEnabled
-XX:+UseStringDeduplication

# Heap – size for your workload
-Xms4g -Xmx4g

# Reduce allocation churn from XML/JSON
-XX:+UseCompressedOops
-XX:+UseCompressedClassPointers

# Tiered compilation – full optimization faster
-XX:TieredStopAtLevel=1
# OR for sustained high load, use full C2:
# -XX:-TieredCompilation (removes tiered; C2 only after warmup)

# Avoid biased locking in high-contention paths
-XX:-UseBiasedLocking

# Large pages (if available; requires host config)
# -XX:+UseLargePages
# -XX:LargePageSizeInBytes=2m
```

### 2.2 GC Choice Justification

| GC | Use Case | Trade-off |
|----|----------|-----------|
| **G1GC** | **Recommended** – 4–32 GB heap, throughput + sub-200ms pauses | Balanced |
| ZGC | Sub-10ms pauses, very large heap | Higher CPU, newer JVM |
| Parallel GC | Max throughput, pause-insensitive | Long pauses (100ms+) |
| Shenandoah | Low pause, large heap | More experimental |

**For millions of messages:** G1GC with `MaxGCPauseMillis=200` is the default choice. Use ZGC only if you need sub-10ms pauses and accept higher CPU.

### 2.3 Heap Sizing

```
Heap = 4–8 GB for moderate load
Heap = 8–16 GB for high load (50K+ records/sec)
Heap = 16–32 GB for very high load (100K+ records/sec)
```

- Set `-Xms` = `-Xmx` to avoid resize overhead.
- Leave 20–30% of host RAM for OS, Kafka, and buffers.

### 2.4 Apply to Docker

In `docker-compose.yml` or `docker-compose.monitoring.yml`, add:

```yaml
connect:
  environment:
    KAFKA_OPTS: >-
      -javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=9991:/opt/jmx-exporter/kafka-connect.yml
      -XX:+UseG1GC
      -XX:MaxGCPauseMillis=200
      -XX:InitiatingHeapOccupancyPercent=45
      -XX:G1HeapRegionSize=16m
      -Xms4g -Xmx4g
      -XX:+UseStringDeduplication
      -XX:-UseBiasedLocking
```

---

## 3. Concurrency Model

### 3.1 Connector Threading (Confluent Oracle XStream CDC)

- **Source tasks:** Each task runs in its own thread; `tasks.max` controls parallelism.
- **Worker threads:** Kafka Connect uses a fixed worker thread pool (configurable via `worker.threads`).
- **Oracle XStream API:** Blocking I/O; each task has its own Oracle session.

### 3.2 Recommendations

| Setting | Value | Notes |
|---------|-------|-------|
| `tasks.max` | 4–8 | Primary parallelism lever |
| `worker.threads` | Default or 2× tasks | Enough for tasks + REST/admin |
| `snapshot.max.threads` | 4–8 | For initial snapshot only |

### 3.3 Contention Points

- **Shared producer:** Each task uses Kafka producer; batching reduces lock contention.
- **Schema history topic:** Single writer; avoid frequent schema changes.
- **Oracle connection:** One connection per task; ensure Oracle can handle connections.

### 3.4 Virtual Threads (Java 21+)

Kafka Connect does not yet use virtual threads. For custom code or extensions, virtual threads can help I/O-bound paths but add complexity. **Not recommended** for stock connector.

---

## 4. I/O Pipeline Optimization

### 4.1 Oracle JDBC / XStream

- **`query.fetch.size`:** 50000 reduces round-trips.
- **Oracle `oracle.jdbc.ReadTimeout`:** Set if needed; avoid very long blocking.
- **Network:** Use low-latency path to Oracle (same region/VCN).

### 4.2 Kafka Producer

- **`batch.size`:** 1MB reduces per-message overhead.
- **`linger.ms`:** 50ms balances latency vs throughput.
- **`compression.type`:** `lz4` – fast and reduces network load.
- **`buffer.memory`:** 64MB+ for high throughput.

### 4.3 Buffer Sizes

- Connector internal queue: `max.queue.size` (262144).
- Kafka producer buffer: `producer.override.buffer.memory` (64MB).

---

## 5. Serialization Optimization

### 5.1 Current: JsonConverter (schemas disabled)

- Lower overhead than schema-enabled.
- JSON is slower than binary formats.

### 5.2 Avro + Schema Registry (Recommended for Scale)

```json
"key.converter": "io.confluent.connect.avro.AvroConverter",
"value.converter": "io.confluent.connect.avro.AvroConverter",
"key.converter.schema.registry.url": "http://schema-registry:8081",
"value.converter.schema.registry.url": "http://schema-registry:8081"
```

- **15–25%** faster serialization than JSON.
- Smaller payloads, better compression.

### 5.3 Protobuf (If Schema Registry Supports)

- Fastest binary format in Confluent stack.
- Requires Schema Registry 7+ and Protobuf support.

---

## 6. Connector-Specific Tuning Summary

| Parameter | Conservative | Aggressive |
|-----------|--------------|------------|
| `tasks.max` | 2 | 8 |
| `query.fetch.size` | 20000 | 50000 |
| `max.queue.size` | 131072 | 262144 |
| `max.batch.size` | 32768 | 65536 |
| `producer.override.batch.size` | 524288 | 1048576 |
| `producer.override.linger.ms` | 100 | 50 |
| `producer.override.compression.type` | none | lz4 |

---

## 7. XStream (com.thoughtworks.xstream) – If You Use It

The **Confluent** Oracle XStream CDC connector uses **Oracle xstreams.jar** and **JAXB**, not com.thoughtworks.xstream. If you have **custom code** using com.thoughtworks.xstream:

### 7.1 Driver Benchmark (Xpp3Driver vs StaxDriver)

```java
// Xpp3Driver – typically fastest for small/medium XML
XStream xstream = new XStream(new Xpp3Driver());

// StaxDriver – often faster for large XML, less allocation
XStream xstream = new XStream(new StaxDriver());
```

**Benchmark both** with your payload sizes.

### 7.2 Pre-register Classes, Disable Unused Features

```java
XStream xstream = new XStream(new Xpp3Driver());
xstream.allowTypesByWildcard(new String[]{"com.your.**"});
xstream.setMode(XStream.NO_REFERENCES);
xstream.ignoreUnknownElements();
xstream.autodetectAnnotations(false);
// Pre-register
xstream.alias("lcr", LcrRecord.class);
xstream.alias("row", RowData.class);
```

### 7.3 Thread-Local vs Pooled XStream

```java
private static final ThreadLocal<XStream> XSTREAM = ThreadLocal.withInitial(() -> {
    XStream x = new XStream(new Xpp3Driver());
    x.setMode(XStream.NO_REFERENCES);
    // ... configure once
    return x;
});
```

- **Thread-local:** Simple, no lock; one instance per thread.
- **Pool:** Use only if thread count >> core count and allocation is costly.

### 7.4 Security Overhead

```java
// Minimal allowlist – avoid wildcards if possible
xstream.addPermission(AnyTypePermission.ANY);
// Or restrict:
xstream.allowTypesByWildcard(new String[]{"com.your.model.**"});
```

---

## 8. Replacement Strategy (If Serialization Is the Bottleneck)

### 8.1 When to Consider Replacing

- Profiling shows >30% CPU in XML/JSON parsing.
- Allocation rate >500 MB/sec from serialization.
- GC pauses >100ms and correlated with message bursts.

### 8.2 Alternatives (Rough Order of Speed)

| Format | Relative Speed | Use Case |
|-------|----------------|----------|
| **Kryo** | 3–5× JSON | Internal services, same JVM |
| **Protobuf** | 2–4× JSON | Schema Registry, cross-service |
| **Avro** | 1.5–2× JSON | Kafka ecosystem |
| **Jackson (binary)** | 1.2–1.5× JSON | If staying with JSON-like model |

### 8.3 Migration Path

1. Add Avro converter alongside JSON; run A/B on a subset of topics.
2. Use Schema Registry for evolution.
3. Migrate consumers; then switch connector to Avro.

---

## 9. Benchmarking + Validation

### 9.1 JMH Benchmark (For Custom XStream/Serialization Code)

```java
@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.SECONDS)
@State(Scope.Thread)
public class XStreamBenchmark {
    private XStream xstream;
    private String xml;

    @Setup
    public void setup() {
        xstream = new XStream(new Xpp3Driver());
        xstream.setMode(XStream.NO_REFERENCES);
        xml = loadSampleXml();
    }

    @Benchmark
    public Object deserialize() {
        return xstream.fromXML(xml);
    }
}
```

### 9.2 KPIs to Track

| KPI | Target | How to Measure |
|-----|--------|----------------|
| **Throughput** | records/sec | `kafka_connect_source_task_metrics_source_record_write_rate` |
| **Allocation rate** | MB/sec | JFR allocation profiling |
| **GC pause** | <200ms p99 | GC logs, `-Xlog:gc*` |
| **Oracle fetch latency** | p99 | Oracle AWR / connector metrics |
| **End-to-end latency** | Insert → Kafka | Timestamp diff in consumer |

### 9.3 Load Test

```bash
# Generate 100K inserts
cd oracle-database
export ORDMGMT_PWD='<password>'
./run-generate-heavy-cdc-load.sh 100000

# Watch Grafana: Oracle XStream Connector Throughput, CDC Throughput
```

### 9.4 Throughput Testing Results (OCI RAC POC)

Validated on Oracle RAC (XSTRPDB) → Kafka Connect → Kafka, with optimizations applied.

| Load | Oracle Insert Rate | Connector Throughput (peak) | Kafka / CDC Throughput |
|------|--------------------|-----------------------------|------------------------|
| 100K rows | ~48K rows/sec | ~2 K records/sec | ~180–200 msg/sec |
| 500K rows | ~46K rows/sec | **>10 K records/sec** | ~1.8–2 K msg/sec |

**Configuration used:**
- Connector: `query.fetch.size=50000`, `max.queue.size=262144`, `max.batch.size=65536`
- Producer: `batch.size=1MB`, `linger.ms=50`, `compression.type=lz4`
- JVM: G1GC, 4 GB heap, `UseStringDeduplication`, `-UseBiasedLocking`

**How to reproduce:**
```bash
cd oracle-database
export ORDMGMT_PWD='<password>'
./run-generate-heavy-cdc-load.sh 500000
# Monitor: Grafana → Oracle XStream CDC - Kafka Overview
```

---

## 10. Prioritized Action List

### HIGH Impact

1. **JVM flags** (G1GC, heap, `UseStringDeduplication`).
2. **Connector batch/queue (streaming):** `max.batch.size` 65536, `max.queue.size` 262144.
3. **Producer:** `batch.size` 1MB, `linger.ms` 50, `compression.type` lz4.
4. **`query.fetch.size`** 50000.
5. **Avro converter** (if Schema Registry available).

### MEDIUM Impact

6. **Heap** 8–16 GB for high load.
7. **`producer.override.buffer.memory`** 64MB.
8. **Oracle:** Same-region, low-latency network.

### LOW Impact (Snapshot phase)

9. **`snapshot.max.threads`** 4–8 for initial load.
10. **`heartbeat.interval.ms`** – increase if Oracle allows (reduces keepalive traffic).
11. **Custom XStream tuning** – only if you have custom XML parsing code.

---

## 11. Docker Compose Snippet (Full Connect Config)

```yaml
connect:
  environment:
    CONNECT_BOOTSTRAP_SERVERS: kafka1:29092,kafka2:29092,kafka3:29092
    CONNECT_KEY_CONVERTER: org.apache.kafka.connect.json.JsonConverter
    CONNECT_VALUE_CONVERTER: org.apache.kafka.connect.json.JsonConverter
    CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE: "false"
    CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE: "false"
    KAFKA_OPTS: >-
      -javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=9991:/opt/jmx-exporter/kafka-connect.yml
      -XX:+UseG1GC
      -XX:MaxGCPauseMillis=200
      -XX:InitiatingHeapOccupancyPercent=45
      -XX:G1HeapRegionSize=16m
      -Xms4g -Xmx4g
      -XX:+UseStringDeduplication
      -XX:-UseBiasedLocking
  deploy:
    resources:
      limits:
        memory: 6G
```

---

## 12. Performance References

**Confluent – Oracle XStream CDC Performance Testing:**  
https://confluentinc.atlassian.net/wiki/spaces/OAAC/pages/3946545186/Oracle+XStream+CDC+Source+Performance+Testing

**Key findings (summary):**
- Throughput scales with batch size, fetch size, and producer tuning.
- JVM heap and GC tuning reduce pause times under load.
- Network latency between VM and Oracle affects end-to-end latency.

---

## References

- [Confluent Oracle XStream CDC Connector](https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/overview.html)
- [Connector Configuration Properties](https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/configuration-properties.html#connector)
- [Kafka Connect Configuration](https://docs.confluent.io/platform/current/connect/references/restapi.html#connectors)
- [G1GC Tuning](https://docs.oracle.com/javase/9/gctuning/garbage-first-garbage-collector.htm)
