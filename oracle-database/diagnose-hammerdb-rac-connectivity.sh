#!/usr/bin/env bash
# Run ON the HammerDB Linux VM after Instant Client + (optional) tnsnames.ora.
# Prints a clear verdict: TCP -> TNS -> Oracle libs -> HammerDB Oratcl.
# Does not require database passwords.
#
# Usage:
#   bash diagnose-hammerdb-rac-connectivity.sh
#   SCAN_HOST=racdb-scan.example.com SCAN_IPS="10.0.0.1 10.0.0.2" bash diagnose-hammerdb-rac-connectivity.sh

set -euo pipefail

SCAN_HOST="${SCAN_HOST:-racdb-scan.sub01061249390.xstrmconnectdb2.oraclevcn.com}"
# Default PoC SCAN IPs; override if your SCAN resolves differently
SCAN_IPS="${SCAN_IPS:-10.0.0.29 10.0.0.91 10.0.0.238}"
EXTRA_VIPS="${EXTRA_VIPS:-10.0.0.104 10.0.0.105}"

export ORACLE_HOME="${ORACLE_HOME:-/usr/lib/oracle/19.29/client64}"
export LD_LIBRARY_PATH="${ORACLE_HOME}/lib:${LD_LIBRARY_PATH:-}"
export ORACLE_LIBRARY="${ORACLE_HOME}/lib/libclntsh.so"
export TNS_ADMIN="${TNS_ADMIN:-${HOME}/oracle/network/admin}"
export PATH="${ORACLE_HOME}/bin:/opt/HammerDB-5.0:${PATH}"
TNSPING_BIN="${TNSPING_BIN:-${ORACLE_HOME}/bin/tnsping}"

FAIL=0

echo "=============================================="
echo "HammerDB VM -> Oracle RAC connectivity diagnose"
echo "Client IP: $(hostname -I 2>/dev/null | awk '{print $1}')"
echo "=============================================="

echo ""
echo "=== 1) DNS: SCAN host ==="
if getent hosts "$SCAN_HOST" 2>/dev/null | head -5; then
  :
else
  echo "FAIL: cannot resolve $SCAN_HOST"
  FAIL=1
fi

echo ""
echo "=== 2) TCP port 1521 (must be OK before sqlplus/HammerDB DB login) ==="
tcp_ok=0
for ip in $SCAN_IPS $EXTRA_VIPS; do
  if timeout 4 bash -c "echo >/dev/tcp/${ip}/1521" 2>/dev/null; then
    echo "${ip}:1521 OK"
    tcp_ok=1
  else
    echo "${ip}:1521 FAIL"
  fi
done

if [[ "$tcp_ok" -eq 0 ]]; then
  echo ""
  echo "VERDICT: TCP to listeners FAILED. Fix OCI ingress (TCP 1521) from this VM"
  echo "to SCAN + RAC VIPs, and verify routing/peering. See:"
  echo "  docs/OCI-HAMMERDB-RAC-1521.md"
  FAIL=1
fi

echo ""
echo "=== 3) Oracle Instant Client (libclntsh) ==="
if [[ -e "$ORACLE_HOME/lib/libclntsh.so" ]]; then
  ls -la "$ORACLE_HOME/lib/libclntsh.so"
else
  echo "FAIL: $ORACLE_HOME/lib/libclntsh.so missing"
  FAIL=1
fi

echo ""
echo "=== 4) tnsnames.ora ==="
if [[ -f "$TNS_ADMIN/tnsnames.ora" ]]; then
  echo "Found $TNS_ADMIN/tnsnames.ora"
  grep -E "^\s*[A-Za-z0-9_]+\s*=" "$TNS_ADMIN/tnsnames.ora" | sed 's/ *=.*//' || true
else
  echo "WARN: no $TNS_ADMIN/tnsnames.ora — copy hammerdb-tnsnames.rac.example"
fi

echo ""
echo "=== 5) tnsping (if alias exists) ==="
if [[ -f "$TNS_ADMIN/tnsnames.ora" ]] && [[ -x "${TNSPING_BIN}" ]]; then
  first_alias=$(grep -E "^[A-Za-z0-9_]+\s*=" "$TNS_ADMIN/tnsnames.ora" | head -1 | sed 's/[[:space:]]*=.*//')
  if [[ -n "${first_alias:-}" ]]; then
    "$TNSPING_BIN" "$first_alias" || FAIL=1
  fi
else
  if [[ ! -f "$TNS_ADMIN/tnsnames.ora" ]]; then
    echo "skip (no tnsnames.ora)"
  elif [[ ! -x "${TNSPING_BIN}" ]]; then
    echo "skip (install oracle-instantclient-tools or set TNSPING_BIN; expected ${TNSPING_BIN})"
  fi
fi

echo ""
echo "=== 6) sqlplus network probe (no valid password) ==="
# Expect ORA-12543 if TCP blocked; ORA-12514/1017 if TCP OK but bad service/user
PROBE_HOST="${PROBE_HOST:-10.0.0.29}"
if command -v sqlplus >/dev/null; then
  out=$(echo exit | sqlplus -L "x/x@//${PROBE_HOST}:1521/nosuchservice" 2>&1) || true
  echo "$out" | tail -6
  if echo "$out" | grep -q "ORA-12543"; then
    echo "Probe shows ORA-12543 — network path to listener still blocked or wrong IP."
    FAIL=1
  fi
else
  echo "sqlplus not in PATH"
fi

echo ""
echo "=== 7) HammerDB Oratcl (tcl auto — avoids stty errors) ==="
HAMMERDB_CLI="${HAMMERDB_CLI:-/opt/HammerDB-5.0/hammerdbcli}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBCHK="${SCRIPT_DIR}/hammerdb-librarycheck.tcl"
if [[ -x "$HAMMERDB_CLI" || -f "$HAMMERDB_CLI" ]]; then
  if [[ -f "$LIBCHK" ]]; then
    "$HAMMERDB_CLI" tcl auto "$LIBCHK" 2>&1 | grep -E "Oracle|Oratcl|Error.*Oracle" || true
  else
    echo "WARN: hammerdb-librarycheck.tcl not next to this script; run:"
    echo "  printf 'librarycheck\n' | ...  # wrong; use: hammerdbcli tcl auto hammerdb-librarycheck.tcl"
  fi
else
  echo "HammerDB CLI not found at $HAMMERDB_CLI"
  FAIL=1
fi

echo ""
echo "=============================================="
if [[ "$FAIL" -eq 0 ]]; then
  echo "SUMMARY: Basic checks passed (still test sqlplus with real user@TNS)."
else
  echo "SUMMARY: One or more checks FAILED — fix items above before load tests."
fi
echo "=============================================="
exit "$FAIL"
