#!/bin/bash
# Add HammerDB TPCC tables to XStream capture/apply (same pattern as ug-prod-onboard-xstream.sh)
# Prereqs: hammerdb-tpcc-onboard-xstream.sql (supplemental log + GRANT SELECT)
#
# ADD_TABLE_RULES needs DBA_CAPTURE in CDB$ROOT — connect SYS to the CDB service (e.g. DB0312_r8n_phx...), not PDB XSTRPDB (ORA-01031). ORA-12514 = wrong SERVICE_NAME.
#   export ORACLE_SYS_PWD='...' ORACLE_CONN='//host:1521/DB0312_r8n_phx....oraclevcn.com'
# Optional: ORACLE_CONN_CDB overrides ORACLE_CONN for SYS when set.
# Legacy (only if c##xstrmadmin has been granted catalog/XStream privileges):
#   export ORACLE_USER='c##xstrmadmin' ORACLE_PWD='...' ORACLE_CONN=...
# Optional: ONBOARD_VM_IP=<connector-vm> to run onboard-tables-deploy-on-vm.sh via SSH

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Instant Client + TNS for sqlplus (same as HammerDB)
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/hammerdb-oracle-env.sh" ] && . "${SCRIPT_DIR}/hammerdb-oracle-env.sh"
export TNS_ADMIN="${TNS_ADMIN:-${HOME}/oracle/network/admin}"
ADD_TABLE="11-add-table-to-cdc.sql"

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

# Prefer TNS alias so you hit the same PDB service as HammerDB (see tnsnames.ora).
# Easy Connect example: //racdb-scan.example.com:1521/XSTRPDB.your.vcn.oraclevcn.com
# Wrong for remote hosts: //localhost:1521/XSTRPDB
: "${ORACLE_CONN:=RAC_XSTRPDB_POC}"
: "${ORACLE_USER:="c##xstrmadmin"}"

CONN_SYS="${ORACLE_CONN_CDB:-$ORACLE_CONN}"
if [ -n "${ORACLE_SYS_PWD:-}" ] && [[ "${CONN_SYS}" == //* ]] && echo "${CONN_SYS}" | LC_ALL=C grep -qi xstrpdb; then
  echo "ERROR: SYS must use the CDB database from lsnrctl services (e.g. //host:1521/DB0312_r8n_phx...), not Easy Connect to PDB XSTRPDB. ORA-12514 = fix SERVICE_NAME." >&2
  exit 1
fi

if [ -n "${ORACLE_SYS_PWD:-}" ]; then
  echo "Adding TPCC tables to XStream (SYS AS SYSDBA @ ${CONN_SYS})..."
else
  : "${ORACLE_PWD:?Set ORACLE_SYS_PWD (recommended) or ORACLE_PWD + ORACLE_USER for XStream admin}"
  echo "Adding TPCC tables to XStream (${ORACLE_USER} @ ${ORACLE_CONN})..."
fi

sql_quote_ident() {
  printf '"'
  printf '%s' "$1" | sed 's/"/""/g'
  printf '"'
}

cd "$SCRIPT_DIR"
ERR=0
run_add_table() {
  local t="$1"
  if [ -n "${ORACLE_SYS_PWD:-}" ]; then
    sqlplus -s /nolog <<SQLEOF
WHENEVER SQLERROR EXIT SQL.SQLCODE
CONNECT sys/$(sql_quote_ident "$ORACLE_SYS_PWD")@${CONN_SYS} AS SYSDBA
SET DEFINE ON
@"${ADD_TABLE}" ${t}
EXIT
SQLEOF
  elif [[ "${ORACLE_PWD}" == *@* ]]; then
    sqlplus -s /nolog <<SQLEOF
WHENEVER SQLERROR EXIT SQL.SQLCODE
CONNECT "${ORACLE_USER}"/"${ORACLE_PWD}"@${ORACLE_CONN}
SET DEFINE ON
@"${ADD_TABLE}" ${t}
EXIT
SQLEOF
  else
    sqlplus -s -L "${ORACLE_USER}/${ORACLE_PWD}@${ORACLE_CONN}" "@${ADD_TABLE}" "$t"
  fi
}
for t in "${TABLES[@]}"; do
  echo "Adding $t..."
  if ! run_add_table "$t"; then
    echo "ERROR: failed to add $t (table may already be in capture — check Oracle output above)" >&2
    ERR=1
  fi
done
if [ "$ERR" -ne 0 ]; then
  echo "WARNING: one or more ADD_TABLE_RULES calls failed. If ORA- says rule already exists, that table was already in capture; otherwise fix Oracle errors and re-run."
fi

echo ""
if [ -n "${ONBOARD_VM_IP:-}" ]; then
  echo "Running onboard-tables-deploy-on-vm.sh on $ONBOARD_VM_IP..."
  ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "opc@${ONBOARD_VM_IP}" \
    "cd ~/oracle-xstream-cdc-poc 2>/dev/null || cd /home/opc/oracle-xstream-cdc-poc && ./docker/scripts/onboard-tables-deploy-on-vm.sh" \
    || echo "SSH failed - run onboard-tables-deploy-on-vm.sh manually on VM"
else
  echo "Next: on the Kafka Connect VM, from repo root:"
  echo "  ./docker/scripts/onboard-tables-deploy-on-vm.sh"
  echo "  ./docker/scripts/connector-ensure-tpcc-onboard.sh"
  echo "  ./docker/scripts/validate-tpcc-cdc-pipeline.sh"
  echo "Or: ONBOARD_VM_IP=<ip> $0"
fi

exit "${ERR:-0}"
