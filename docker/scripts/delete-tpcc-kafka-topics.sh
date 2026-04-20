#!/usr/bin/env bash
# Delete Kafka topics for TPCC CDC (empty or not). Matches any topic name that contains
# TPCC under the racdb prefix (e.g. racdb.XSTRPDB.TPCC.* or racdb.TPCC.*).
#
# Run on Kafka Connect VM from repo root:
#   CONFIRM=yes ./docker/scripts/delete-tpcc-kafka-topics.sh
#
# Broker CLI must clear KAFKA_OPTS (JMX exporter bind); uses kafka1:29092 like precreate-topics.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${CONFIRM:=}"
: "${BOOTSTRAP:=kafka1:29092}"

KAFKA_TOPICS=(docker exec -e KAFKA_OPTS= kafka1 kafka-topics)

if [ "${CONFIRM}" != "yes" ]; then
  echo "Refusing: set CONFIRM=yes to delete TPCC-related Kafka topics."
  echo "Lists topics first (dry run):"
  "${KAFKA_TOPICS[@]}" --bootstrap-server "${BOOTSTRAP}" --list 2>/dev/null | grep -E 'racdb\..*TPCC' || true
  exit 1
fi

TOPICS=()
while IFS= read -r line; do
  [ -n "$line" ] && TOPICS+=("$line")
done < <("${KAFKA_TOPICS[@]}" --bootstrap-server "${BOOTSTRAP}" --list 2>/dev/null | grep -E 'racdb\..*TPCC' || true)
if [ "${#TOPICS[@]}" -eq 0 ]; then
  echo "No racdb.*TPCC* topics found."
  exit 0
fi

echo "Deleting ${#TOPICS[@]} topic(s):"
printf '  %s\n' "${TOPICS[@]}"
for t in "${TOPICS[@]}"; do
  "${KAFKA_TOPICS[@]}" --bootstrap-server "${BOOTSTRAP}" --delete --topic "$t" 2>/dev/null || true
done
echo "Done."
