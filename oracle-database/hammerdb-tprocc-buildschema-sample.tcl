#!/bin/tclsh
# HammerDB TPROC-C: build schema on Oracle RAC.
# Mirrors upstream: scripts/tcl/oracle/tprocc/ora_tprocc_buildschema.tcl
# Usage: source hammerdb-oracle-env.sh && hammerdbcli tcl auto hammerdb-tprocc-buildschema-sample.tcl

puts "SETTING CONFIGURATION"
dbset db ora
dbset bm TPC-C

diset connection system_user SYSTEM
diset connection system_password {ConFL#_uent12}
diset connection instance RAC_XSTRPDB_POC

# Optional: scale warehouses with CPU count like upstream
# set vu [ numberOfCPUs ]
# set warehouse [ expr {$vu * 5} ]
set vu 2
set warehouse 4
diset tpcc count_ware $warehouse
diset tpcc num_vu $vu
diset tpcc tpcc_user tpcc
diset tpcc tpcc_pass {HammerTpcc9912$$}
diset tpcc tpcc_def_tab users
diset tpcc tpcc_def_temp temp
if { $warehouse >= 200 } {
  diset tpcc partition true
  diset tpcc hash_clusters true
  diset tpcc tpcc_ol_tab users
} else {
  diset tpcc partition false
  diset tpcc hash_clusters false
}

puts "SCHEMA BUILD STARTED"
buildschema
puts "SCHEMA BUILD COMPLETED"
