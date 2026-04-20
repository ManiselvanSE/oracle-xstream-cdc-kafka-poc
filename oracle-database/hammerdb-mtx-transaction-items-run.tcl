#!/bin/tclsh
# =============================================================================
# HammerDB CLI — ORDERMGMT.MTX* load (custom driver; not TPROC-C)
#
# hammerdb-mtx-run-production.sh default: HDB_MTX_MODE=items_only (MTX_TRANSACTION_ITEMS only; max rate path).
# HDB_MTX_MODE=all_mtx: each iteration = one wave into ALL MTX tables (hammerdb-mtx-multitable-wave.sql).
#
#   source hammerdb-oracle-env.sh
#   export HDB_MTX_PASS='<ordermgmt_password>'
#   # optional: HDB_MTX_USER HDB_MTX_TNS HDB_MTX_TOTAL_ITERATIONS HDB_MTX_MODE HDB_MTX_RAISEERROR
#   # optional: HDB_MTX_VUS HDB_MTX_NO_TC (true=skip transaction counter; avoids spurious ORA-28000)
#   hammerdbcli tcl auto hammerdb-mtx-transaction-items-run.tcl 2>&1 | tee mtx-run.log
#
# Or: ./hammerdb-mtx-run-production.sh
#
# total_iterations is per virtual user (same semantics as TPROC-C test mode).
# =============================================================================

if { [info exists ::env(TMP)] } {
  set tmpdir $::env(TMP)
} else {
  set tmpdir /tmp
}

puts "=== HammerDB Oracle CUSTOM: MTX_TRANSACTION_ITEMS (iteration) ==="

foreach {key def} {
  HDB_MTX_USER ordermgmt
  HDB_MTX_TNS RAC_XSTRPDB_POC
  HDB_MTX_TOTAL_ITERATIONS 100000
  HDB_MTX_RAISEERROR false
} {
  if { ![info exists ::env($key)] || $::env($key) eq "" } {
    set ::env($key) $def
  }
}

if { ![info exists ::env(HDB_MTX_PASS)] || $::env(HDB_MTX_PASS) eq "" } {
  puts stderr "ERROR: export HDB_MTX_PASS (ORDERMGMT password)."
  exit 1
}

dbset db ora
# HammerDB requires a benchmark module; workload is NOT TPCC tables — customscript only hits ORDERMGMT.MTX*.
dbset bm TPC-C

# Unused by custom driver but keeps dict consistent with other Oracle scripts
diset connection system_user SYSTEM
diset connection system_password {unused_by_mtx_driver}
diset connection instance $::env(HDB_MTX_TNS)

diset tpcc tpcc_user $::env(HDB_MTX_USER)
diset tpcc tpcc_pass $::env(HDB_MTX_PASS)
diset tpcc ora_driver test
diset tpcc total_iterations $::env(HDB_MTX_TOTAL_ITERATIONS)
diset tpcc keyandthink false
# Match HDB_MTX_RAISEERROR (custom driver uses same flag for oraexec failures).
set _mtx_re false
if { [info exists ::env(HDB_MTX_RAISEERROR)] && [string tolower $::env(HDB_MTX_RAISEERROR)] eq "true" } {
  set _mtx_re true
}
if { $_mtx_re } {
  diset tpcc raiseerror true
} else {
  diset tpcc raiseerror false
}

set here [file dirname [file normalize [info script]]]
# VU workers may not resolve [info script] for customscript; prefer process env (set by hammerdb-mtx-run-production.sh).
if { ![info exists ::env(HDB_MTX_SCRIPT_DIR)] || $::env(HDB_MTX_SCRIPT_DIR) eq "" } {
  set ::env(HDB_MTX_SCRIPT_DIR) $here
}
set mtxscript [file join $here hammerdb-mtx-custom-driver.tcl]
if { ![file exists $mtxscript] } {
  puts stderr "ERROR: Missing custom driver: $mtxscript"
  exit 1
}

customscript $mtxscript

puts "TEST STARTED"

# Optional: HDB_MTX_VUS=N (e.g. 1 for smoke). Default: vcpu (all CPUs).
if { [info exists ::env(HDB_MTX_VUS)] && $::env(HDB_MTX_VUS) ne "" } {
  vuset vu $::env(HDB_MTX_VUS)
} else {
  vuset vu vcpu
}
vucreate

# Transaction counter uses separate Oracle credentials; it often logs ORA-28000 while VUs succeed.
# Default: skip TC (HDB_MTX_NO_TC unset or true). Enable: HDB_MTX_NO_TC=false
set mtx_tc 0
if { [info exists ::env(HDB_MTX_NO_TC)] } {
  set v [string tolower $::env(HDB_MTX_NO_TC)]
  if { $v eq "false" || $v eq "0" || $v eq "no" } {
    set mtx_tc 1
  }
}
if { $mtx_tc } {
  tcstart
  tcstatus
}

set jobid [ vurun ]

vudestroy
if { $mtx_tc } {
  tcstop
}
puts "TEST COMPLETE jobid=$jobid"

set of [ open $tmpdir/ora_mtx_tprocc w ]
puts $of $jobid
close $of
