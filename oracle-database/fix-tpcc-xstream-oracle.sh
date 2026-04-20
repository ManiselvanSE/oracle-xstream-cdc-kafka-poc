#!/bin/bash
# One-shot: supplemental log + grants, then ADD_TABLE_RULES for all nine TPCC tables
# (hammerdb-tpcc-onboard-xstream.sh -> 11-add-table-to-cdc.sql per table).
#
# Requires: sqlplus,
#   ORACLE_SYS_PWD — SYS password (step 1: supplemental log + GRANT; step 2: ADD_TABLE_RULES via 11-add-table-to-cdc.sql)
#     c##xstrmadmin alone often gets ORA-01031 on DBA_CAPTURE / DBMS_XSTREAM_ADM in CDB$ROOT.
#
# Usage (from oracle-database/):
#   export ORACLE_SYS_PWD='<SYS password>'
#   # TNS alias (needs tnsnames.ora):
#   export ORACLE_CONN=RAC_XSTRPDB_POC
#   # OR Easy Connect (no TNS file), CDB or PDB service:
#   CDB service (required for SYS): PDB service (…XSTRPDB…) causes ORA-01031 on ALTER SESSION SET CONTAINER=CDB$ROOT in 11-add-table-to-cdc.sql
#   Use the DB unique-name / CDB service from your listener (see docs/HAMMERDB-RAC-LOAD.md), e.g.:
#   export ORACLE_CONN='//10.0.0.29:1521/DB0312_r8n_phx.sub01061249390.xstrmconnectdb2.oraclevcn.com'
#   ORA-12514: wrong SERVICE_NAME — try DB0312_r8n_phx… not DB0312… if that is what lsnrctl services shows.
#   Optional override: ORACLE_CONN_CDB (defaults to ORACLE_CONN)
#
#   source ./hammerdb-oracle-env.sh   # optional; sets ORACLE_HOME / PATH
#   ./fix-tpcc-xstream-oracle.sh
#
# After Oracle succeeds, on Kafka Connect VM:
#   ./docker/scripts/onboard-tables-deploy-on-vm.sh
#   ./docker/scripts/check-tpcc-kafka-offsets.sh
# (Optional) ONBOARD_VM_IP=<connect-vm> was supported from hammerdb-tpcc-onboard-xstream.sh for remote deploy.
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/hammerdb-oracle-env.sh" ] && . "${SCRIPT_DIR}/hammerdb-oracle-env.sh"
export TNS_ADMIN="${TNS_ADMIN:-${HOME}/oracle/network/admin}"

: "${ORACLE_SYS_PWD:?Set ORACLE_SYS_PWD — SYS AS SYSDBA for supplemental log, GRANTs, and ADD_TABLE_RULES}"
: "${ORACLE_CONN:=RAC_XSTRPDB_POC}"

CONN_SYS="${ORACLE_CONN_CDB:-$ORACLE_CONN}"
# Easy Connect to PDB service (.../XSTRPDB...) blocks ALTER SESSION SET CONTAINER=CDB$ROOT as SYS; TNS alias names are not validated here.
if [[ "${CONN_SYS}" == //* ]] && echo "${CONN_SYS}" | LC_ALL=C grep -qi xstrpdb; then
  echo "ERROR: SYS must use the CDB database service (e.g. //host:1521/DB0312_r8n_phx....oraclevcn.com), not the PDB XSTRPDB service." >&2
  echo "  hammerdb-tpcc-onboard-xstream.sql uses ALTER SESSION SET CONTAINER = XSTRPDB; 11-add-table-to-cdc.sql needs CDB\$ROOT (DBA_CAPTURE)." >&2
  echo "  Set ORACLE_CONN_CDB=//host:1521/<CDB_SERVICE_FROM_LISTENER> or change ORACLE_CONN (tnsping / lsnrctl services)." >&2
  exit 1
fi

sql_quote_ident() {
  printf '"'
  printf '%s' "$1" | sed 's/"/""/g'
  printf '"'
}

cd "${SCRIPT_DIR}"
echo "Step 1/2: hammerdb-tpcc-onboard-xstream.sql as SYS AS SYSDBA @ ${CONN_SYS} (supplemental log + grants)..."
# c##xstrmadmin cannot ALTER TPCC.* or GRANT to c##cfltuser (ORA-01031). Step 1 must be SYSDBA.
sqlplus -L /nolog <<SQLEOF
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE
CONNECT sys/$(sql_quote_ident "$ORACLE_SYS_PWD")@${CONN_SYS} AS SYSDBA
@hammerdb-tpcc-onboard-xstream.sql
EXIT
SQLEOF

echo "Step 2/2: hammerdb-tpcc-onboard-xstream.sh (XStream rules as SYS AS SYSDBA)..."
ORACLE_SYS_PWD="${ORACLE_SYS_PWD}" ORACLE_CONN="${CONN_SYS}" ORACLE_CONN_CDB="${CONN_SYS}" \
  ./hammerdb-tpcc-onboard-xstream.sh

echo "Done. On Kafka Connect VM (optional): ./docker/scripts/onboard-tables-deploy-on-vm.sh && ./docker/scripts/connector-ensure-tpcc-onboard.sh"
