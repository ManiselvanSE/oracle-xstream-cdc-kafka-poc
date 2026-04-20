#!/bin/tclsh
# =============================================================================
# HammerDB — Oracle TPROC-C configuration sanity (no schema build, no workload)
#
# Use AFTER sqlplus user@TNS_ALIAS works. This prints the dictionary HammerDB
# will use for connection settings. Full OCI login to the DB is exercised when
# you run buildschema or loadscript/vurun.
#
#   source hammerdb-oracle-env.sh
#   hammerdbcli tcl auto hammerdb-connection-sanity.tcl 2>&1 | tee hammerdb_sanity.log
#
# Edit: system_user, system_password, instance (TNS alias).
# =============================================================================

puts "=== HammerDB Oracle connection settings (sanity) ==="

dbset db ora
dbset bm TPC-C

# Must match tnsnames.ora service name entry (see tnsping / sqlplus)
diset connection system_user SYSTEM
diset connection system_password {ConFL#_uent12}
diset connection instance RAC_XSTRPDB_POC

puts "=== print dict (verify instance / users match your TNS + sqlplus test) ==="
print dict

puts "=== Done. Next: sqlplus for real login proof; then buildschema or run TCL ==="
