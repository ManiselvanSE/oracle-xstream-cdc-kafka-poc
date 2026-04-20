#!/usr/bin/env bash
# Install HammerDB 5.0 from official GitHub RPM on Oracle Linux 9.
# Run: sudo bash install-hammerdb-ol9.sh
# Doc: ../docs/HAMMERDB-INSTALL.md

set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || exec sudo bash "$0" "$@"

VER="${HAMMERDB_VER:-5.0}"
RPM_URL="https://github.com/TPC-Council/HammerDB/releases/download/v${VER}/hammerdb-${VER}-1.el9.x86_64.rpm"
WORKDIR="${TMPDIR:-/tmp}"

cd "$WORKDIR"
curl -fsSL -o "hammerdb-${VER}-el9.rpm" "$RPM_URL"
dnf install -y "./hammerdb-${VER}-el9.rpm"

MARK="# HammerDB PATH"
for u in opc; do
  H="/home/$u/.bashrc"
  [[ -f "$H" ]] || continue
  if ! grep -qF "$MARK" "$H" 2>/dev/null; then
    {
      echo ""
      echo "$MARK"
      echo 'export PATH="/opt/HammerDB-5.0:${PATH}"'
    } >> "$H"
    chown "$u:$u" "$H"
  fi
done

echo "Installed: $(rpm -q hammerdb)"
echo "/opt/HammerDB-5.0/hammerdbcli -v"
sudo -u opc bash -lc 'export PATH="/opt/HammerDB-5.0:$PATH"; hammerdbcli -v | head -2'
