#!/usr/bin/env bash
# Verify HammerDB can load Oracle Oratcl (libclntsh).
# Uses "hammerdbcli tcl auto" — required on batch/SSH without a TTY (pipe mode breaks with stty).
#
# Usage:
#   source hammerdb-oracle-env.sh
#   bash /path/to/hammerdb-cli-librarycheck.sh

set -euo pipefail
HAMMERDB_CLI="${HAMMERDB_CLI:-/opt/HammerDB-5.0/hammerdbcli}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBCHK="${SCRIPT_DIR}/hammerdb-librarycheck.tcl"

if [[ ! -f "$HAMMERDB_CLI" ]]; then
  echo "ERROR: HammerDB CLI not found: $HAMMERDB_CLI" >&2
  exit 1
fi
if [[ ! -f "$LIBCHK" ]]; then
  echo "ERROR: Missing $LIBCHK" >&2
  exit 1
fi
if [[ -z "${ORACLE_LIBRARY:-}" ]]; then
  echo "WARN: ORACLE_LIBRARY unset — source hammerdb-oracle-env.sh first." >&2
fi

exec "$HAMMERDB_CLI" tcl auto "$LIBCHK"
