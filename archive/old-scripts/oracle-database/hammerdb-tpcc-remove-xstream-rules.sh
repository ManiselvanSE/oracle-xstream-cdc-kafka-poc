#!/bin/bash
# Remove HammerDB TPCC tables from XStream capture/apply (DBMS_XSTREAM_ADM.REMOVE_TABLE_RULES).
# Use when the connector fails with: LCR schema differs from table's current schema.
# Then re-onboard: hammerdb-tpcc-onboard-xstream.sh (or 11-add-table-to-cdc.sql per table).
#
# Requires SYS to CDB (same rules as hammerdb-tpcc-onboard-xstream.sh):
#   export ORACLE_SYS_PWD='...' ORACLE_CONN='//host:1521/DB0312_r8n_phx....oraclevcn.com'

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/hammerdb-oracle-env.sh" ] && . "${SCRIPT_DIR}/hammerdb-oracle-env.sh"
export TNS_ADMIN="${TNS_ADMIN:-${HOME}/oracle/network/admin}"
REMOVE_TABLE="12-remove-table-from-cdc.sql"

TABLES=(
  "TPCC.DISTRICT"
  "TPCC.CUSTOMER"
  "TPCC.HISTORY"
  "TPCC.ITEM"
  "TPCC.WAREHOUSE"
  "TPCC.STOCK"
  "TPCC.ORDERS"
  "TPCC.NEW_ORDER"
  "TPCC.ORDER_LINE"
)

: "${ORACLE_CONN:=RAC_XSTRPDB_POC}"
: "${ORACLE_USER:="c##xstrmadmin"}"

CONN_SYS="${ORACLE_CONN_CDB:-$ORACLE_CONN}"
if [ -n "${ORACLE_SYS_PWD:-}" ] && [[ "${CONN_SYS}" == //* ]] && echo "${CONN_SYS}" | LC_ALL=C grep -qi xstrpdb; then
  echo "ERROR: SYS must use the CDB service, not PDB XSTRPDB (ORA-01031)." >&2
  exit 1
fi

if [ -n "${ORACLE_SYS_PWD:-}" ]; then
  echo "Removing TPCC tables from XStream (SYS AS SYSDBA @ ${CONN_SYS})..."
else
  : "${ORACLE_PWD:?Set ORACLE_SYS_PWD (recommended) or ORACLE_PWD + ORACLE_USER}"
  echo "Removing TPCC tables from XStream (${ORACLE_USER} @ ${ORACLE_CONN})..."
fi

sql_quote_ident() {
  printf '"'
  printf '%s' "$1" | sed 's/"/""/g'
  printf '"'
}

cd "$SCRIPT_DIR"
ERR=0
run_remove_table() {
  local t="$1"
  if [ -n "${ORACLE_SYS_PWD:-}" ]; then
    sqlplus -s /nolog <<SQLEOF
WHENEVER SQLERROR EXIT SQL.SQLCODE
CONNECT sys/$(sql_quote_ident "$ORACLE_SYS_PWD")@${CONN_SYS} AS SYSDBA
SET DEFINE ON
@"${REMOVE_TABLE}" ${t}
EXIT
SQLEOF
  elif [[ "${ORACLE_PWD}" == *@* ]]; then
    sqlplus -s /nolog <<SQLEOF
WHENEVER SQLERROR EXIT SQL.SQLCODE
CONNECT "${ORACLE_USER}"/"${ORACLE_PWD}"@${ORACLE_CONN}
SET DEFINE ON
@"${REMOVE_TABLE}" ${t}
EXIT
SQLEOF
  else
    sqlplus -s -L "${ORACLE_USER}/${ORACLE_PWD}@${ORACLE_CONN}" "@${REMOVE_TABLE}" "$t"
  fi
}
for t in "${TABLES[@]}"; do
  echo "Removing $t..."
  if ! run_remove_table "$t"; then
    echo "ERROR: failed to remove $t" >&2
    ERR=1
  fi
done

echo ""
echo "Next:"
echo "  1) Re-add rules: ./hammerdb-tpcc-onboard-xstream.sh"
echo "  2) Connect VM: delete __orcl-schema-changes.racdb topic, CONFIRM=yes connector-recreate-full-snapshot.sh with snapshot.mode=initial"
exit "${ERR:-0}"
