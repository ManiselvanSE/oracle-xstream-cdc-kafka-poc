#!/bin/bash
# On Connect VM: compare Kafka offsets ORDERMGMT vs TPCC to see if CDC is global or TPCC-only gap.
# HammerDB load + TPCC topics at 0 usually means Oracle XStream rules/grants missing for TPCC,
# or HammerDB not using PDB XSTRPDB — not a Kafka "topic" bug.
#
# Usage: ./docker/scripts/diagnose-tpcc-vs-ordermgmt-kafka.sh
set -e
: "${KAFKA_BS:=kafka1:29092,kafka2:29092,kafka3:29092}"
: "${CONNECT_REST:=http://localhost:8083}"

echo "=== Connector: snapshot.mode + TPCC in table.include.list ==="
curl -sf "${CONNECT_REST}/connectors/oracle-xstream-rac-connector/config" | jq -r '
  "snapshot.mode = " + (.["snapshot.mode"] // "null"),
  "database.pdb.name = " + (.["database.pdb.name"] // "null"),
  (if (.["table.include.list"] // "") | test("TPCC"; "i") then "table.include.list: TPCC present" else "table.include.list: TPCC MISSING" end)
'

echo ""
echo "=== Kafka end offsets (sample): ORDERMGMT vs TPCC ==="
for t in \
  "racdb.XSTRPDB.ORDERMGMT.REGIONS" \
  "racdb.XSTRPDB.ORDERMGMT.MTX_TRANSACTION_ITEMS" \
  "racdb.TPCC.STOCK" \
  "racdb.TPCC.ORDER_LINE"; do
  out=$(docker exec -e KAFKA_OPTS= kafka1 kafka-get-offsets --bootstrap-server "$KAFKA_BS" --topic "$t" --time -1 2>/dev/null || echo "err")
  echo "$out  ($t)"
done

echo ""
echo "=== Connect log (last 80 lines, errors / Oracle / snapshot) ==="
docker logs connect --tail 80 2>&1 | grep -iE 'error|exception|ORA-|snapshot|skipped|TPCC|xstream' || echo "(no matches — see full: docker logs connect --tail 200)"

echo ""
echo "=== Interpretation ==="
echo "• If ORDERMGMT offsets > 0 but TPCC = 0: connector works; run Oracle TPCC XStream onboarding:"
echo "    oracle-database/fix-tpcc-xstream-oracle.sh  (c##xstrmadmin ORACLE_PWD)"
echo "  Then verify: sqlplus ... @oracle-database/verify-tpcc-cdc-prereqs.sql"
echo "• If ALL are 0: broader issue (outbound, service name, pdb.name, or no snapshot/stream)."
echo "• Confirm HammerDB uses PDB service XSTRPDB (not CDB only) — HAMMERDB-RAC-LOAD.md multitenant note."
