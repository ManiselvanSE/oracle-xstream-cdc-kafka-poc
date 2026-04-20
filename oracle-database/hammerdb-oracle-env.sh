# Source before running hammerdb / hammerdbcli:  source ~/.../hammerdb-oracle-env.sh
# Adjust ORACLE_HOME if your Instant Client version differs (rpm -qa | grep instantclient).

export ORACLE_HOME="${ORACLE_HOME:-/usr/lib/oracle/19.29/client64}"
export LD_LIBRARY_PATH="${ORACLE_HOME}/lib:${LD_LIBRARY_PATH:-}"
export ORACLE_LIBRARY="${ORACLE_HOME}/lib/libclntsh.so"
export TNS_ADMIN="${TNS_ADMIN:-${HOME}/oracle/network/admin}"
# Include Instant Client bin (sqlplus, tnsping if oracle-instantclient-tools installed)
export PATH="${ORACLE_HOME}/bin:/opt/HammerDB-5.0:${PATH}"
# HammerDB run script uses $::env(TMP) for job id file
export TMP="${TMP:-/tmp}"
export TEMP="${TEMP:-/tmp}"
