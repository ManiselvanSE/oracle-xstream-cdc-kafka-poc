#!/usr/bin/env bash
# Measure JSON value byte size for every Kafka topic matching racdb.ORDERMGMT.MTX*
# (same semantics as measure-kafka-message-size.sh per topic).
#
# Usage:
#   ./measure-kafka-message-size-mtx-all.sh [MAX_MESSAGES] [TOPIC_PREFIX]
# Examples:
#   ./measure-kafka-message-size-mtx-all.sh 5
#   ./measure-kafka-message-size-mtx-all.sh 3 racdb.ORDERMGMT.MTX
#
set -euo pipefail
BOOTSTRAP="${BOOTSTRAP_SERVERS:-kafka1:29092,kafka2:29092,kafka3:29092}"
MAX_MSG="${1:-5}"
# Prefix without trailing dot; topics are like racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS
TOPIC_PREFIX="${2:-racdb.ORDERMGMT.MTX}"
CONNECT_CONTAINER="${CONNECT_CONTAINER:-connect}"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONNECT_CONTAINER"; then
  echo "ERROR: container '$CONNECT_CONTAINER' not running." >&2
  exit 1
fi

# Escape dots for grep -E
esc_prefix="${TOPIC_PREFIX//./\\.}"

mapfile -t topics < <(
  docker exec "$CONNECT_CONTAINER" env KAFKA_OPTS= kafka-topics \
    --bootstrap-server "$BOOTSTRAP" --list 2>/dev/null | grep -E "^${esc_prefix}" | sort -u || true
)

if [ "${#topics[@]}" -eq 0 ]; then
  echo "No topics matching prefix '$TOPIC_PREFIX' (kafka-topics --list empty or no match)." >&2
  echo "Check: docker exec $CONNECT_CONTAINER env KAFKA_OPTS= kafka-topics --bootstrap-server $BOOTSTRAP --list | grep MTX" >&2
  exit 1
fi

echo "Bootstrap:     $BOOTSTRAP"
echo "Topic prefix:  $TOPIC_PREFIX*"
echo "Samples/topic: $MAX_MSG (value bytes per line; wc -c)"
echo ""

for TOPIC in "${topics[@]}"; do
  tmp=$(mktemp)
  err=$(mktemp)
  if ! docker exec "$CONNECT_CONTAINER" env KAFKA_OPTS= kafka-console-consumer \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --from-beginning \
    --max-messages "$MAX_MSG" \
    --property print.key=false \
    --property print.value=true \
    --timeout-ms 60000 >"$tmp" 2>"$err"; then
    echo "$TOPIC  —  consumer failed (empty topic, timeout, or error)"
    if [ -s "$err" ]; then
      head -3 "$err" | sed 's/^/    /'
    fi
    rm -f "$tmp" "$err"
    echo ""
    continue
  fi
  if [ ! -s "$tmp" ]; then
    echo "$TOPIC  —  no lines read"
    rm -f "$tmp" "$err"
    echo ""
    continue
  fi
  # min / max / avg bytes (GNU awk)
  stats=$(awk '
    { len = length($0); n++; sum += len; if (n == 1 || len < min) min = len; if (len > max) max = len }
    END { if (n > 0) printf "min=%d avg=%.0f max=%d n=%d", min, sum/n, max, n; else print "n=0" }
  ' "$tmp")
  echo "$TOPIC"
  echo "  $stats  (bytes, UTF-8 line length)"
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    bytes=$(printf '%s' "$line" | wc -c | tr -d ' ')
    echo "    message $n: ~ ${bytes} bytes"
  done <"$tmp"
  rm -f "$tmp" "$err"
  echo ""
done
