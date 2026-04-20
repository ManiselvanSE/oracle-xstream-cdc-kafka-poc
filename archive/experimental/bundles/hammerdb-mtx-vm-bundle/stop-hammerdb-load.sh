#!/bin/bash
# Stop a running HammerDB CLI load (MTX or TPROC-C scripts).
# Safe to run when no load is active.
set -euo pipefail

# Match: hammerdbcli tcl auto <script.tcl> (HammerDB 4.x/5.x)
pids=$(pgrep -f 'hammerdbcli[[:space:]]+tcl[[:space:]]+auto' || true)
if [ -z "${pids}" ]; then
  echo "No hammerdbcli tcl auto process found."
  exit 0
fi

echo "Sending SIGTERM to: ${pids}"
kill -TERM ${pids} 2>/dev/null || true
sleep 2
still=$(pgrep -f 'hammerdbcli[[:space:]]+tcl[[:space:]]+auto' || true)
if [ -n "${still}" ]; then
  echo "Still running; sending SIGKILL to: ${still}"
  kill -KILL ${still} 2>/dev/null || true
fi
sleep 1
if pgrep -f 'hammerdbcli[[:space:]]+tcl[[:space:]]+auto' >/dev/null 2>&1; then
  echo "WARNING: hammerdbcli still present." >&2
  exit 1
fi
echo "HammerDB load stopped."
