#!/usr/bin/env bash
# Run on Oracle Linux 9 HammerDB client (as root or with sudo).
# 1) Installs Oracle Instant Client 19.x + SQL*Plus via dnf
# 2) Adds SCAN entries to /etc/hosts (edit SCAN_IPs if your RAC differs)
# 3) Appends Oracle env to /home/opc/.bashrc
#
# OCI: Allow TCP 1521 from this VM's private IP to RAC *and* to node VIPs.
#     RAC redirects clients to a VIP (e.g. 10.0.0.104:1521) after SCAN connect;
#     opening only SCAN IPs is not enough. Source e.g. 10.0.0.173/32 → DB CIDR.

set -euo pipefail

SCAN_NAME="racdb-scan.sub01061249390.xstrmconnectdb2.oraclevcn.com"
# Resolve from a host that can reach RAC (e.g. mani-xstrm-vm): getent hosts "$SCAN_NAME"
SCAN_IPS="${SCAN_IPS:-10.0.0.91 10.0.0.238 10.0.0.29}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run with: sudo bash $0"
  exit 1
fi

dnf install -y oracle-instantclient-release-el9
dnf install -y oracle-instantclient19.29-basic oracle-instantclient19.29-sqlplus

MARK="# oracle-instantclient-scan (hammerdb-client-setup)"
if ! grep -qF "$MARK" /etc/hosts 2>/dev/null; then
  {
    echo ""
    echo "$MARK"
    for ip in $SCAN_IPS; do
      echo "$ip $SCAN_NAME"
    done
  } >> /etc/hosts
fi

ORACLE_HOME="/usr/lib/oracle/19.29/client64"
PROFILE_MARK="# Oracle Instant Client 19.29 (hammerdb)"
for f in /home/opc/.bashrc; do
  [[ -f "$f" ]] || continue
  if ! grep -qF "$PROFILE_MARK" "$f" 2>/dev/null; then
    {
      echo ""
      echo "$PROFILE_MARK"
      echo "export ORACLE_HOME=$ORACLE_HOME"
      echo 'export LD_LIBRARY_PATH=$ORACLE_HOME/lib:${LD_LIBRARY_PATH:-}'
      echo 'export PATH=$ORACLE_HOME/bin:$PATH'
      echo "# Optional: export TNS_ADMIN=\$HOME/oracle/network/admin if you use tnsnames.ora"
      echo "# Do not set TWO_TASK here — it forces implicit connect to SCAN and breaks troubleshooting."
    } >> "$f"
    chown opc:opc "$f"
  fi
done

mkdir -p /home/opc/oracle/network/admin
chown -R opc:opc /home/opc/oracle

echo "Done. Log out and back in, or: source ~/.bashrc"
echo "Test (after OCI allows 1521 from this host) — use PDB service for app/HammerDB (XSTRPDB...), not only DB unique name:"
echo "  sqlplus -S 'sys/<password>@//racdb-scan.sub01061249390.xstrmconnectdb2.oraclevcn.com:1521/XSTRPDB.sub01061249390.xstrmconnectdb2.oraclevcn.com' AS SYSDBA"
