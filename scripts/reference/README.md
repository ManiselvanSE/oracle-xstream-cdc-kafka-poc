# Reference scripts (metrics & load-test helpers)

These scripts support **post-run metrics capture** for the Oracle XStream → Kafka PoC. They are versioned here so clones and GitHub links stay stable.

| Script | Purpose |
|--------|---------|
| `collect-april16-test-metrics.sh` | SSH/SQL/Kafka checks for the April 16, 2026 MTX 30-minute test window (paths and credentials are **environment-specific**—edit before use). |
| `collect-grafana-metrics.sh` | Pull Prometheus/Grafana-style snapshots for a time range (host/dashboard IDs are **environment-specific**). |

## Run from the repository root

```bash
cd oracle-xstream-cdc-poc   # or your clone root

./scripts/reference/collect-april16-test-metrics.sh
./scripts/reference/collect-grafana-metrics.sh "START_MS" "END_MS" "output-dir"
```

## GitHub (canonical paths)

Public repository: [ManiselvanSE/oracle-xstream-cdc-kafka-poc](https://github.com/ManiselvanSE/oracle-xstream-cdc-kafka-poc)

- [collect-april16-test-metrics.sh on `main`](https://github.com/ManiselvanSE/oracle-xstream-cdc-kafka-poc/blob/main/scripts/reference/collect-april16-test-metrics.sh)
- [collect-grafana-metrics.sh on `main`](https://github.com/ManiselvanSE/oracle-xstream-cdc-kafka-poc/blob/main/scripts/reference/collect-grafana-metrics.sh)

The HammerDB MTX driver used by this PoC lives under `oracle-database/hammerdb-mtx-custom-driver.tcl` (see [HammerDB setup](../../docs/hammerdb-setup.md)).
