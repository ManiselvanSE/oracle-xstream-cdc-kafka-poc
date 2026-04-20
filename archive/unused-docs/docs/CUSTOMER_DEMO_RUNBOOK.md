# Customer Demo Runbook: Oracle CDC + Kafka + HammerDB

This guide is written for fast execution during engineering runs and customer demos.

---

## System Flow (Oracle CDC + HammerDB Load Testing)

### Simple architecture diagram

```text
HammerDB Load
    |
    v
Oracle Database (OLTP writes)
    |
    v
Redo Logs
    |
    v
XStream CDC (capture + outbound)
    |
    v
Kafka Connect (Oracle XStream Source)
    |
    v
Kafka Topics
    |
    v
Consumers + Monitoring (Grafana/Prometheus)
```

### Step-by-step flow (plain language)

1. **HammerDB sends OLTP transactions** (insert/update/delete) to Oracle.
2. **Oracle writes all committed changes to redo logs**.
3. **XStream reads redo logs** and converts changes into CDC events (LCR stream).
4. **Kafka Connect reads XStream stream** and publishes events to Kafka topics.
5. **Consumers read events from Kafka** for downstream processing.
6. **Monitoring tracks throughput and latency** across Oracle, CDC, and Kafka.

---

## How to Start and Stop the Entire PoC

## A) Docker Services

This repo uses **Kafka KRaft mode** (no ZooKeeper required).

### Start

```bash
# From repo root
./docker/scripts/start-docker-cluster.sh

# Optional: with monitoring stack
./docker/scripts/start-docker-cluster-with-monitoring.sh
```

Equivalent direct command:

```bash
docker compose -f docker/docker-compose.yml up -d
```

### Stop

```bash
./docker/scripts/stop-docker-cluster.sh
```

Equivalent direct command:

```bash
docker compose -f docker/docker-compose.yml down
```

---

## B) Oracle + CDC Services

### Oracle DB start/stop

Use your DBA standard controls (RAC example):

```bash
srvctl start database -d <DB_UNIQUE_NAME>
srvctl stop database -d <DB_UNIQUE_NAME>
```

### XStream start/stop

Start/check XStream components:

```bash
sqlplus -L sys/<pwd>@//<host>:1521/<service> as sysdba @oracle-database/09-check-and-start-xstream.sql
```

Safe stop (capture/apply):

```sql
BEGIN
  DBMS_CAPTURE_ADM.STOP_CAPTURE(capture_name => 'CONFLUENT_XOUT1');
  DBMS_APPLY_ADM.STOP_APPLY(apply_name => 'XOUT');
END;
/
```

Drop outbound only when teardown is needed:

```bash
sqlplus -L c##xstrmadmin/<pwd>@//<host>:1521/<service> as sysdba @oracle-database/10-teardown-xstream-outbound.sql
```

### Safe shutdown process

1. Stop HammerDB load.
2. Stop consumers.
3. Stop connector/Kafka stack.
4. Stop XStream capture/apply.
5. Stop Oracle DB (if required).

---

## C) HammerDB Lifecycle

### Start workload

```bash
cd oracle-database
source ./hammerdb-oracle-env.sh
export HDB_MTX_PASS='<ordermgmt_password>'
./hammerdb-mtx-run-production.sh
```

Heavy redo profile:

```bash
cd oracle-database
source ./hammerdb-oracle-env.sh
export HDB_MTX_PASS='<ordermgmt_password>'
./hammerdb-mtx-items-high-redo.sh
```

### Stop workload

```bash
cd oracle-database
./stop-hammerdb-load.sh
```

### Reset test runs

Use one of these based on your test plan:

- rerun load script with a new run window
- reset connector state only when needed (`docker/scripts/connector-recreate-streaming-only.sh`)
- recreate topics for clean replay (`docker/scripts/recreate-tpcc-kafka-topics.sh` or target-topic variant)

---

## D) Correct Startup Order

1. **Oracle Database**
2. **CDC (XStream setup/start)**
3. **Kafka stack (brokers + schema registry)**
4. **Kafka Connect layer**
5. **HammerDB load generation**
6. **Consumers + monitoring**

---

## HammerDB Configuration for Oracle Load Testing

### Why HammerDB is used

HammerDB is used to create repeatable high-volume OLTP load.  
It is useful for stressing Oracle transaction path, redo generation, and CDC behavior.

### Workload type

- **TPC-C style OLTP** for standard benchmarking
- **Custom MTX OLTP inserts** for CDC throughput testing in this PoC

### Schema build steps

```bash
cd oracle-database
source ./hammerdb-oracle-env.sh
hammerdbcli tcl auto ./hammerdb-tprocc-buildschema-sample.tcl
```

### Virtual users setup

Use environment variables in MTX scripts:

- `HDB_MTX_VUS` for fixed user count
- `HDB_MTX_VUS_MAX` for capped auto-scaling
- `HDB_MTX_DURATION_SECONDS` for timed runs

### Oracle connection setup

```bash
cd oracle-database
source ./hammerdb-oracle-env.sh
```

Confirm TNS alias points to PDB service:

```bash
echo "$HDB_MTX_TNS"
```

### Load target explanation

- Generate sustained high transaction volume
- Push Oracle redo subsystem hard
- Observe CDC lag and Kafka ingestion during stress windows

### Tuning parameters

- **virtual users**: increase gradually (for example 16 -> 48 -> 96)
- **ramp-up**: use phased ramp, not immediate max
- **think time**: keep low for stress tests

### Execution steps

1. Start Oracle + XStream.
2. Start Kafka + Connect.
3. Run HammerDB script.
4. Watch Oracle, connector, and Kafka metrics.

### Validation points

- Oracle transaction/redo increase is visible.
- CPU and redo activity increase during run.
- Kafka topic offsets and throughput increase.

---

## How We Achieved XStream CDC Load Testing with 700–800 MB/s Throughput and ~200ms Latency

This section explains the practical approach used for peak stress profile runs.

### A) Load Generation Strategy (HammerDB)

- High virtual user counts for parallel sessions.
- Very low think time to keep sessions busy.
- Continuous OLTP transaction mix.
- Parallel session execution on the load host.
- Stable Oracle connectivity settings (`hammerdb-oracle-env.sh` + TNS).

### B) Oracle Tuning

- Redo logs sized and grouped to reduce switch storm risk.
- SGA/PGA tuned for sustained transaction throughput.
- Commit strategy tuned for high redo generation.
- Index path kept efficient for insert-heavy workloads.
- Redo path monitored continuously (`v$log`, `v$archived_log`).

### C) CDC Optimization (XStream)

- Capture/apply kept in ENABLED state and verified before load.
- Redo capture pipeline kept clean (no repeated stop/start during peak).
- Capture lag minimized by ensuring DB + connector path had enough headroom.
- Batching and buffering on connector side tuned to avoid micro-stalls.

### D) Kafka Pipeline Optimization

- Topic partitioning sized for downstream parallel reads.
- Producer batch tuned (`max.batch.size`, `producer.override.batch.size`).
- Compression enabled (`lz4`) to reduce network and broker pressure.
- Producer latency-throughput balance tuned (`linger.ms`).
- Consumer parallelism aligned with partition count.

### E) End-to-End Performance Result

- Sustained high data generation profile targeting **700–800 MB/s** redo band during peak windows.
- Peak windows held for approximately **~1 minute** at max stress.
- CDC pipeline captured and delivered with near real-time behavior, around **~200 ms** end-to-end latency profile.

### F) Key Success Factors

- Parallelism across load, DB, CDC, and Kafka layers.
- Redo bottleneck reduction at Oracle level.
- Efficient Kafka ingestion configuration.
- Low network overhead between Oracle, Connect, and Kafka.

---

## Oracle CDC Setup (XStream)

### What CDC does (simple)

CDC captures database changes and streams them without full table polling.

### How Oracle captures changes

Oracle writes commits to redo logs. XStream reads those redo records and emits change events.

### How XStream streams to Kafka

XStream outbound server exposes the change stream; Kafka Connect source connector consumes it and writes Kafka records.

### Setup steps

1. Enable Oracle prerequisites (`02-enable-xstream.sql`, `03-supplemental-logging.sql`).
2. Create users/grants (`04-create-xstream-users.sql`).
3. Create outbound (`06-create-outbound-ordermgmt.sql`).
4. Verify/start (`08-verify-xstream-outbound.sql`, `09-check-and-start-xstream.sql`).
5. Deploy connector (`docker/scripts/deploy-connector.sh`).

### Start/stop commands

Start/check:

```bash
sqlplus -L sys/<pwd>@//<host>:1521/<service> as sysdba @oracle-database/09-check-and-start-xstream.sql
```

Stop (operational):

```sql
BEGIN
  DBMS_CAPTURE_ADM.STOP_CAPTURE(capture_name => 'CONFLUENT_XOUT1');
  DBMS_APPLY_ADM.STOP_APPLY(apply_name => 'XOUT');
END;
/
```

### Validation steps

```bash
sqlplus -L "$ORACLE_SYSDBA_CONN" @oracle-database/08-verify-xstream-outbound.sql
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq .
```

---

## Kafka Pipeline Flow

### CDC to Kafka flow

1. Oracle change committed.
2. XStream captures it.
3. Connector reads it.
4. Event is produced to Kafka topic.
5. Consumer processes event.

### Topic structure

Typical topic pattern:

`racdb.<PDB>.<SCHEMA>.<TABLE>`

Example:

`racdb.XSTRPDB.ORDERMGMT.MTX_TRANSACTION_ITEMS`

### Topic creation (if needed)

```bash
./docker/scripts/precreate-topics.sh
```

### Connect configuration (if used)

Connector file:

`xstream-connector/oracle-xstream-rac-docker.json.example`

Deploy:

```bash
./docker/scripts/deploy-connector.sh
```

---

## Architecture Diagram

```text
HammerDB -> Oracle DB -> XStream CDC -> Kafka -> Consumers
```

---

## Validation Checklist

- [ ] Oracle load is active (sessions, CPU, transaction activity)
- [ ] Redo generation increases during test window
- [ ] XStream capture/apply are ENABLED
- [ ] Connector status is RUNNING
- [ ] Kafka topic offsets are increasing
- [ ] Throughput is measured in MB/s
- [ ] End-to-end latency is validated near ~200 ms target
- [ ] Source-to-topic consistency checks pass

---

## Troubleshooting

### 1) HammerDB not generating load

- Check `HDB_MTX_PASS`, TNS alias, Oracle connectivity.
- Run `oracle-database/diagnose-hammerdb-rac-connectivity.sh`.

### 2) CDC lag or capture failure

- Verify XStream capture/apply status.
- Re-run `09-check-and-start-xstream.sql`.
- Check connector logs: `docker logs connect --tail 200`.

### 3) Kafka throughput is low

- Check broker health and partition count.
- Check connector batch/compression settings.
- Confirm topic is receiving writes (offset growth).

### 4) Oracle bottlenecks

- Watch log switch frequency, CPU, and I/O.
- Increase redo log size/groups when switching is too frequent.
- Review SGA/PGA and session pressure.

### 5) Connectivity issues

- Validate Oracle listener reachability from Connect and HammerDB host.
- Validate service name (PDB service, not CDB root only).
- Validate Docker host networking and firewall rules.

---

## Quick Command Block (Demo Operator)

```bash
# 1) Start Kafka stack
./docker/scripts/start-docker-cluster.sh

# 2) Deploy connector
./docker/scripts/deploy-connector.sh

# 3) Verify connector
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq .

# 4) Start HammerDB load
cd oracle-database
source ./hammerdb-oracle-env.sh
export HDB_MTX_PASS='<ordermgmt_password>'
./hammerdb-mtx-run-production.sh

# 5) Stop HammerDB load
./stop-hammerdb-load.sh

# 6) Stop Kafka stack
cd ..
./docker/scripts/stop-docker-cluster.sh
```
