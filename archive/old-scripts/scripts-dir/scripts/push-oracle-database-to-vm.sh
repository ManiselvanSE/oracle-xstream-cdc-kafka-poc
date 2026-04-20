#!/usr/bin/env bash
# Copy oracle-database/ (SQL + HammerDB TCL/scripts) to a VM over SSH.
# Use for: Kafka/Connect VM, Oracle/sqlplus VM, or HammerDB load VM (set VM to that host’s IP/DNS).
#
# Usage (from repo root):
#   VM=137.131.53.98 SSH_KEY=$HOME/Desktop/Mani/ssh-key-2026-03-12.key ./scripts/push-oracle-database-to-vm.sh
# Optional: also copy hammerdb-mtx-vm-bundle/ (minimal HammerDB copy):
#   SYNC_HAMMERDB_BUNDLE=yes VM=<hammerdb_host> SSH_KEY=... ./scripts/push-oracle-database-to-vm.sh
#
# Requires: ssh, scp (rsync optional — used if present for faster sync)
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${VM:?Set VM to the target VM IP or hostname}"
: "${SSH_KEY:=$HOME/Desktop/Mani/ssh-key-2026-03-12.key}"
if [ ! -f "$SSH_KEY" ]; then
  echo "SSH key not found: $SSH_KEY" >&2
  exit 1
fi
if [ ! -d "$ROOT/oracle-database" ]; then
  echo "Missing directory: $ROOT/oracle-database" >&2
  exit 1
fi

REMOTE="opc@${VM}"
DEST="~/oracle-xstream-cdc-poc/oracle-database"
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no)

ssh "${SSH_OPTS[@]}" "$REMOTE" "mkdir -p ~/oracle-xstream-cdc-poc/oracle-database"

if command -v rsync >/dev/null 2>&1; then
  rsync -avz -e "ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no" \
    "$ROOT/oracle-database/" "${REMOTE}:${DEST}/"
else
  scp "${SSH_OPTS[@]}" -r "$ROOT/oracle-database" "${REMOTE}:~/oracle-xstream-cdc-poc/"
fi

echo "Copied $ROOT/oracle-database/ → ${REMOTE}:${DEST}/"

if [ "${SYNC_HAMMERDB_BUNDLE:-}" = "yes" ] && [ -d "$ROOT/hammerdb-mtx-vm-bundle" ]; then
  ssh "${SSH_OPTS[@]}" "$REMOTE" "mkdir -p ~/oracle-xstream-cdc-poc/hammerdb-mtx-vm-bundle"
  if command -v rsync >/dev/null 2>&1; then
    rsync -avz -e "ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no" \
      "$ROOT/hammerdb-mtx-vm-bundle/" "${REMOTE}:~/oracle-xstream-cdc-poc/hammerdb-mtx-vm-bundle/"
  else
    scp "${SSH_OPTS[@]}" -r "$ROOT/hammerdb-mtx-vm-bundle" "${REMOTE}:~/oracle-xstream-cdc-poc/"
  fi
  echo "Also copied hammerdb-mtx-vm-bundle/ → ${REMOTE}:~/oracle-xstream-cdc-poc/hammerdb-mtx-vm-bundle/"
fi

echo "On VM:"
echo "  cd ~/oracle-xstream-cdc-poc/oracle-database"
echo "  source ./hammerdb-oracle-env.sh && export HDB_MTX_PASS='...' && ./hammerdb-mtx-run-production.sh"
