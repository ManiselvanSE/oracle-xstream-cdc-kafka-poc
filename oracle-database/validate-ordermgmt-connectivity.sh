#!/usr/bin/env bash
# Test sqlplus login as ORDERMGMT (exit 0 on success).
# Usage:
#   ORDMGMT_PWD='...' ORACLE_CONN=RAC_XSTRPDB_POC ./validate-ordermgmt-connectivity.sh
# Env:
#   ORDMGMT_PWD / ORDERMGMT_PWD / ORACLE_PWD — password (required)
#   ORACLE_CONN / ORDERMGMT_TNS — TNS alias or net service (default RAC_XSTRPDB_POC)
#   ORACLE_USER — default ordermgmt
#   TNS_ADMIN — if needed for tnsnames.ora
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || true

ORACLE_USER="${ORACLE_USER:-ordermgmt}"
ORACLE_PWD="${ORDMGMT_PWD:-${ORDERMGMT_PWD:-${ORACLE_PWD:?Set ORDMGMT_PWD (ORDERMGMT password)}}}"
ORACLE_CONN="${ORACLE_CONN:-${ORDERMGMT_TNS:-RAC_XSTRPDB_POC}}"

echo "Validating: ${ORACLE_USER}@${ORACLE_CONN}"

if sqlplus -S /nolog <<SQLEOF
SET HEAD OFF FEED OFF VERIFY OFF PAGES 0
WHENEVER SQLERROR EXIT 1
CONNECT "${ORACLE_USER}"/"${ORACLE_PWD}"@${ORACLE_CONN}
SELECT 'CONNECTIVITY_OK' FROM DUAL;
EXIT;
SQLEOF
then
  echo "OK: ORDERMGMT connectivity validated."
else
  echo "FAILED: ORDERMGMT login or query failed." >&2
  exit 1
fi
