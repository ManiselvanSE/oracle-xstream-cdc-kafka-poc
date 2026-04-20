#!/usr/bin/env bash
set -euo pipefail

# Unified PoC shutdown helper.
# Reverse order:
# 1) HammerDB load
# 2) Monitoring/Kafka stack
# 3) XStream CDC
# 4) Oracle DB

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== [1/4] Stop HammerDB load ==="
if [[ -x "${ROOT_DIR}/oracle-database/stop-hammerdb-load.sh" ]]; then
  "${ROOT_DIR}/oracle-database/stop-hammerdb-load.sh" || true
fi

echo "=== [2/4] Stop monitoring + Kafka stack ==="
"${ROOT_DIR}/docker/scripts/stop-docker-cluster.sh" --monitoring || true

echo "=== [3/4] Stop XStream CDC ==="
if [[ -n "${ORACLE_SYSDBA_CONN:-}" ]]; then
  sqlplus -L "${ORACLE_SYSDBA_CONN}" <<'SQL'
BEGIN
  DBMS_CAPTURE_ADM.STOP_CAPTURE(capture_name => 'CONFLUENT_XOUT1');
  DBMS_APPLY_ADM.STOP_APPLY(apply_name => 'XOUT');
END;
/
EXIT
SQL
else
  echo "Skip SQL stop (set ORACLE_SYSDBA_CONN to stop capture/apply)."
fi

echo "=== [4/4] Oracle DB shutdown ==="
if [[ -n "${ORACLE_STOP_CMD:-}" ]]; then
  echo "Running ORACLE_STOP_CMD..."
  eval "${ORACLE_STOP_CMD}"
else
  echo "Skip (set ORACLE_STOP_CMD to automate DB shutdown)."
fi

echo "=== PoC shutdown flow complete ==="
