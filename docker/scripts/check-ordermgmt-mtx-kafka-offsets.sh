#!/usr/bin/env bash
# End offsets for racdb.ORDERMGMT.MTX* Kafka topics (Confluent XStream naming).
# Run on Kafka Connect VM after 17-generate-ug-prod-cdc-load.sql (or HammerDB load).
#
# Usage: ./docker/scripts/check-ordermgmt-mtx-kafka-offsets.sh
set -euo pipefail
: "${KAFKA_BS:=kafka1:29092,kafka2:29092,kafka3:29092}"

echo "=== ORDERMGMT.MTX* topic end offsets (latest) ==="
echo "bootstrap: $KAFKA_BS"
echo ""

for t in $(docker exec -e KAFKA_OPTS= kafka1 kafka-topics --bootstrap-server kafka1:29092 --list 2>/dev/null | grep -E '^racdb\.ORDERMGMT\.MTX' | sort); do
  out=$(docker exec -e KAFKA_OPTS= kafka1 kafka-get-offsets --bootstrap-server "$KAFKA_BS" --topic "$t" --time -1 2>/dev/null || true)
  if [ -z "$out" ]; then
    echo "$t  →  (no topic or error)"
  else
    echo "$out"
  fi
done

echo ""
echo "Read messages (example):"
echo "  docker exec -e KAFKA_OPTS= kafka1 kafka-console-consumer --bootstrap-server kafka1:29092 \\"
echo "    --topic racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS --from-beginning --max-messages 3"
