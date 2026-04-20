# Repository Map (Active vs Archive)

This file shows which parts of the repo are active for the PoC and which parts are preserved in archive.

## Active (used for working PoC)

- `README.md`
- `start-all.sh`
- `stop-all.sh`
- `docker/`
  - `docker-compose.yml`
  - `docker-compose.monitoring.yml`
  - `Dockerfile.connect`
  - `Dockerfile.kafka-jmx`
  - `Dockerfile.schema-registry-jmx`
  - `connect-entrypoint.sh`
  - `scripts/start-docker-cluster.sh`
  - `scripts/start-docker-cluster-with-monitoring.sh`
  - `scripts/stop-docker-cluster.sh`
  - `scripts/deploy-connector.sh`
  - `scripts/precreate-topics.sh`
  - `scripts/verify-cdc-stack.sh`
  - `scripts/install-docker.sh`
- `xstream-connector/`
  - `oracle-xstream-rac-docker.json.example`
  - `oracle-xstream-rac-connector.properties.example`
  - `README.md`
- `oracle-database/` (core CDC + HammerDB scripts)
  - Oracle setup SQL: `01` to `11`, `12-create`, `14`, `15`, `16`
  - XStream validation/start/teardown scripts
  - HammerDB runtime scripts (`hammerdb-mtx-*`, `hammerdb-tprocc-*`, `stop-hammerdb-load.sh`)
  - Validation/report SQL needed for active PoC
- `monitoring/` (active observability stack)
- `scripts/reference/`
  - `collect-april16-test-metrics.sh` — MTX test metrics collection (edit env-specific values before use)
  - `collect-grafana-metrics.sh` — Grafana/Prometheus snapshot helper for a time window
  - `README.md` — run instructions and GitHub links
- `docs/`
  - `system-flow.md`
  - `hammerdb-setup.md`
  - `MTX_14M_LOAD_REPRODUCTION_GUIDE.md` — deep dive: MTX load scripts, scaling, CDC latency context
  - `oracle-cdc-setup.md`
  - `validation-guide.md`
  - `performance-results.md`
  - `repo-map.md`

## Archive (preserved, not part of active run path)

- `archive/old-configs/`  
  old config variants, backups, and local-only config files
- `archive/old-scripts/`  
  scripts not needed for the final PoC runbook flow
- `archive/experimental/`  
  bundles, screenshots, load-testing extras, and previous deliverable packs
- `archive/unused-docs/`  
  previous docs, guides, and legacy README content

## Rule enforced

- No files were deleted.
- Non-core files were moved to `archive/`.
