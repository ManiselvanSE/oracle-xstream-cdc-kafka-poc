#!/bin/tclsh
# =============================================================================
# Production CDC load — ORDERMGMT.MTX_TRANSACTION_ITEMS by default (no TPCC schema).
#
# This file intentionally does NOT run the HammerDB TPROC-C / TPC-C workload
# (WAREHOUSE, DISTRICT, STOCK, …). It sources the MTX custom driver (items_only
# or all_mtx — see hammerdb-mtx-run-production.sh and hammerdb-mtx-multitable-wave.sql).
#
# For classic TPC-C benchmarking against schema TPCC, use instead:
#   hammerdb-tprocc-run-sample.tcl
#   or upstream: scripts/tcl/oracle/tprocc/ora_tprocc_run.tcl
#
# Usage (same env as hammerdb-mtx-run-production.sh):
#   source hammerdb-oracle-env.sh
#   export HDB_MTX_PASS='<ordermgmt_password>'
#   hammerdbcli tcl auto hammerdb-tprocc-run-production.tcl 2>&1 | tee mtx-run.log
#
# Recommended entry point:
#   ./hammerdb-mtx-run-production.sh
# =============================================================================

puts "=== ORDERMGMT MTX load (hammerdb-tprocc-run-production.tcl → MTX runner; no TPCC) ==="
set _mtx_prod_dir [file dirname [file normalize [info script]]]
source [file join $_mtx_prod_dir hammerdb-mtx-transaction-items-run.tcl]
