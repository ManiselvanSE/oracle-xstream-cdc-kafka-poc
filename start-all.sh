#!/usr/bin/env bash
set -euo pipefail

# Unified PoC startup helper.
# Order:
# 1) Oracle DB
# 2) XStream CDC
# 3) Kafka stack
# 4) Monitoring
# 5) HammerDB load (optional)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== [1/5] Oracle DB startup ==="
if [[ -n "${ORACLE_START_CMD:-}" ]]; then
  echo "Running ORACLE_START_CMD..."
  eval "${ORACLE_START_CMD}"
else
  echo "Skip (set ORACLE_START_CMD to automate DB startup)."
fi

echo "=== [2/5] XStream CDC startup/check ==="
if [[ -n "${ORACLE_SYSDBA_CONN:-}" ]]; then
  sqlplus -L "${ORACLE_SYSDBA_CONN}" @"${ROOT_DIR}/oracle-database/09-check-and-start-xstream.sql"
else
  echo "Skip SQL startup (set ORACLE_SYSDBA_CONN to run 09-check-and-start-xstream.sql)."
fi

echo "=== [3/5] Kafka stack startup ==="
if [[ "${ENABLE_MONITORING:-true}" == "true" ]]; then
  "${ROOT_DIR}/docker/scripts/start-docker-cluster-with-monitoring.sh"
else
  "${ROOT_DIR}/docker/scripts/start-docker-cluster.sh"
fi

echo "=== [4/5] Monitoring startup ==="
if [[ "${ENABLE_MONITORING:-true}" == "true" ]]; then
  echo "Monitoring enabled (Grafana/Prometheus started with stack)."
else
  echo "Monitoring disabled (set ENABLE_MONITORING=true to enable)."
fi

echo "=== [5/5] HammerDB load (optional) ==="
if [[ "${RUN_HAMMERDB:-false}" == "true" ]]; then
  pushd "${ROOT_DIR}/oracle-database" >/dev/null
  source ./hammerdb-oracle-env.sh
  : "${HDB_MTX_PASS:?Set HDB_MTX_PASS before RUN_HAMMERDB=true}"
  ./hammerdb-mtx-run-production.sh
  popd >/dev/null
else
  echo "Skip (set RUN_HAMMERDB=true to auto-start load)."
fi

echo "=== PoC startup flow complete ==="
