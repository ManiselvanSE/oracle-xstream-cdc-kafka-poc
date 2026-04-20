#!/bin/bash
# Unlock c##xstrmadmin and set password (common user — run in CDB$ROOT).
# Run on a host where sqlplus can reach the database (e.g. Connect VM).
#
# Usage (pick one):
#   A) export ORACLE_SYSDBA_CONN='sys/<sys_password>@//host:1521/<CDB_service> AS SYSDBA'
#   B) export ORACLE_SYS_PWD='<sys_password>' ORACLE_CONN='//host:1521/<CDB_service>'
#   export NEW_XSTRMADMIN_PWD='<new_password_for_c##xstrmadmin>'
#   ./unlock-reset-xstrmadmin.sh
#
# ORA-28007 (password cannot be reused): default RELAX_REUSE=1 relaxes PASSWORD_REUSE_*
# on c##xstrmadmin's profile, then restores (10 / 10 days). Override with
# RELAX_REUSE_RESTORE_MAX, RELAX_REUSE_RESTORE_DAYS. RELAX_REUSE=0 skips relax.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

: "${NEW_XSTRMADMIN_PWD:?Set NEW_XSTRMADMIN_PWD to the new c##xstrmadmin password}"

RELAX_REUSE="${RELAX_REUSE:-1}"
RELAX_REUSE_RESTORE_MAX="${RELAX_REUSE_RESTORE_MAX:-10}"
RELAX_REUSE_RESTORE_DAYS="${RELAX_REUSE_RESTORE_DAYS:-10}"

sql_quote_ident() {
  printf '"'
  printf '%s' "$1" | sed 's/"/""/g'
  printf '"'
}

echo "Altering c##xstrmadmin in CDB\$ROOT (unlock + new password)..."

if [ -n "${ORACLE_SYSDBA_CONN:-}" ]; then
  sqlplus -L "$ORACLE_SYSDBA_CONN" <<EOF
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = CDB\$ROOT;
$(if [ "${RELAX_REUSE}" = "1" ]; then cat <<'PLSQL'
DECLARE
  v_prof VARCHAR2(128);
BEGIN
  SELECT profile INTO v_prof FROM dba_users WHERE username = 'C##XSTRMADMIN';
  EXECUTE IMMEDIATE 'ALTER PROFILE ' || DBMS_ASSERT.SIMPLE_SQL_NAME(v_prof) || ' LIMIT PASSWORD_REUSE_MAX UNLIMITED';
  EXECUTE IMMEDIATE 'ALTER PROFILE ' || DBMS_ASSERT.SIMPLE_SQL_NAME(v_prof) || ' LIMIT PASSWORD_REUSE_TIME UNLIMITED';
END;
/
PLSQL
fi)
ALTER USER c##xstrmadmin ACCOUNT UNLOCK;
ALTER USER c##xstrmadmin IDENTIFIED BY $(sql_quote_ident "$NEW_XSTRMADMIN_PWD");
$(if [ "${RELAX_REUSE}" = "1" ]; then cat <<PLSQL
DECLARE
  v_prof VARCHAR2(128);
BEGIN
  SELECT profile INTO v_prof FROM dba_users WHERE username = 'C##XSTRMADMIN';
  EXECUTE IMMEDIATE 'ALTER PROFILE ' || DBMS_ASSERT.SIMPLE_SQL_NAME(v_prof) ||
    ' LIMIT PASSWORD_REUSE_MAX ${RELAX_REUSE_RESTORE_MAX}';
  EXECUTE IMMEDIATE 'ALTER PROFILE ' || DBMS_ASSERT.SIMPLE_SQL_NAME(v_prof) ||
    ' LIMIT PASSWORD_REUSE_TIME ${RELAX_REUSE_RESTORE_DAYS}';
END;
/
PLSQL
fi)
EXIT
EOF
else
  : "${ORACLE_SYS_PWD:?Set ORACLE_SYS_PWD (SYS) or use ORACLE_SYSDBA_CONN}"
  : "${ORACLE_CONN:?Set ORACLE_CONN e.g. //10.0.0.29:1521/DB0312_r8n_phx....oraclevcn.com}"
  sqlplus -L /nolog <<EOF
WHENEVER SQLERROR EXIT SQL.SQLCODE
CONNECT sys/$(sql_quote_ident "$ORACLE_SYS_PWD")@${ORACLE_CONN} AS SYSDBA
ALTER SESSION SET CONTAINER = CDB\$ROOT;
$(if [ "${RELAX_REUSE}" = "1" ]; then cat <<'PLSQL'
DECLARE
  v_prof VARCHAR2(128);
BEGIN
  SELECT profile INTO v_prof FROM dba_users WHERE username = 'C##XSTRMADMIN';
  EXECUTE IMMEDIATE 'ALTER PROFILE ' || DBMS_ASSERT.SIMPLE_SQL_NAME(v_prof) || ' LIMIT PASSWORD_REUSE_MAX UNLIMITED';
  EXECUTE IMMEDIATE 'ALTER PROFILE ' || DBMS_ASSERT.SIMPLE_SQL_NAME(v_prof) || ' LIMIT PASSWORD_REUSE_TIME UNLIMITED';
END;
/
PLSQL
fi)
ALTER USER c##xstrmadmin ACCOUNT UNLOCK;
ALTER USER c##xstrmadmin IDENTIFIED BY $(sql_quote_ident "$NEW_XSTRMADMIN_PWD");
$(if [ "${RELAX_REUSE}" = "1" ]; then cat <<PLSQL
DECLARE
  v_prof VARCHAR2(128);
BEGIN
  SELECT profile INTO v_prof FROM dba_users WHERE username = 'C##XSTRMADMIN';
  EXECUTE IMMEDIATE 'ALTER PROFILE ' || DBMS_ASSERT.SIMPLE_SQL_NAME(v_prof) ||
    ' LIMIT PASSWORD_REUSE_MAX ${RELAX_REUSE_RESTORE_MAX}';
  EXECUTE IMMEDIATE 'ALTER PROFILE ' || DBMS_ASSERT.SIMPLE_SQL_NAME(v_prof) ||
    ' LIMIT PASSWORD_REUSE_TIME ${RELAX_REUSE_RESTORE_DAYS}';
END;
/
PLSQL
fi)
EXIT
EOF
fi

echo "Done. Update the Kafka Connect connector / oracle-xstream JSON with the same password if it uses c##xstrmadmin."
