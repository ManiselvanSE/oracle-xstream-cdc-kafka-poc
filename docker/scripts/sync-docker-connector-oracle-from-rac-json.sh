#!/bin/bash
# Copy database.hostname, database.service.name, and database.password from
# oracle-xstream-rac.json into oracle-xstream-rac-docker.json (keeps Docker Kafka bootstrap, transforms, table list).
# Use after ORA-12545 or placeholder YOUR_PASSWORD in docker.json.
#
# Usage (repo root): ./docker/scripts/sync-docker-connector-oracle-from-rac-json.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RAC="$ROOT/xstream-connector/oracle-xstream-rac.json"
DOC="$ROOT/xstream-connector/oracle-xstream-rac-docker.json"
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }
[ -f "$RAC" ] || { echo "Missing $RAC" >&2; exit 1; }
[ -f "$DOC" ] || { echo "Missing $DOC — copy from oracle-xstream-rac-docker.json.example" >&2; exit 1; }

HN=$(jq -r '.config["database.hostname"] // empty' "$RAC")
SN=$(jq -r '.config["database.service.name"] // empty' "$RAC")
PW=$(jq -r '.config["database.password"] // empty' "$RAC")
[ -n "$HN" ] && [ -n "$SN" ] || { echo "Could not read hostname/service from $RAC" >&2; exit 1; }
[ -n "$PW" ] || { echo "Could not read database.password from $RAC" >&2; exit 1; }

BAK="${DOC}.bak.$(date +%Y%m%d%H%M%S)"
cp -a "$DOC" "$BAK"
jq --arg hn "$HN" --arg sn "$SN" --arg pw "$PW" \
  '.config["database.hostname"] = $hn | .config["database.service.name"] = $sn | .config["database.password"] = $pw' "$DOC" > "${DOC}.tmp"
mv "${DOC}.tmp" "$DOC"
echo "Backed up: $BAK"
echo "Updated $DOC: database.hostname, database.service.name, database.password from $RAC"
