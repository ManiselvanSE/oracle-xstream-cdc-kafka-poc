#!/bin/tclsh
# HammerDB TPROC-C: run workload (after schema exists).
# Mirrors upstream: scripts/tcl/oracle/tprocc/ora_tprocc_run.tcl
# Usage: source hammerdb-oracle-env.sh && hammerdbcli tcl auto hammerdb-tprocc-run-sample.tcl

set tmpdir $::env(TMP)
puts "SETTING CONFIGURATION"
dbset db ora
dbset bm TPC-C

diset connection system_user SYSTEM
diset connection system_password {ConFL#_uent12}
diset connection instance RAC_XSTRPDB_POC

diset tpcc tpcc_user tpcc
diset tpcc tpcc_pass {HammerTpcc9912$$}

diset tpcc ora_driver timed
diset tpcc total_iterations 10000000
diset tpcc rampup 2
diset tpcc duration 5
diset tpcc ora_timeprofile true
diset tpcc allwarehouse true
diset tpcc checkpoint false

loadscript
puts "TEST STARTED"
vuset vu vcpu
vucreate
tcstart
tcstatus
set jobid [ vurun ]
vudestroy
tcstop
puts "TEST COMPLETE"
set of [ open $tmpdir/ora_tprocc w ]
puts $of $jobid
close $of
