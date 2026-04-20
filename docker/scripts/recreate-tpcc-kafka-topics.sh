#!/usr/bin/env bash
# Pre-create the nine TPCC CDC topics (RF=3, 1 partition) — names match Confluent XStream
# ({topic.prefix}.{schema}.{table} = racdb.TPCC.*). Connect auto-creates these if missing.
#
# Run on Kafka Connect VM from repo root:
#   ./docker/scripts/recreate-tpcc-kafka-topics.sh
set -euo pipefail

: "${BOOTSTRAP:=kafka1:29092}"
KAFKA_TOPICS=(docker exec -e KAFKA_OPTS= kafka1 kafka-topics)

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

echo "Creating TPCC topics (if not exist, replication-factor=3)..."
for topic in "${TOPICS[@]}"; do
  "${KAFKA_TOPICS[@]}" --bootstrap-server "${BOOTSTRAP}" --create --if-not-exists \
    --topic "$topic" --partitions 1 --replication-factor 3 2>/dev/null || true
done
echo "Done."
