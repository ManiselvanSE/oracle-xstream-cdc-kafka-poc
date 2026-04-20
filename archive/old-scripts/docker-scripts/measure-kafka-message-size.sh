#!/usr/bin/env bash
# Measure approximate byte size of Kafka record values (JSON from Connect) on the Connect host.
#
# Requires: Docker stack running (kafka1–3 Up), Connect container named "connect".
#
# Usage:
#   ./measure-kafka-message-size.sh [TOPIC] [MAX_MESSAGES]
#
# Examples:
#   ./measure-kafka-message-size.sh racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS 5
#   ./measure-kafka-message-size.sh   # uses default topic below
# All MTX* topics: ./measure-kafka-message-size-mtx-all.sh 5
#
set -euo pipefail
BOOTSTRAP="${BOOTSTRAP_SERVERS:-kafka1:29092,kafka2:29092,kafka3:29092}"
TOPIC="${1:-racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS}"
MAX_MSG="${2:-3}"
CONNECT_CONTAINER="${CONNECT_CONTAINER:-connect}"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONNECT_CONTAINER"; then
  echo "ERROR: container '$CONNECT_CONTAINER' not running." >&2
  exit 1
fi

echo "Bootstrap: $BOOTSTRAP"
echo "Topic:     $TOPIC"
echo "Samples:   $MAX_MSG (value bytes per line; includes trailing newline from console consumer)"
echo ""

tmp=$(mktemp)
err=$(mktemp)
trap 'rm -f "$tmp" "$err"' EXIT

# Clear KAFKA_OPTS: Connect sets a JMX Prometheus javaagent on :9991; child JVMs inherit it and hit "Address already in use".
if ! docker exec "$CONNECT_CONTAINER" env KAFKA_OPTS= kafka-console-consumer \
  --bootstrap-server "$BOOTSTRAP" \
  --topic "$TOPIC" \
  --from-beginning \
  --max-messages "$MAX_MSG" \
  --property print.key=false \
  --property print.value=true \
  --timeout-ms 60000 >"$tmp" 2>"$err"; then
  echo "ERROR: consumer failed. Is Kafka up?  docker ps | grep kafka" >&2
  echo "Start: cd ~/oracle-xstream-cdc-poc/docker && docker compose up -d" >&2
  if [ -s "$err" ]; then
    echo "--- kafka-console-consumer stderr ---" >&2
    cat "$err" >&2
  fi
  exit 1
fi

n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  # Byte length of UTF-8 line (GNU wc -c)
  bytes=$(printf '%s' "$line" | wc -c | tr -d ' ')
  echo "message $n: value ~ ${bytes} bytes (wc -c on line, no extra newline added)"
done <"$tmp"

if [ "$n" -eq 0 ]; then
  echo "No messages read (empty topic or timeout)."
  exit 1
fi
