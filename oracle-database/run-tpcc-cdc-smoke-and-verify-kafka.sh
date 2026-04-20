#!/usr/bin/env bash
# Run TPCC CDC verification SQL, then optionally show Kafka topic offsets.
#
# Modes (env TPCC_MODE):
#   smoke (default) — tpcc-cdc-smoke-test.sql: UPDATEs + NEW_ORDER delete/insert (fast, safe on loaded data)
#   insert          — tpcc-cdc-sample-inserts.sql: new warehouse chain INSERTs (full INSERT path, all 9 tables)
#
# Usage (Oracle client host, e.g. HammerDB VM):
#   export TPCC_PASSWORD='<HammerDB TPCC user password>'
#   source ./hammerdb-oracle-env.sh
#   ./run-tpcc-cdc-smoke-and-verify-kafka.sh
#
# Optional — run Kafka offset check on Connect VM over SSH:
#   export KAFKA_VM=opc@137.131.53.98
#   export KAFKA_SSH_KEY=$HOME/Desktop/Mani/ssh-key-2026-03-12.key
#   ./run-tpcc-cdc-smoke-and-verify-kafka.sh
#
# Env:
#   TPCC_PASSWORD (required) — TPCC schema password
#   TPCC_MODE (optional)     — smoke (default) | insert
#   TPCC_USER, ORACLE_CONN   — same as run-tpcc-cdc-smoke-test.sh / run-tpcc-cdc-sample-inserts.sh
#   KAFKA_VM (optional)      — e.g. opc@<connect-vm-ip>
#   KAFKA_SSH_KEY (optional) — SSH private key for KAFKA_VM
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

: "${TPCC_MODE:=smoke}"
case "$TPCC_MODE" in
  insert)
    echo "=== 1) Oracle: tpcc-cdc-sample-inserts.sql (INSERT chain, all 9 TPCC tables) ==="
    ./run-tpcc-cdc-sample-inserts.sh
    ;;
  smoke|*)
    echo "=== 1) Oracle: tpcc-cdc-smoke-test.sql (updates all 9 TPCC tables) ==="
    ./run-tpcc-cdc-smoke-test.sh
    ;;
esac

echo ""
echo "=== 2) Kafka topics (Confluent naming: racdb.TPCC.<TABLE>) ==="
echo "Wait ~30–90s for XStream + Connect, then on the Kafka Connect VM run:"
echo "  cd ~/oracle-xstream-cdc-poc && ./docker/scripts/check-tpcc-kafka-offsets.sh"
echo "Read sample messages:"
echo "  docker exec -e KAFKA_OPTS= kafka1 kafka-console-consumer --bootstrap-server kafka1:29092 \\"
echo "    --topic racdb.TPCC.STOCK --from-beginning --max-messages 2"
echo ""

if [ -n "${KAFKA_VM:-}" ]; then
  KEY="${KAFKA_SSH_KEY:-${HOME}/.ssh/id_rsa}"
  if [ ! -f "$KEY" ]; then
    echo "WARN: KAFKA_SSH_KEY not found ($KEY); skipping SSH. Set KAFKA_SSH_KEY or copy key." >&2
    exit 0
  fi
  echo "=== SSH: $KAFKA_VM — check-tpcc-kafka-offsets.sh ==="
  ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$KAFKA_VM" \
    'cd ~/oracle-xstream-cdc-poc && ./docker/scripts/check-tpcc-kafka-offsets.sh' || true
fi
