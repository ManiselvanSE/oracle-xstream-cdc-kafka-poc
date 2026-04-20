#!/bin/bash
# Print kafka-get-offsets (latest) for TPCC CDC topics.
#
# Confluent Oracle XStream connector names topics: {topic.prefix}.{schema}.{table}
# e.g. racdb.TPCC.STOCK — not racdb.XSTRPDB.TPCC.* (XSTRPDB.* in precreate-topics.sh was
# a mistaken second naming; the connector does not insert PDB into the Kafka topic name).
#
# Run on Kafka Connect VM after TPCC DML / HammerDB load.
#
# Usage: ./docker/scripts/check-tpcc-kafka-offsets.sh
# Env:
#   KAFKA_BS (default kafka1:29092,kafka2:29092,kafka3:29092)
#   SKIP_CREATE=yes — do not run --create --if-not-exists before listing offsets

set -e
: "${KAFKA_BS:=kafka1:29092,kafka2:29092,kafka3:29092}"
KT=(docker exec -e KAFKA_OPTS= kafka1 kafka-topics)
BS_ADMIN=kafka1:29092

TOPICS=(
  racdb.TPCC.DISTRICT
  racdb.TPCC.CUSTOMER
  racdb.TPCC.HISTORY
  racdb.TPCC.ITEM
  racdb.TPCC.WAREHOUSE
  racdb.TPCC.STOCK
  racdb.TPCC.ORDERS
  racdb.TPCC.NEW_ORDER
  racdb.TPCC.ORDER_LINE
)

if [ "${SKIP_CREATE:-}" != "yes" ]; then
  echo "=== Ensure racdb.TPCC.* topics exist (if-not-exists, RF=3) ==="
  for t in "${TOPICS[@]}"; do
    "${KT[@]}" --bootstrap-server "$BS_ADMIN" --create --if-not-exists \
      --topic "$t" --partitions 1 --replication-factor 3 2>/dev/null || true
  done
  echo ""
fi

echo "=== TPCC topic end offsets (time -1 = latest) ==="
echo "bootstrap: $KAFKA_BS"
echo ""

for t in "${TOPICS[@]}"; do
  out=$(docker exec -e KAFKA_OPTS= kafka1 kafka-get-offsets --bootstrap-server "$KAFKA_BS" --topic "$t" --time -1 2>/dev/null || true)
  if [ -z "$out" ]; then
    echo "$t  →  (no output — topic missing or kafka-get-offsets failed)"
  else
    echo "$out"
  fi
done

echo ""
echo "Format: topic:partition:endOffset."
echo "Offset 0 after load: run oracle-database/tpcc-cdc-smoke-test.sql (touches all 9 tables) or wait for DML on that table."
echo "Connector: curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq ."
