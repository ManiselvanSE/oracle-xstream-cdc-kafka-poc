#!/bin/bash
# Run 08-verify-xstream-outbound.sql without pasting (avoids SQL*Plus line-split errors).
#
# Usage:
#   export ORACLE_SYSDBA_CONN='sys/password@//host:1521/DB0312_r8n_phx....oraclevcn.com AS SYSDBA'
#   ./run-08-verify-xstream-outbound.sh
#
# Wrong (do not split sys/ and password with extra quotes):
#   export ORACLE_SYSDBA_CONN='sys/'mypassword'@//...'   # breaks bash quoting
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="${SCRIPT_DIR}/08-verify-xstream-outbound.sql"
: "${ORACLE_SYSDBA_CONN:?Set ORACLE_SYSDBA_CONN to full sqlplus connect e.g. sys/pwd@//host:1521/svc AS SYSDBA}"
[ -f "$SQL_FILE" ] || { echo "Missing $SQL_FILE" >&2; exit 1; }
exec sqlplus -L "$ORACLE_SYSDBA_CONN" @"$SQL_FILE"
