#!/bin/bash
# Run tpcc-cdc-smoke-test.sql as TPCC (PDB). Generates redo on all 9 TPCC tables for CDC verification.
#
# Usage:
#   export TPCC_PASSWORD='<TPCC user password>'
#   source ./hammerdb-oracle-env.sh
#   ./run-tpcc-cdc-smoke-test.sh
#
# Env:
#   TPCC_PASSWORD (required)  — HammerDB TPCC schema password
#   TPCC_USER (optional)      — default TPCC
#   ORACLE_CONN (optional)    — TNS alias to PDB, default RAC_XSTRPDB_POC
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/hammerdb-oracle-env.sh" ] && . "${SCRIPT_DIR}/hammerdb-oracle-env.sh"
export TNS_ADMIN="${TNS_ADMIN:-${HOME}/oracle/network/admin}"

: "${TPCC_PASSWORD:?Set TPCC_PASSWORD to the TPCC schema password (HammerDB tpcc user)}"
: "${TPCC_USER:=TPCC}"
: "${ORACLE_CONN:=RAC_XSTRPDB_POC}"

echo "Running ${SCRIPT_DIR}/tpcc-cdc-smoke-test.sql as ${TPCC_USER}@${ORACLE_CONN} ..."
sqlplus -L "${TPCC_USER}/${TPCC_PASSWORD}@${ORACLE_CONN}" @"${SCRIPT_DIR}/tpcc-cdc-smoke-test.sql"
