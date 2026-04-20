#!/bin/bash
# Increase replication factor of CDC topics to 3
# Run from project root: ./docker/scripts/increase-rf-to-3.sh

set -e

BOOTSTRAP="kafka1:29092,kafka2:29092,kafka3:29092"
REASSIGN_JSON="/tmp/reassign-rf3.json"

# Build reassignment JSON for all CDC topics (1 partition each, replicas 1,2,3)
echo '{"version":1,"partitions":[' > "$REASSIGN_JSON"
TOPICS=$(docker exec -e KAFKA_OPTS= kafka2 kafka-topics --bootstrap-server $BOOTSTRAP --list 2>/dev/null | grep -E 'racdb|__orcl|__cflt' || true)
FIRST=1
for topic in $TOPICS; do
  [ -z "$topic" ] && continue
  if [ "$FIRST" -eq 1 ]; then
    FIRST=0
  else
    echo -n "," >> "$REASSIGN_JSON"
  fi
  echo -n "{\"topic\":\"$topic\",\"partition\":0,\"replicas\":[1,2,3]}" >> "$REASSIGN_JSON"
done
echo ']}' >> "$REASSIGN_JSON"

echo "Reassignment plan:"
cat "$REASSIGN_JSON" | jq . 2>/dev/null || cat "$REASSIGN_JSON"
echo ""

echo "Executing reassignment..."
# Copy JSON into container and run (kafka-reassign-partitions needs a file path)
docker cp "$REASSIGN_JSON" kafka2:/tmp/reassign-rf3.json
docker exec -e KAFKA_OPTS= kafka2 kafka-reassign-partitions \
  --bootstrap-server $BOOTSTRAP \
  --execute \
  --reassignment-json-file /tmp/reassign-rf3.json

echo "Waiting for reassignment to complete..."
sleep 5
docker exec -e KAFKA_OPTS= kafka2 kafka-reassign-partitions \
  --bootstrap-server $BOOTSTRAP \
  --verify \
  --reassignment-json-file /tmp/reassign-rf3.json

echo "Done. Verifying topic RF..."
docker exec -e KAFKA_OPTS= kafka2 kafka-topics --bootstrap-server $BOOTSTRAP --describe --topic racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS
rm -f "$REASSIGN_JSON"
