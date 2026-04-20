# Oracle XStream CDC + Kafka PoC (HammerDB Performance Test)

This PoC demonstrates end-to-end Oracle CDC load testing:

- **700-800 MB/s** data load generation profile for ~1 minute
- **~200 ms** end-to-end latency profile
- Flow: **HammerDB -> Oracle -> XStream CDC -> Kafka -> Consumers**

## Architecture

```text
HammerDB -> Oracle DB -> Redo Logs -> XStream CDC -> Kafka Connect -> Kafka Topics -> Consumers
```

## Quick Start (3-5 steps)

1. **Start full stack**

```bash
./start-all.sh
```

2. **Deploy connector (if not already deployed)**

```bash
./docker/scripts/deploy-connector.sh
```

3. **Run HammerDB load**

```bash
cd oracle-database
source ./hammerdb-oracle-env.sh
export HDB_MTX_PASS='<ordermgmt_password>'
./hammerdb-mtx-run-production.sh
```

4. **Validate status and flow**

```bash
./docker/scripts/verify-cdc-stack.sh
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq .
```

5. **Stop everything**

```bash
./stop-all.sh
```

## Reference scripts (metrics)

- [scripts/reference/README.md](scripts/reference/README.md) — April 16 metrics collection and Grafana helpers (canonical paths match [oracle-xstream-cdc-kafka-poc on GitHub](https://github.com/ManiselvanSE/oracle-xstream-cdc-kafka-poc/tree/main/scripts/reference))

## Core Documentation

- [System flow](docs/system-flow.md)
- [HammerDB setup](docs/hammerdb-setup.md)
- [MTX high-volume load & reproduction (scripts, scaling, CDC latency)](docs/MTX_14M_LOAD_REPRODUCTION_GUIDE.md)
- [Oracle CDC setup](docs/oracle-cdc-setup.md)
- [Validation guide](docs/validation-guide.md)
- [Performance results](docs/performance-results.md)
- [Repo map (active vs archive)](docs/repo-map.md)

## Repository Policy

- Active PoC files are kept clean and minimal.
- Older/unused assets are preserved in `archive/` (no file deletion).
