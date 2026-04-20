#!/usr/bin/env bash
# Run on the HammerDB VM with sudo.
# OCI instance metadata exposes hostname as e.g. hammerdb-vcn; cloud-init reapplies
# it on every boot. preserve_hostname alone does not override metadata.
# This script installs a systemd oneshot that runs AFTER cloud-final and sets
# the static hostname to "hammerdb".

set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || exec sudo bash "$0" "$@"

NEW_HOST="${1:-hammerdb}"

hostnamectl set-hostname "$NEW_HOST"

mkdir -p /etc/cloud/cloud.cfg.d
printf '%s\n' '#cloud-config' 'preserve_hostname: true' > /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg
if grep -q '^preserve_hostname:' /etc/cloud/cloud.cfg; then
  sed -i 's/^preserve_hostname:.*/preserve_hostname: true/' /etc/cloud/cloud.cfg
fi

# Loopback
if grep -q '^127.0.0.1' /etc/hosts; then
  sed -i "s/^127\\.0\\.0\\.1\\s.*/127.0.0.1 ${NEW_HOST} localhost localhost.localdomain localhost4 localhost4.localdomain4/" /etc/hosts
fi
sed -i "s/hammerdb-vcn/${NEW_HOST}/g" /etc/hosts

cat > /etc/systemd/system/set-hostname-hammerdb.service << UNIT
[Unit]
Description=Override OCI metadata hostname to ${NEW_HOST}
After=cloud-final.service
Wants=cloud-final.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c "/usr/bin/hostnamectl set-hostname ${NEW_HOST} && /bin/sed -i 's/hammerdb-vcn/${NEW_HOST}/g' /etc/hosts"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable set-hostname-hammerdb.service
systemctl start set-hostname-hammerdb.service

echo "Static hostname: $(hostnamectl --static)"
echo "Enabled: set-hostname-hammerdb.service (runs after each boot)"
echo "Optional: rename instance in OCI Console so metadata hostname matches ${NEW_HOST}."
