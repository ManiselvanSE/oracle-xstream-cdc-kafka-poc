# =============================================================================
# HammerDB CUSTOM DRIVER — ORDERMGMT.MTX* CDC load (Oratcl)
#
# Modes (env HDB_MTX_MODE):
#   all_mtx   — default. Each iteration runs one "wave": INSERT into all MTX tables
#               (see hammerdb-mtx-multitable-wave.sql). Good for multi-topic CDC.
#   items_only — legacy: INSERT only into MTX_TRANSACTION_ITEMS (high row count).
#
# Config: HDB_MTX_USER, HDB_MTX_PASS, HDB_MTX_TNS, HDB_MTX_TOTAL_ITERATIONS,
#         optional HDB_MTX_RAISEERROR, HDB_MTX_MODE
# Time-bound run (overrides iteration limit for the loop): HDB_MTX_DURATION_SECONDS
#   e.g. 1800 = 30 minutes of sustained inserts per VU (heavy redo / log switches).
# =============================================================================

if { [catch {package require Oratcl} message] } {
  error "Failed to load Oratcl: $message"
}
if { [catch {package require tpcccommon} message] } {
  error "Failed to load tpcccommon: $message"
}
namespace import tpcccommon::*

if { ![info exists ::env(HDB_MTX_USER)] || $::env(HDB_MTX_USER) eq "" } {
  error "Set HDB_MTX_USER (e.g. ordermgmt)"
}
if { ![info exists ::env(HDB_MTX_PASS)] || $::env(HDB_MTX_PASS) eq "" } {
  error "Set HDB_MTX_PASS"
}
if { ![info exists ::env(HDB_MTX_TNS)] || $::env(HDB_MTX_TNS) eq "" } {
  error "Set HDB_MTX_TNS (TNS alias, e.g. RAC_XSTRPDB_POC)"
}
if { ![info exists ::env(HDB_MTX_TOTAL_ITERATIONS)] || $::env(HDB_MTX_TOTAL_ITERATIONS) eq "" } {
  set ::env(HDB_MTX_TOTAL_ITERATIONS) 100000
}

if { ![info exists ::env(HDB_MTX_MODE)] || $::env(HDB_MTX_MODE) eq "" } {
  set ::env(HDB_MTX_MODE) "all_mtx"
}

set connect "$::env(HDB_MTX_USER)/$::env(HDB_MTX_PASS)@$::env(HDB_MTX_TNS)"
set total_iterations [expr { int($::env(HDB_MTX_TOTAL_ITERATIONS)) }]
set use_duration 0
set end_time 0
if { [info exists ::env(HDB_MTX_DURATION_SECONDS)] && $::env(HDB_MTX_DURATION_SECONDS) ne "" } {
  set ds [expr { int($::env(HDB_MTX_DURATION_SECONDS)) }]
  if { $ds > 0 } {
    set use_duration 1
    set end_time [expr { [clock seconds] + $ds }]
  }
}
set RAISEERROR false
if { [info exists ::env(HDB_MTX_RAISEERROR)] && [string tolower $::env(HDB_MTX_RAISEERROR)] eq "true" } {
  set RAISEERROR true
}
set KEYANDTHINK false

proc OracleLogon { connectstring lda } {
  set lda [oralogon $connectstring ]
  SetNLS $lda
  oraautocom $lda on
  return $lda
}

proc SetNLS { lda } {
  set curn_nls [oraopen $lda ]
  set nls(1) "alter session set NLS_LANGUAGE = AMERICAN"
  set nls(2) "alter session set NLS_TERRITORY = AMERICA"
  for { set i 1 } { $i <= 2 } { incr i } {
    if { [ catch {orasql $curn_nls $nls($i)} message ] } {
      puts "$message $nls($i)"
    }
  }
  oraclose $curn_nls
}

proc strip_sql_comments { text } {
  set out {}
  foreach line [split $text \n] {
    set t [string trimleft $line]
    if { [string match "--*" $t] } { continue }
    append out $line "\n"
  }
  return [string trim $out]
}

proc load_text_file { path } {
  set f [open $path r]
  set t [read $f]
  close $f
  return $t
}

# PK is UNIQUE_SEQ_NUMBER (VARCHAR2(50)) — must not duplicate across VUs.
# Old logic used string range 0 49 on a long prefix; left-truncation made different
# threads collide on ORA-00001 (silenced when raiseerror=false → no Grafana load).
proc mtx_unique_seq50 { vid it } {
  set long "SEQ-MTX-[clock microseconds]-V${vid}-I${it}-[pid]-[expr {int(rand()*1e9)}]-[expr {int(rand()*1e9)}]"
  if { [string length $long] <= 50 } {
    return $long
  }
  return [string range $long end-49 end]
}

# TRANSFER_ID VARCHAR2(20) — include vu + high-res time so parallel VUs do not truncate to same 20 chars.
proc mtx_transfer_id20 { vid it } {
  set long "T[clock microseconds]-V${vid}-I${it}"
  if { [string length $long] <= 20 } {
    return $long
  }
  return [string range $long end-19 end]
}

proc load_wave_sql { dir } {
  set path [file join $dir hammerdb-mtx-multitable-wave.sql]
  if { ![file exists $path] } {
    error "Missing $path (multi-table wave SQL). Set HDB_MTX_SCRIPT_DIR to the directory containing this file."
  }
  set f [open $path r]
  set raw [read $f]
  close $f
  return [strip_sql_comments $raw]
}

# [info script] is unreliable when HammerDB loads this via customscript inside VU threads (often ".").
set mtx_script_dir ""
if { [info exists ::env(HDB_MTX_SCRIPT_DIR)] && $::env(HDB_MTX_SCRIPT_DIR) ne "" } {
  set mtx_script_dir [file normalize $::env(HDB_MTX_SCRIPT_DIR)]
} else {
  set mtx_script_dir [file dirname [file normalize [info script]]]
}
set lda [ OracleLogon $connect lda ]
set mode [string tolower $::env(HDB_MTX_MODE)]

if { $mode eq "items_only" } {
  # ----- MTX_TRANSACTION_ITEMS only (full column list; see hammerdb-mtx-items-only-insert.sql) -----
  set items_path [file join $mtx_script_dir hammerdb-mtx-items-only-insert.sql]
  if { ![file exists $items_path] } {
    error "Missing $items_path (run: python3 generate-hammerdb-mtx-multitable-wave.py)"
  }
  set sql_ins [strip_sql_comments [load_text_file $items_path]]
  set curn [oraopen $lda ]
  oraparse $curn $sql_ins
  set vid 0
  if { [llength [info commands thread::id]] } {
    catch { set vid [thread::id] }
  }
  if { $use_duration } {
    puts "HDB_MTX_MODE=items_only — duration=${::env(HDB_MTX_DURATION_SECONDS)}s into MTX_TRANSACTION_ITEMS (time-bound)..."
  } else {
    puts "HDB_MTX_MODE=items_only — $total_iterations inserts into MTX_TRANSACTION_ITEMS only..."
  }
  set it 0
  while { 1 } {
    if { ![catch {tsv::get application abort} a] && $a } { break }
    if { $use_duration } {
      if { [clock seconds] >= $end_time } { break }
    } else {
      if { $it >= $total_iterations } { break }
    }
    set seq [mtx_unique_seq50 $vid $it]
    set trf [mtx_transfer_id20 $vid $it]
    set pty "P001"
    set acc "ACC001"
    set sec "P002"
    set txnseq [expr {1000 + ($it % 999999000)}]
    set plbd 0
    if { [info exists ::env(HDB_MTX_PAYLOAD_BYTES)] && $::env(HDB_MTX_PAYLOAD_BYTES) ne "" } {
      set plbd [expr { int($::env(HDB_MTX_PAYLOAD_BYTES)) }]
    }
    # Prod INSERT may include CDC_PAYLOAD + :plbd (see hammerdb-mtx-items-only-insert.sql).
    if { [string match *:plbd* $sql_ins] } {
      orabind $curn :trf $trf :pty $pty :acc $acc :sec $sec :txnseq $txnseq :seq $seq :plbd $plbd
    } else {
      orabind $curn :trf $trf :pty $pty :acc $acc :sec $sec :txnseq $txnseq :seq $seq
    }
    if { [catch {oraexec $curn} message] } {
      if { $RAISEERROR } {
        error "MTX insert: $message [ oramsg $curn all ]"
      }
    }
    incr it
  }
  oraclose $curn
} else {
  # ----- Default: one wave per iteration (all MTX tables in hammerdb-mtx-multitable-wave.sql) -----
  set wave_sql [load_wave_sql $mtx_script_dir]
  set curn [oraopen $lda ]
  if { [catch {oraparse $curn $wave_sql} err] } {
    puts stderr "oraparse failed: $err"
    puts stderr "First 400 chars: [string range $wave_sql 0 400]"
    error "Fix hammerdb-mtx-multitable-wave.sql or Oratcl bind :suf"
  }
  set vid 0
  if { [llength [info commands thread::id]] } {
    catch { set vid [thread::id] }
  }
  if { $use_duration } {
    puts "HDB_MTX_MODE=all_mtx — duration=${::env(HDB_MTX_DURATION_SECONDS)}s (multi-table wave)..."
  } else {
    puts "HDB_MTX_MODE=all_mtx — $total_iterations waves (multi-table; see hammerdb-mtx-multitable-wave.sql)..."
  }
  set it 0
  while { 1 } {
    if { ![catch {tsv::get application abort} a] && $a } { break }
    if { $use_duration } {
      if { [clock seconds] >= $end_time } { break }
    } else {
      if { $it >= $total_iterations } { break }
    }
    set ts [clock format [clock seconds] -format %Y%m%d%H%M%S]
    set suf [string range "W${ts}-${vid}-${it}-[clock microseconds]-[expr {int(rand()*1e6)}]" 0 120]
    orabind $curn :suf $suf
    if { [catch {oraexec $curn} message] } {
      if { $RAISEERROR } {
        error "Wave insert: $message [ oramsg $curn all ]"
      }
    }
    incr it
  }
  oraclose $curn
}

oralogoff $lda
