#!/usr/bin/env bash
# List Kafka topics whose latest end offsets sum to 0 (no committed messages).
# Run on Kafka Connect VM. Uses one docker exec into kafka1 (fast).
#
# Usage: ./docker/scripts/list-empty-kafka-topics.sh
# Env:   KAFKA_BS (default kafka1:29092,kafka2:29092,kafka3:29092)
set -euo pipefail
: "${KAFKA_BS:=kafka1:29092,kafka2:29092,kafka3:29092}"

echo "=== Topics with end offset 0 on all partitions (empty log) ==="
docker exec -e KAFKA_OPTS= kafka1 bash -lc "
  BS='${KAFKA_BS}'
  for t in \$(kafka-topics --bootstrap-server kafka1:29092 --list 2>/dev/null | sort); do
    out=\$(kafka-get-offsets --bootstrap-server \"\$BS\" --topic \"\$t\" --time -1 2>/dev/null) || continue
    [ -z \"\$out\" ] && continue
    sum=\$(echo \"\$out\" | awk -F: '{s+=\$3} END {print s+0}')
    [ \"\$sum\" = \"0\" ] && echo \"\$t\"
  done
"
