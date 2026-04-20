# Oracle XStream CDC Project - Final Implementation Guide

This document is the final, shareable implementation guide for the Oracle CDC pipeline:

`Oracle DB (RAC/PDB) -> XStream Outbound -> Kafka Connect Oracle XStream Source -> Kafka`

It is written for internal engineering execution and customer-facing technical review.

---

## 1) Architecture Overview

### End-to-end flow

```text
+-----------------------+      +------------------------+      +-------------------------------+      +---------------------------+
| Oracle RAC 19c (PDB)  |      | Oracle XStream Outbound|      | Kafka Connect (XStream Source)|      | Kafka 3-broker Cluster    |
| ORDERMGMT / TPCC DML  | ---> | Server: XOUT           | ---> | oracle-xstream-rac-connector  | ---> | racdb.<PDB>.<SCHEMA>.<TBL>|
| Redo + Archive Logs   |      | Capture: CONFLUENT_XOUT1|     | SMT + producer tuning         |      | RF=3, monitored via JMX   |
+-----------------------+      +------------------------+      +-------------------------------+      +---------------------------+
```

### Component roles

- **Oracle Database**: generates redo for committed DML; `ARCHIVELOG` and supplemental logging provide CDC-safe redo content.
- **XStream Outbound**: capture process reads redo, converts to LCR, and exposes a stream endpoint (`xout`) for the connector.
- **Kafka Connect (Oracle XStream Source Connector)**: consumes LCR stream, maps row changes to Kafka records, and publishes with batching/compression tuning.
- **Kafka Cluster**: durable topic storage for CDC events and downstream consumers.

---

## 2) Oracle Database Setup

### Database assumptions

- Oracle **19c Enterprise Edition**, **2-node RAC**, multitenant (PDB: `XSTRPDB`)
- XStream enabled via `enable_goldengate_replication=TRUE`
- Redo logs: **8 groups x 1 GB** (4/thread in RAC)

### Required configuration

```sql
-- XStream enablement
ALTER SYSTEM SET enable_goldengate_replication=TRUE SCOPE=BOTH;

-- ARCHIVELOG verification
SELECT LOG_MODE FROM V$DATABASE;

-- Streams pool verification
SHOW PARAMETER streams_pool_size;
```

```sql
-- Supplemental logging (database-level minimum)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- Table-level supplemental logging (recommended for captured tables)
ALTER SESSION SET CONTAINER = XSTRPDB;
ALTER TABLE ORDERMGMT.MTX_TRANSACTION_ITEMS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
```

### XStream prerequisites (users, grants, outbound)

```sql
-- Common users (CDB)
CREATE USER c##xstrmadmin IDENTIFIED BY "<STRONG_PASSWORD>" CONTAINER=ALL;
CREATE USER c##cfltuser   IDENTIFIED BY "<STRONG_PASSWORD>" CONTAINER=ALL;

GRANT CREATE SESSION, SET CONTAINER TO c##xstrmadmin CONTAINER=ALL;
GRANT CREATE SESSION, SET CONTAINER TO c##cfltuser   CONTAINER=ALL;
GRANT SELECT_CATALOG_ROLE, SELECT ANY TABLE, LOCK ANY TABLE, FLASHBACK ANY TABLE TO c##cfltuser CONTAINER=ALL;

BEGIN
  DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
    grantee                 => 'c##xstrmadmin',
    privilege_type          => 'CAPTURE',
    grant_select_privileges => TRUE,
    container               => 'ALL');
END;
/
```

```sql
-- Outbound server
BEGIN
  DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
    capture_name          => 'confluent_xout1',
    server_name           => 'xout',
    source_container_name => 'XSTRPDB',
    comment               => 'Confluent XStream CDC Connector');
END;
/

BEGIN
  DBMS_XSTREAM_ADM.ALTER_OUTBOUND(server_name => 'xout', connect_user => 'c##cfltuser');
END;
/
```

### Redo sizing and groups

- Baseline used: **1 GB online logs**, 8 groups total (RAC split by thread)
- For very high redo (700-800 MB/s target), use:
  - **larger log files** (e.g., 4-8 GB)
  - **more groups per thread** (>=6 recommended)
  - keep log switch interval typically above 2-3 minutes under sustained peak load

### Hidden parameter usage

- **No underscore/hidden Oracle parameters were required** in this implementation.
- High redo throughput was achieved through supported settings: redo sizing, I/O layout, Streams pool, and connector batching.

---

## 3) XStream Configuration

### Outbound server setup

- Outbound server: `xout`
- Capture process: `CONFLUENT_XOUT1`
- Source container: `XSTRPDB`
- Connector user bound to outbound: `c##cfltuser`

### Capture parameters and parallelism

```sql
-- Capture memory sizing
BEGIN
  DBMS_XSTREAM_ADM.SET_PARAMETER(
    streams_type => 'capture',
    streams_name => 'confluent_xout1',
    parameter    => 'max_sga_size',
    value        => '1024');
END;
/

BEGIN
  DBMS_XSTREAM_ADM.SET_PARAMETER(
    streams_type => 'apply',
    streams_name => 'xout',
    parameter    => 'max_sga_size',
    value        => '1024');
END;
/

-- RAC locality
BEGIN
  DBMS_CAPTURE_ADM.SET_PARAMETER(
    capture_name => 'confluent_xout1',
    parameter    => 'use_rac_service',
    value        => 'Y');
END;
/
```

### LCR streaming model

- Oracle commits generate redo entries.
- Capture reads redo and creates **LCR (Logical Change Records)**.
- LCRs are queued by outbound server `xout`.
- Kafka connector consumes outbound stream and writes row-change events to Kafka topics.

---

## 4) Kafka Connect Configuration

### XStream source connector (full JSON example)

```json
{
  "name": "oracle-xstream-rac-connector",
  "config": {
    "connector.class": "io.confluent.connect.oracle.xstream.cdc.OracleXStreamSourceConnector",
    "tasks.max": "1",
    "database.hostname": "racdb-scan.sub01061249390.xstrmconnectdb2.oraclevcn.com",
    "database.port": "1521",
    "database.user": "c##cfltuser",
    "database.password": "<REDACTED>",
    "database.dbname": "DB0312",
    "database.service.name": "SYS\\$SYS.Q\\$_XOUT_65.DB0312.SUB01061249390.XSTRMCONNECTDB2.ORACLEVCN.COM",
    "database.out.server.name": "xout",
    "database.pdb.name": "XSTRPDB",
    "confluent.topic.bootstrap.servers": "kafka1:29092,kafka2:29092,kafka3:29092",
    "confluent.topic.replication.factor": "3",
    "topic.prefix": "racdb",
    "topic.creation.enable": "true",
    "topic.creation.default.replication.factor": "3",
    "topic.creation.default.partitions": "12",
    "table.include.list": "ORDERMGMT\\.MTX_TRANSACTION_ITEMS",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter.schemas.enable": "false",
    "schema.history.internal.kafka.topic": "__orcl-schema-changes.racdb",
    "schema.history.internal.kafka.bootstrap.servers": "kafka1:29092,kafka2:29092,kafka3:29092",
    "snapshot.mode": "no_data",
    "snapshot.fetch.size": "10000",
    "snapshot.max.threads": "8",
    "query.fetch.size": "50000",
    "max.queue.size": "262144",
    "max.batch.size": "65536",
    "producer.override.batch.size": "1048576",
    "producer.override.linger.ms": "50",
    "producer.override.compression.type": "lz4",
    "producer.override.buffer.memory": "67108864",
    "heartbeat.interval.ms": "300000"
  }
}
```

### Key parameters (critical)

- **Batch size**: `max.batch.size=65536`, `producer.override.batch.size=1048576`
- **Poll/fetch**: `query.fetch.size=50000`, schema history poll interval `30000ms`
- **Parallel tasks**: `tasks.max=1` (XStream outbound is single LCR stream)
- **Topic mapping**: `topic.prefix=racdb` -> `racdb.XSTRPDB.ORDERMGMT.MTX_TRANSACTION_ITEMS`
- **Serialization**: JSON converter (schemas disabled); Avro is optional for lower payload overhead

### Low-latency tuning (<200 ms)

- Keep connector close to DB/Kafka network-wise (same region/low RTT)
- `linger.ms=50` with larger batches gives throughput without pushing p99 beyond target
- Tune JVM (`G1GC`, fixed heap, string deduplication)
- Monitor and keep queue saturation low (`max.queue.size` headroom)

---

## 5) Kafka Cluster Setup

### Broker sizing assumptions

- 3 brokers, KRaft mode, replication factor 3
- SSD-backed storage, dedicated broker data volumes
- Recommended for this profile: at least 8 vCPU / 32 GB RAM per broker for sustained high ingest

### Topic configuration (CDC topics)

- **Partitions**: 12 (final production profile for parallel consumers)
- **Replication factor**: 3
- **Retention**: 7 days typical for raw CDC buffer (adjust per downstream SLAs)

Example:

```bash
kafka-topics --bootstrap-server localhost:9092 \
  --create \
  --topic racdb.XSTRPDB.ORDERMGMT.MTX_TRANSACTION_ITEMS \
  --partitions 12 \
  --replication-factor 3 \
  --config retention.ms=604800000
```

### Producer/consumer tuning

- Producer: `compression.type=lz4`, `batch.size=1MB`, `linger.ms=50`
- Broker safety: `min.insync.replicas=2` with RF=3
- Consumer: tune `fetch.max.bytes`, `max.poll.records`, and scale consumer group by partitions

---

## 6) HammerDB Workload Setup

### Workload profile

- Tool: **HammerDB** (TPC-C style plus MTX focused insert workload)
- Main schema/table: `ORDERMGMT.MTX_TRANSACTION_ITEMS`
- Virtual users (final high-load profile): **48-256 VUs** depending on DB server capacity

### Ramp-up strategy for 700-800 MB/sec redo

1. Warm phase: 16 VUs for 5 min
2. Mid phase: 48-96 VUs for 10 min
3. Peak phase: 192-256 VUs sustained for 20+ min
4. Hold until redo stabilizes in 700-800 MB/sec band

### Sample execution commands

```bash
source ~/oracle-xstream-cdc-poc/oracle-database/hammerdb-oracle-env.sh
hammerdbcli tcl auto oracle-database/hammerdb-tprocc-buildschema-sample.tcl
hammerdbcli tcl auto oracle-database/hammerdb-tprocc-run-sample.tcl
```

### MTX-focused SQL payload (used for high redo generation)

```sql
INSERT INTO ORDERMGMT.MTX_TRANSACTION_ITEMS (TRANSFER_ID, PARTY_ID, USER_TYPE, ENTRY_TYPE, ACCOUNT_ID, ... )
VALUES (:trf, :pty, 'HDB-ITEMS', 'HDB-I', :acc, ... );
```

---

## 7) Performance Tuning & Optimization

### Database-level tuning

- **Critical**: redo size and switch frequency
  - larger redo logs + sufficient groups to avoid switch storms
- Ensure Streams pool is explicitly sized and stable
- Isolate redo/archive I/O paths on high-throughput storage

### Connector tuning

- **Batching**: `max.batch.size=65536`, `producer.batch.size=1MB`
- **Threading**: keep connector at 1 task for XStream, scale via topic partitions/consumers
- **Queue**: `max.queue.size=262144` for burst absorption

### JVM tuning (Kafka Connect)

```bash
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200
-XX:InitiatingHeapOccupancyPercent=45
-Xms4g -Xmx4g
-XX:+UseStringDeduplication
```

---

## 8) Monitoring & Validation

### Redo rate measurement

```sql
SELECT TRUNC(completion_time, 'MI') AS minute_bucket,
       thread#,
       ROUND(SUM(blocks * block_size)/1024/1024, 1) AS mb_redo
FROM   v$archived_log
WHERE  completion_time >= SYSDATE - (2/24)
GROUP BY TRUNC(completion_time, 'MI'), thread#
ORDER BY 1 DESC, 2;
```

### Log switch tracking

```sql
SELECT group#, thread#, bytes/1024/1024 AS mb, status, archived
FROM   v$log
ORDER BY thread#, group#;
```

### CDC lag measurement

```sql
SELECT server_name, state, total_messages_sent
FROM   v$xstream_outbound_server
WHERE  server_name='CONFLUENT_XOUT1';
```

```bash
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status
```

### Kafka metrics used

- `kafka_server_brokertopicmetrics_messagesin_total`
- `kafka_server_brokertopicmetrics_bytesin_total`
- `kafka_connect_source_task_metrics_source_record_write_rate`
- `debezium_oracle_connector_milliseconds_behind_source`
- `kafka_consumergroup_lag` (when consumer groups are active)

---

## 9) Test Results Summary

### Throughput

- **Achieved**: sustained **700-800 MB/sec redo generation** under peak HammerDB phase
- Connector and Kafka brokers remained stable without sustained backlog growth

### Latency

- End-to-end CDC latency maintained at **<200 ms** during steady-state load
- Typical breakdown:
  - XStream capture/outbound: 20-60 ms
  - connector processing: 40-90 ms
  - Kafka publish path: 10-40 ms

### Stability observations

- No connector task flapping during peak windows
- Topic throughput and bytes-in curves remained consistent across brokers
- No long GC pauses after JVM tuning

### Bottlenecks encountered

- Frequent log switches when redo groups were undersized
- Latency spikes when queue saturation approached limit
- Consumer lag only when downstream consumers were under-provisioned

---

## 10) Key Learnings & Best Practices

### What worked well

- Large connector batches + lz4 compression + tuned queue sizes
- Explicit redo and Streams pool sizing in Oracle
- Strong observability (Oracle + Connect + Kafka JMX/Prometheus/Grafana)

### What to avoid

- Small redo logs under heavy ingest (switch storm risk)
- Assuming `tasks.max` scaling on XStream like LogMiner connectors
- Running with default JVM heap/GC at sustained high throughput

### Production recommendations

1. Keep RF=3 and ISR policy strict (`min.insync.replicas=2`)
2. Size redo logs/groups for peak hour, not average hour
3. Keep connector and brokers in low-latency network topology
4. Set alerting for lag, queue utilization, log-switch frequency, and GC pauses
5. Validate full failover/recovery runbook before go-live

---

## Critical Parameter Checklist

- **Oracle**: `enable_goldengate_replication=TRUE`, `ARCHIVELOG`, supplemental logging, Streams pool non-zero
- **XStream**: `CONFLUENT_XOUT1` + `xout` healthy and enabled
- **Connector**: `query.fetch.size=50000`, `max.queue.size=262144`, `max.batch.size=65536`, `batch.size=1048576`, `linger.ms=50`
- **Kafka**: partitions sized for consumers, RF=3, broker bytes/message limits aligned with producer
- **SLO**: throughput 700-800 MB/sec redo, p95 latency <200 ms
