# Performance Results: Oracle XStream CDC PoC

## Target achieved

- **700-800 MB/s** data load generation profile
- sustained peak window: **~1 minute**
- end-to-end CDC latency profile: **~200 ms**

This section explains how the result was achieved in practical, reproducible terms.

---

## 1) HammerDB tuning

- high virtual user counts with phased ramp-up
- low think time to maintain steady transaction pressure
- parallel sessions against Oracle PDB service
- continuous MTX transaction execution with minimal idle gap

Key scripts:

- `oracle-database/hammerdb-mtx-run-production.sh`
- `oracle-database/hammerdb-mtx-items-high-redo.sh`

---

## 2) Oracle tuning

- XStream/GoldenGate replication enabled
- supplemental logging enabled for captured objects
- redo log size/group strategy tuned to avoid switch storms
- memory and I/O paths sized for sustained write pressure
- capture/apply health validated before each test run

Key scripts:

- `oracle-database/02-enable-xstream.sql`
- `oracle-database/03-supplemental-logging.sql`
- `oracle-database/09-check-and-start-xstream.sql`
- `oracle-database/hammerdb-redo-and-size-report.sql`

---

## 3) CDC optimization (XStream)

- outbound server kept stable (`xout`, `CONFLUENT_XOUT1`)
- capture/apply verified as enabled before load
- connector path tuned to reduce queue pressure and lag
- avoid unnecessary restart cycles during peak window

---

## 4) Kafka optimization

- proper topic partitioning for consumer parallelism
- producer batch and linger tuning for throughput/latency balance
- compression (`lz4`) to reduce network and broker overhead
- connector batch/queue sizes tuned for sustained ingestion

Typical connector tuning used:

- `query.fetch.size=50000`
- `max.queue.size=262144`
- `max.batch.size=65536`
- `producer.override.batch.size=1048576`
- `producer.override.linger.ms=50`
- `producer.override.compression.type=lz4`

---

## 5) Repro steps (high level)

1. Start Oracle and XStream capture.
2. Start Kafka/Connect stack.
3. Run high-redo HammerDB profile.
4. Observe throughput and lag metrics during peak window.
5. Validate topic offsets and end-to-end timestamps.

---

## 6) Success factors

- parallelism at load, DB, CDC, and Kafka layers
- careful redo and capture stability management
- connector batching tuned for sustained ingest
- minimal network overhead between Oracle, Connect, and brokers
