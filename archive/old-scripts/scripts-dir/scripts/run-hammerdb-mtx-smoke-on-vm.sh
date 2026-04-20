#!/usr/bin/env bash
# From your Mac: SSH to the HammerDB VM and run stop → unlock ORDERMGMT → small MTX load.
#
# Required (export before running):
#   VM              — host/IP of HammerDB VM
#   HDB_MTX_PASS    — ORDERMGMT password
#
# Required unless SKIP_UNLOCK=1:
#   SYSDBA_PWD      — Oracle SYS password (for ALTER USER ... UNLOCK)
#
# Optional:
#   SKIP_UNLOCK=1   — skip unlock (no SYSDBA_PWD)
#   SSH_KEY         — default: $HOME/Desktop/Mani/ssh-key-2026-03-12.key
#   HDB_MTX_TOTAL_ITERATIONS — default 10
#
# Example:
#   export VM=129.146.31.189
#   export SYSDBA_PWD='...'
#   export HDB_MTX_PASS='...'
#   ./scripts/run-hammerdb-mtx-smoke-on-vm.sh
#
set -euo pipefail
: "${VM:?Set VM (HammerDB host)}"
: "${HDB_MTX_PASS:?Set HDB_MTX_PASS}"
if [ "${SKIP_UNLOCK:-0}" != "1" ]; then
  : "${SYSDBA_PWD:?Set SYSDBA_PWD or SKIP_UNLOCK=1}"
fi
SSH_KEY="${SSH_KEY:-$HOME/Desktop/Mani/ssh-key-2026-03-12.key}"
REMOTE="opc@${VM}"
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no)
if [ ! -f "$SSH_KEY" ]; then
  echo "SSH key not found: $SSH_KEY" >&2
  exit 1
fi

export HDB_MTX_TOTAL_ITERATIONS="${HDB_MTX_TOTAL_ITERATIONS:-10}"

ssh "${SSH_OPTS[@]}" "$REMOTE" bash -s <<EOF
set -euo pipefail
export SKIP_UNLOCK="${SKIP_UNLOCK:-0}"
export HDB_MTX_PASS=$(printf '%q' "$HDB_MTX_PASS")
export HDB_MTX_TOTAL_ITERATIONS="${HDB_MTX_TOTAL_ITERATIONS}"
if [ "\${SKIP_UNLOCK:-0}" != "1" ]; then
  export SYSDBA_PWD=$(printf '%q' "${SYSDBA_PWD:-}")
fi
cd \$HOME/oracle-xstream-cdc-poc/oracle-database
exec ./hammerdb-mtx-stop-unlock-and-smoke.sh
EOF
