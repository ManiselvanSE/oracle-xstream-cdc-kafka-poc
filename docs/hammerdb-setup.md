# HammerDB Setup for Oracle Load Testing

## Why HammerDB

HammerDB is used to generate repeatable high-throughput OLTP load for CDC testing.

## Workload used in this PoC

- Primary path: custom MTX transactional load against `ORDERMGMT.MTX_TRANSACTION_ITEMS`
- Optional: TPC-C style scripts for baseline Oracle OLTP behavior

## Setup

```bash
cd oracle-database
source ./hammerdb-oracle-env.sh
```

## Schema build (optional TPC-C baseline)

```bash
hammerdbcli tcl auto ./hammerdb-tprocc-buildschema-sample.tcl
```

## Run MTX load (primary PoC path)

```bash
cd oracle-database
source ./hammerdb-oracle-env.sh
export HDB_MTX_PASS='<ordermgmt_password>'
./hammerdb-mtx-run-production.sh
```

## Run high-redo profile

```bash
cd oracle-database
source ./hammerdb-oracle-env.sh
export HDB_MTX_PASS='<ordermgmt_password>'
./hammerdb-mtx-items-high-redo.sh
```

For a **step-by-step** explanation of how the MTX scripts scale concurrency, how time-bound runs work, and how this relates to **CDC / ~200 ms latency** (vs HammerDB alone), see [MTX_14M_LOAD_REPRODUCTION_GUIDE.md](MTX_14M_LOAD_REPRODUCTION_GUIDE.md).

## Stop load

```bash
cd oracle-database
./stop-hammerdb-load.sh
```

## Tuning knobs

- `HDB_MTX_VUS`: fixed virtual users
- `HDB_MTX_VUS_MAX`: upper cap for auto VU selection
- `HDB_MTX_DURATION_SECONDS`: timed test duration
- think time: keep low for stress tests

## Validation

- Oracle CPU/session activity increases
- redo generation increases
- Kafka topic offsets increase during run
