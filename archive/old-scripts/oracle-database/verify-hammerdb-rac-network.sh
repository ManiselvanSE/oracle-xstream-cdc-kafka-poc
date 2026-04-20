#!/usr/bin/env bash
# Run ON the HammerDB VM as opc. Exits 0 only if TCP 1521 is reachable to SCAN IPs.
# If this fails, fix OCI security list / NSG (see docs/OCI-HAMMERDB-RAC-1521.md).

set -euo pipefail

SCAN_IPS=(10.0.0.29 10.0.0.91 10.0.0.238)
OK=0
for ip in "${SCAN_IPS[@]}"; do
  if timeout 4 bash -c "echo >/dev/tcp/${ip}/1521" 2>/dev/null; then
    echo "${ip}:1521 OK"
    OK=1
  else
    echo "${ip}:1521 FAIL"
  fi
done

if [[ "$OK" -eq 0 ]]; then
  echo ""
  echo "All SCAN listener checks failed. Add OCI ingress: TCP 1521 from $(hostname -I | awk '{print $1}')/32"
  echo "to the RAC DB subnet security list and any NSG on the DB System."
  echo "See: oracle-xstream-cdc-poc/docs/OCI-HAMMERDB-RAC-1521.md"
  exit 1
fi
exit 0
