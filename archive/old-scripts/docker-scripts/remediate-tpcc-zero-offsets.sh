#!/bin/bash
# Remediate TPCC Kafka topics at end offset 0 (no messages).
#
# Typical causes:
#   1) snapshot.mode=no_data — existing rows are never emitted; need NEW DML or initial snapshot
#   2) Oracle — supplemental log / XStream rules / GRANT missing for TPCC
#
# This script (on Connect VM):
#   A) Prints current snapshot.mode + connector task state
#   B) Optionally sets snapshot.mode=initial and restarts (backfill if Oracle has rows)
#   C) Re-checks TPCC topic offsets after a short wait
#
# Usage:
#   ./docker/scripts/remediate-tpcc-zero-offsets.sh              # diagnose only
#   APPLY_INITIAL=yes ./docker/scripts/remediate-tpcc-zero-offsets.sh   # try initial snapshot
#
# For streaming-only proof without backfill, run Oracle DML instead:
#   oracle-database/run-tpcc-cdc-smoke-test.sh or run-tpcc-cdc-sample-inserts.sh
#
set -euo pipefail
: "${CONNECT_REST:=http://localhost:8083}"
: "${CONNECTOR:=oracle-xstream-rac-connector}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== 1) Connector snapshot.mode + task ==="
CFG=$(curl -sf "${CONNECT_REST}/connectors/${CONNECTOR}/config") || { echo "FAIL: GET config"; exit 1; }
echo "$CFG" | jq -r '"snapshot.mode = " + (.["snapshot.mode"] // "null")'
curl -sf "${CONNECT_REST}/connectors/${CONNECTOR}/status" | jq '{connector: .connector.state, task: .tasks[0].state}'

echo ""
echo "=== 2) Current TPCC end offsets (before) ==="
"$SCRIPT_DIR/check-tpcc-kafka-offsets.sh" || true

if [ "${APPLY_INITIAL:-}" = "yes" ]; then
  echo ""
  echo "=== 3) APPLY_INITIAL=yes — setting snapshot.mode=initial and restarting ==="
  command -v jq >/dev/null || { echo "jq required"; exit 1; }
  echo "$CFG" | jq '. + {"snapshot.mode": "initial"}' > /tmp/remediate_conn.json
  HTTP=$(curl -s -o /tmp/remediate_put.txt -w "%{http_code}" -X PUT -H "Content-Type: application/json" \
    -d @/tmp/remediate_conn.json "${CONNECT_REST}/connectors/${CONNECTOR}/config")
  echo "PUT config HTTP $HTTP"
  [ "$HTTP" = "200" ] || { cat /tmp/remediate_put.txt; exit 1; }
  curl -s -X POST "${CONNECT_REST}/connectors/${CONNECTOR}/restart?includeTasks=true" || true
  echo "Waiting 45s for snapshot/streaming to produce records..."
  sleep 45
  echo ""
  echo "=== 4) TPCC end offsets (after) ==="
  "$SCRIPT_DIR/check-tpcc-kafka-offsets.sh" || true
fi

echo ""
echo "=== If offsets are still 0 ==="
echo "Check Connect logs: docker logs connect 2>&1 | grep -i Snapshot"
echo "If you see: SnapshotResult [status=SKIPPED] and 'completed snapshot' — Connect offset storage thinks"
echo "a snapshot already finished. PUT snapshot.mode=initial alone does NOT re-snapshot."
echo ""
echo "Fix (recreate connector = clear offsets; all tables in table.include.list):"
echo "  • Full backfill to Kafka: edit JSON → \\\"snapshot.mode\\\": \\\"initial\\\" then"
echo "      CONFIRM=yes ./docker/scripts/connector-recreate-full-snapshot.sh"
echo "  • Streaming only (no snapshot backfill): backup is automatic; then"
echo "      CONFIRM=yes ./docker/scripts/connector-recreate-streaming-only.sh"
echo ""
echo "• Oracle: verify-tpcc-cdc-prereqs.sql + fix-tpcc-xstream-oracle.sh (XStream rules + grants)."
echo "• Streaming-only proof: run oracle-database/run-tpcc-cdc-smoke-test.sh (TPCC DML)."
echo "• See: docs/HAMMERDB-RAC-LOAD.md §8"
