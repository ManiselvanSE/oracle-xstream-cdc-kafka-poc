#!/bin/bash
# Run tpcc-cdc-sample-inserts.sql (streaming-mode sample INSERTs for all 9 TPCC tables).
#
# Usage:
#   export TPCC_PASSWORD='<TPCC user password>'
#   source ./hammerdb-oracle-env.sh
#   ./run-tpcc-cdc-sample-inserts.sh
#
# Env: TPCC_USER (default TPCC), ORACLE_CONN (default RAC_XSTRPDB_POC)
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/hammerdb-oracle-env.sh" ] && . "${SCRIPT_DIR}/hammerdb-oracle-env.sh"
export TNS_ADMIN="${TNS_ADMIN:-${HOME}/oracle/network/admin}"

: "${TPCC_PASSWORD:?Set TPCC_PASSWORD to the TPCC schema password}"
: "${TPCC_USER:=TPCC}"
: "${ORACLE_CONN:=RAC_XSTRPDB_POC}"

echo "Running tpcc-cdc-sample-inserts.sql as ${TPCC_USER}@${ORACLE_CONN} ..."
sqlplus -L "${TPCC_USER}/${TPCC_PASSWORD}@${ORACLE_CONN}" @"${SCRIPT_DIR}/tpcc-cdc-sample-inserts.sql"
