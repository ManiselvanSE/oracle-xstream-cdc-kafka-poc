#!/bin/tclsh
# =============================================================================
# HammerDB — Oracle TPROC-C schema BUILD (RAC-ready via TNS SERVICE_NAME)
# Oracle RAC 19c+, HammerDB 4.x/5.x CLI: hammerdbcli tcl auto <this-file>
#
# BEFORE RUN:
#   source hammerdb-oracle-env.sh
#   export TNS_ADMIN=$HOME/oracle/network/admin
#   export ORACLE_SYSTEM_PASSWORD='<SYSTEM_user_password>'
#   export TPCC_PASSWORD='<tpcc_user_password>'
#   sqlplus system@YOUR_TNS_ALIAS   # must work first
#
# Edit: instance (TNS alias), warehouses/VUs.
# =============================================================================

puts "=== HammerDB Oracle TPROC-C: SCHEMA BUILD ==="

if { ![info exists ::env(ORACLE_SYSTEM_PASSWORD)] || $::env(ORACLE_SYSTEM_PASSWORD) eq "" } {
  puts stderr "ERROR: export ORACLE_SYSTEM_PASSWORD (SYSTEM user password)."
  exit 1
}
if { ![info exists ::env(TPCC_PASSWORD)] || $::env(TPCC_PASSWORD) eq "" } {
  puts stderr "ERROR: export TPCC_PASSWORD (tpcc user password for CREATE USER)."
  exit 1
}

# -----------------------------------------------------------------------------
# dbset db ora
#   Select Oracle as the target DBMS (loads Oracle dictionaries/scripts).
# dbset bm TPC-C
#   Benchmark type = TPC-C (OLTP); HammerDB calls this TPROC-C workload.
# -----------------------------------------------------------------------------
dbset db ora
dbset bm TPC-C

# -----------------------------------------------------------------------------
# diset connection system_user / system_password / instance
#   system_* : privileged account used to CREATE USER / tables / indexes for TPC-C.
#              Default in docs is SYSTEM (not SYS AS SYSDBA in standard flows).
#   instance : MUST match tnsnames.ora alias (Net service name), e.g. RAC_XSTRPDB_POC.
#              Password: use {braces} if it contains # (Tcl comment otherwise).
# -----------------------------------------------------------------------------
diset connection system_user SYSTEM
diset connection system_password $::env(ORACLE_SYSTEM_PASSWORD)
diset connection instance RAC_XSTRPDB_POC

# -----------------------------------------------------------------------------
# Scaling: warehouses = logical data volume (TPC-C metric). More => more space/time.
# num_vu = virtual users used during BUILD (parallelism on the LOAD CLIENT).
# Strategy: pilot with small count_ware (e.g. 4-16), then scale for real tests.
# Optional: set vu [ numberOfCPUs ] and warehouse [ expr {$vu * 5} ] like upstream.
# -----------------------------------------------------------------------------
set vu 4
set warehouse 16
diset tpcc count_ware $warehouse
diset tpcc num_vu $vu

# -----------------------------------------------------------------------------
# TPC-C application schema owner (created by build)
# -----------------------------------------------------------------------------
# TPC-C app user password: HammerDB CREATE USER has no PROFILE → user gets DEFAULT (strict verify).
# Must pass verify AND avoid ! (breaks unquoted SQL). Oracle allows $ in passwords — use 2+ $ for "special" rules.
diset tpcc tpcc_user tpcc
diset tpcc tpcc_pass $::env(TPCC_PASSWORD)

# -----------------------------------------------------------------------------
# Tablespace names (defaults often USERS / TEMP — must exist or be creatable)
# tpcc_def_tab  : default tablespace for main tables
# tpcc_def_temp : temp
# tpcc_ol_tab   : order line tablespace (used when partition/hash rules apply)
# -----------------------------------------------------------------------------
diset tpcc tpcc_def_tab USERS
diset tpcc tpcc_def_temp TEMP

# -----------------------------------------------------------------------------
# Partitioning / hash clusters: HammerDB enables for large warehouse counts
# (see upstream ora_tprocc_buildschema.tcl). Keeps build reasonable on big data.
# -----------------------------------------------------------------------------
if { $warehouse >= 200 } {
  diset tpcc partition true
  diset tpcc hash_clusters true
  diset tpcc tpcc_ol_tab USERS
} else {
  diset tpcc partition false
  diset tpcc hash_clusters false
}

# -----------------------------------------------------------------------------
# buildschema
#   Executes DDL + load for TPC-C. Duration grows with count_ware and num_vu.
# -----------------------------------------------------------------------------
puts "SCHEMA BUILD STARTED (warehouses=$warehouse vu=$vu)"
buildschema
puts "SCHEMA BUILD COMPLETED"
