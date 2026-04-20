#!/usr/bin/env bash
# Reset empty TPCC Kafka topics and redeploy the connector from oracle-xstream-rac-docker.json.
# Ensures table.include.list (including TPCC) and other settings come from your JSON file.
#
# Typical workflow:
#   1) Edit xstream-connector/oracle-xstream-rac-docker.json (or run SYNC_FROM_EXAMPLE=yes).
#   2) Set snapshot.mode as needed (e.g. initial for backfill — see connector-recreate-full-snapshot.sh warning).
#   3) CONFIRM=yes ./docker/scripts/reset-tpcc-kafka-for-connector-json.sh
#
# Env:
#   CONFIRM=yes              required
#   CONNECT_REST=http://localhost:8083
#   CONNECTOR=oracle-xstream-rac-connector
#   CONNECTOR_JSON=xstream-connector/oracle-xstream-rac-docker.json
#   SYNC_FROM_EXAMPLE=yes    run sync-connector-table-include-from-example.sh first
#   DELETE_SCHEMA_TOPIC=yes  also delete __orcl-schema-changes.racdb (full schema history reset)
#   PRECREATE_TOPICS=yes     run recreate-tpcc-kafka-topics.sh after deletes (optional; connector can auto-create)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
: "${CONFIRM:=}"
: "${CONNECT_REST:=http://localhost:8083}"
: "${CONNECTOR:=oracle-xstream-rac-connector}"
: "${CONNECTOR_JSON:=$PROJECT_DIR/xstream-connector/oracle-xstream-rac-docker.json}"
: "${SYNC_FROM_EXAMPLE:=}"
: "${DELETE_SCHEMA_TOPIC:=}"
: "${PRECREATE_TOPICS:=}"

if [ "${CONFIRM}" != "yes" ]; then
  echo "Refusing: set CONFIRM=yes to delete connector + TPCC topics and POST ${CONNECTOR_JSON}."
  exit 1
fi
if [ ! -f "$CONNECTOR_JSON" ]; then
  echo "Missing $CONNECTOR_JSON" >&2
  exit 1
fi

if [ "${SYNC_FROM_EXAMPLE}" = "yes" ]; then
  "$SCRIPT_DIR/sync-connector-table-include-from-example.sh"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq required" >&2
  exit 1
fi
LIST=$(jq -r '.config["table.include.list"] // empty' "$CONNECTOR_JSON")
if [ -z "$LIST" ]; then
  echo "table.include.list is empty in $CONNECTOR_JSON" >&2
  exit 1
fi
if ! echo "$LIST" | grep -qF 'TPCC' && ! echo "$LIST" | grep -qE 'ORDERMGMT\\\.MTX|ORDERMGMT\.MTX'; then
  echo "WARN: table.include.list has neither TPCC nor ORDERMGMT.MTX* — merge from oracle-xstream-rac-docker.json.example." >&2
elif ! echo "$LIST" | grep -qF 'TPCC'; then
  echo "INFO: TPCC not in table.include.list (MTX-only mode OK)."
fi

echo "=== 1) DELETE connector ${CONNECTOR} ==="
curl -s -o /tmp/del_conn.txt -w "%{http_code}" -X DELETE "${CONNECT_REST}/connectors/${CONNECTOR}" || true
echo ""
sleep 3

echo "=== 2) DELETE TPCC Kafka topics ==="
CONFIRM=yes "$SCRIPT_DIR/delete-tpcc-kafka-topics.sh"

if [ "${DELETE_SCHEMA_TOPIC}" = "yes" ]; then
  echo "=== 2b) DELETE schema history topic ==="
  docker exec -e KAFKA_OPTS= kafka1 kafka-topics --bootstrap-server kafka1:29092 \
    --delete --topic __orcl-schema-changes.racdb 2>/dev/null || true
fi

if [ "${PRECREATE_TOPICS}" = "yes" ]; then
  echo "=== 3) PRECREATE TPCC topic shells ==="
  "$SCRIPT_DIR/recreate-tpcc-kafka-topics.sh"
fi

echo "=== 4) POST connector from ${CONNECTOR_JSON} ==="
HTTP=$(curl -s -o /tmp/post_conn.txt -w "%{http_code}" -X POST -H "Content-Type: application/json" \
  --data @"$CONNECTOR_JSON" --max-time 300 "${CONNECT_REST}/connectors")
echo "HTTP $HTTP"
head -c 400 /tmp/post_conn.txt
echo ""
sleep 8
curl -s "${CONNECT_REST}/connectors/${CONNECTOR}/status" | jq . 2>/dev/null || true
