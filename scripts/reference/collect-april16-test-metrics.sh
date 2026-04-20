#!/usr/bin/env bash
# =============================================================================
# Collect April 16, 2026 30-Minute Load Test Metrics
# Gathers Oracle, XStream, and Kafka metrics for the test period
# =============================================================================

set -euo pipefail

# SSH Configuration
SSH_KEY="/Users/maniselvank/Desktop/Mani/ssh-key-2026-03-12.key"
SSH_HOST="opc@129.146.31.189"

# Oracle Environment
ORACLE_HOME="/usr/lib/oracle/19.29/client64"
TNS_ADMIN="$HOME/oracle/network/admin"

# Test Period (April 16, 2026)
# Test Start: 2026-04-16 00:29:37 IST
# Test End:   2026-04-16 00:51:33 IST
TEST_DATE="2026-04-16"
TEST_START_TIME="00:29:37"
TEST_END_TIME="00:51:33"

# Output directory
OUTPUT_DIR="mtx-30min-test-metrics-$(date +%Y%m%d_%H%M%S)"
mkdir -p "${OUTPUT_DIR}"

echo "=============================================="
echo "MTX 30-Minute Load Test - Metrics Collection"
echo "=============================================="
echo ""
echo "Test Date: ${TEST_DATE}"
echo "Test Period: ${TEST_START_TIME} - ${TEST_END_TIME} IST"
echo "Output: ${OUTPUT_DIR}"
echo ""

# =============================================================================
# 1. ORACLE ARCHIVE LOG METRICS (Redo Generation & Log Switches)
# =============================================================================
echo "=== 1. Collecting Oracle Archive Log Metrics ==="
echo ""

ssh -i "${SSH_KEY}" "${SSH_HOST}" <<'EOSSH' > "${OUTPUT_DIR}/01-archive-logs.txt"
export ORACLE_HOME=/usr/lib/oracle/19.29/client64
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=$HOME/oracle/network/admin

sqlplus -S sys/'ConFL#_uent12'@RAC_XSTRPDB_POC as sysdba <<'EOSQL'
SET LINESIZE 200 PAGESIZE 500
SET FEEDBACK ON VERIFY OFF HEADING ON

PROMPT ========== Archive Logs for April 16, 2026 (Full Day) ==========
SELECT TRUNC(completion_time, 'DD') AS day,
       thread#,
       ROUND(SUM(blocks * block_size) / 1024 / 1024 / 1024, 2) AS gb,
       COUNT(*) AS archives_generated
  FROM v$archived_log
 WHERE TRUNC(completion_time, 'DD') = TO_DATE('2026-04-16', 'YYYY-MM-DD')
 GROUP BY TRUNC(completion_time, 'DD'), thread#
 ORDER BY 1, 2;

PROMPT ========== Archive Logs During Test Window (00:29 - 00:52 IST) ==========
SELECT TO_CHAR(completion_time, 'YYYY-MM-DD HH24:MI:SS') AS completion_time,
       thread#,
       sequence#,
       ROUND(blocks * block_size / 1024 / 1024, 2) AS mb,
       ROUND(blocks * block_size / 1024 / 1024 / 1024, 3) AS gb
  FROM v$archived_log
 WHERE completion_time >= TO_TIMESTAMP('2026-04-16 00:29:00', 'YYYY-MM-DD HH24:MI:SS')
   AND completion_time <= TO_TIMESTAMP('2026-04-16 00:52:00', 'YYYY-MM-DD HH24:MI:SS')
 ORDER BY completion_time;

PROMPT ========== Archive Logs by Hour for April 16 ==========
SELECT TRUNC(completion_time, 'HH24') AS hour,
       thread#,
       ROUND(SUM(blocks * block_size) / 1024 / 1024 / 1024, 2) AS gb_redo,
       COUNT(*) AS archive_writes
  FROM v$archived_log
 WHERE TRUNC(completion_time, 'DD') = TO_DATE('2026-04-16', 'YYYY-MM-DD')
 GROUP BY TRUNC(completion_time, 'HH24'), thread#
 ORDER BY 1, 2;

PROMPT ========== Archive Logs by Minute (Test Window) ==========
SELECT TRUNC(completion_time, 'MI') AS minute_bucket,
       thread#,
       ROUND(SUM(blocks * block_size) / 1024 / 1024, 1) AS mb_redo,
       COUNT(*) AS archives_in_bucket
  FROM v$archived_log
 WHERE completion_time >= TO_TIMESTAMP('2026-04-16 00:29:00', 'YYYY-MM-DD HH24:MI:SS')
   AND completion_time <= TO_TIMESTAMP('2026-04-16 00:52:00', 'YYYY-MM-DD HH24:MI:SS')
 GROUP BY TRUNC(completion_time, 'MI'), thread#
 ORDER BY 1 DESC, 2;

EXIT;
EOSQL
EOSSH

if [ -f "${OUTPUT_DIR}/01-archive-logs.txt" ]; then
    echo "  ✓ Archive log metrics saved"
else
    echo "  ✗ Failed to collect archive log metrics"
fi

# =============================================================================
# 2. ORACLE REDO STATISTICS (System-wide)
# =============================================================================
echo ""
echo "=== 2. Collecting Oracle Redo Statistics ==="
echo ""

ssh -i "${SSH_KEY}" "${SSH_HOST}" <<'EOSSH' > "${OUTPUT_DIR}/02-redo-statistics.txt"
export ORACLE_HOME=/usr/lib/oracle/19.29/client64
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=$HOME/oracle/network/admin

sqlplus -S sys/'ConFL#_uent12'@RAC_XSTRPDB_POC as sysdba <<'EOSQL'
SET LINESIZE 200 PAGESIZE 100
COLUMN redo_mb FORMAT 999,999,999.99

PROMPT ========== Instance Redo Statistics (Cumulative Since Startup) ==========
SELECT name, value AS bytes,
       ROUND(value/1024/1024, 2) AS redo_mb
FROM v$sysstat
WHERE name IN ('redo size', 'redo wastage', 'redo writes', 'redo write time')
ORDER BY name;

PROMPT ========== Online Redo Log Groups ==========
SELECT group#, thread#, bytes/1024/1024 AS mb, status, archived
  FROM v$log
 ORDER BY thread#, group#;

EXIT;
EOSQL
EOSSH

if [ -f "${OUTPUT_DIR}/02-redo-statistics.txt" ]; then
    echo "  ✓ Redo statistics saved"
else
    echo "  ✗ Failed to collect redo statistics"
fi

# =============================================================================
# 3. XSTREAM CAPTURE STATISTICS
# =============================================================================
echo ""
echo "=== 3. Collecting XStream Capture Statistics ==="
echo ""

ssh -i "${SSH_KEY}" "${SSH_HOST}" <<'EOSSH' > "${OUTPUT_DIR}/03-xstream-statistics.txt"
export ORACLE_HOME=/usr/lib/oracle/19.29/client64
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=$HOME/oracle/network/admin

sqlplus -S sys/'ConFL#_uent12'@RAC_XSTRPDB_POC as sysdba <<'EOSQL'
SET LINESIZE 200 PAGESIZE 100
ALTER SESSION SET CONTAINER = CDB$ROOT;

PROMPT ========== XStream Outbound Server ==========
SELECT SERVER_NAME, CONNECT_USER, CAPTURE_NAME, QUEUE_OWNER, QUEUE_NAME, STATUS
FROM DBA_XSTREAM_OUTBOUND;

PROMPT ========== XStream Capture Status ==========
SELECT CAPTURE_NAME, QUEUE_OWNER, QUEUE_NAME, STATUS, START_SCN, SOURCE_DATABASE
FROM DBA_CAPTURE WHERE CAPTURE_NAME = 'CONFLUENT_XOUT1';

PROMPT ========== XStream Capture State (RAC Instances) ==========
SELECT INST_ID, CAPTURE_NAME, STATE, STARTUP_TIME,
       TOTAL_MESSAGES_CAPTURED, TOTAL_MESSAGES_ENQUEUED
FROM GV$XSTREAM_CAPTURE WHERE CAPTURE_NAME = 'CONFLUENT_XOUT1';

PROMPT ========== XStream Outbound Server Statistics ==========
SELECT SERVER_NAME,
       STARTUP_TIME,
       TOTAL_MESSAGES_SENT,
       TOTAL_BYTES_SENT,
       LAST_SENT_MESSAGE_CREATE_TIME,
       LAST_SENT_MESSAGE_NUMBER,
       ELAPSED_SEND_TIME,
       BYTES_SENT,
       MESSAGE_SEQUENCE
FROM V$XSTREAM_OUTBOUND_SERVER
WHERE SERVER_NAME = 'XOUT';

PROMPT ========== XStream Apply Statistics ==========
SELECT APPLY_NAME,
       TOTAL_MESSAGES_APPLIED,
       TOTAL_ADMIN_HANDLED,
       UNASSIGNED_COMPLETE_TXNS
FROM DBA_APPLY
WHERE APPLY_NAME = 'XOUT';

EXIT;
EOSQL
EOSSH

if [ -f "${OUTPUT_DIR}/03-xstream-statistics.txt" ]; then
    echo "  ✓ XStream statistics saved"
else
    echo "  ✗ Failed to collect XStream statistics"
fi

# =============================================================================
# 4. MTX TABLE STATISTICS
# =============================================================================
echo ""
echo "=== 4. Collecting MTX Table Statistics ==="
echo ""

ssh -i "${SSH_KEY}" "${SSH_HOST}" <<'EOSSH' > "${OUTPUT_DIR}/04-mtx-table-stats.txt"
export ORACLE_HOME=/usr/lib/oracle/19.29/client64
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=$HOME/oracle/network/admin

sqlplus -S sys/'ConFL#_uent12'@RAC_XSTRPDB_POC as sysdba <<'EOSQL'
SET LINESIZE 200 PAGESIZE 100
ALTER SESSION SET CONTAINER = XSTRPDB;

PROMPT ========== MTX_TRANSACTION_ITEMS Current Count ==========
SELECT COUNT(*) AS current_row_count FROM ORDERMGMT.MTX_TRANSACTION_ITEMS;

PROMPT ========== MTX Tables Row Counts and Sizes ==========
SELECT table_name,
       num_rows,
       avg_row_len,
       ROUND(num_rows * NVL(avg_row_len, 0) / 1024 / 1024, 2) AS approx_data_mb
FROM dba_tables
WHERE owner = 'ORDERMGMT'
  AND table_name LIKE 'MTX%'
ORDER BY num_rows DESC NULLS LAST
FETCH FIRST 25 ROWS ONLY;

PROMPT ========== Max Average Row Length for MTX Tables ==========
SELECT MAX(avg_row_len) AS max_avg_row_bytes_among_mtx
FROM dba_tables
WHERE owner = 'ORDERMGMT' AND table_name LIKE 'MTX%' AND avg_row_len IS NOT NULL;

EXIT;
EOSQL
EOSSH

if [ -f "${OUTPUT_DIR}/04-mtx-table-stats.txt" ]; then
    echo "  ✓ MTX table statistics saved"
else
    echo "  ✗ Failed to collect MTX table statistics"
fi

# =============================================================================
# 5. KAFKA CONNECTOR STATUS
# =============================================================================
echo ""
echo "=== 5. Collecting Kafka Connector Status ==="
echo ""

ssh -i "${SSH_KEY}" "${SSH_HOST}" <<'EOSSH' > "${OUTPUT_DIR}/05-kafka-connector-status.txt"
echo "========== Kafka Connector Status =========="
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq '.' 2>/dev/null || echo "Connector status not available"

echo ""
echo "========== Kafka Connector Configuration =========="
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/config | jq '.' 2>/dev/null || echo "Connector config not available"

echo ""
echo "========== Kafka Connector Metrics =========="
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/tasks/0/status | jq '.' 2>/dev/null || echo "Task status not available"
EOSSH

if [ -f "${OUTPUT_DIR}/05-kafka-connector-status.txt" ]; then
    echo "  ✓ Kafka connector status saved"
else
    echo "  ✗ Failed to collect Kafka connector status"
fi

# =============================================================================
# 6. KAFKA TOPIC INFORMATION
# =============================================================================
echo ""
echo "=== 6. Collecting Kafka Topic Information ==="
echo ""

ssh -i "${SSH_KEY}" "${SSH_HOST}" <<'EOSSH' > "${OUTPUT_DIR}/06-kafka-topics.txt"
echo "========== Kafka Topics (MTX) =========="
kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | grep -i mtx || echo "No MTX topics found"

echo ""
echo "========== MTX_TRANSACTION_ITEMS Topic Details =========="
TOPIC_NAME=$(kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | grep -i "MTX_TRANSACTION_ITEMS" | head -1)
if [ -n "${TOPIC_NAME}" ]; then
    echo "Topic: ${TOPIC_NAME}"
    kafka-topics --bootstrap-server localhost:9092 --describe --topic "${TOPIC_NAME}" 2>/dev/null || echo "Topic details not available"

    echo ""
    echo "========== Topic Message Count (Estimate) =========="
    kafka-run-class kafka.tools.GetOffsetShell --bootstrap-server localhost:9092 --topic "${TOPIC_NAME}" --time -1 2>/dev/null || echo "Message count not available"
else
    echo "MTX_TRANSACTION_ITEMS topic not found"
fi
EOSSH

if [ -f "${OUTPUT_DIR}/06-kafka-topics.txt" ]; then
    echo "  ✓ Kafka topic information saved"
else
    echo "  ✗ Failed to collect Kafka topic information"
fi

# =============================================================================
# 7. GENERATE METRICS SUMMARY
# =============================================================================
echo ""
echo "=== 7. Generating Metrics Summary ==="
echo ""

cat > "${OUTPUT_DIR}/00-METRICS-SUMMARY.md" <<'EOF'
# MTX 30-Minute Load Test - Detailed Metrics
## April 16, 2026 - Test Period: 00:29:37 - 00:51:33 IST

---

## Test Overview

**Test Date:** April 16, 2026
**Test Start:** 00:29:37 IST
**Test End:** 00:51:33 IST
**Duration:** ~22 minutes
**Rows Inserted:** 14,019,801
**Baseline Rows:** 3,493,457
**Final Rows:** 17,513,258

---

## Metrics Files Collected

1. **01-archive-logs.txt** - Oracle archive log generation and redo switches
2. **02-redo-statistics.txt** - System-wide redo statistics
3. **03-xstream-statistics.txt** - XStream capture and outbound statistics
4. **04-mtx-table-stats.txt** - MTX table row counts and sizes
5. **05-kafka-connector-status.txt** - Kafka Connect connector status
6. **06-kafka-topics.txt** - Kafka topic information and message counts

---

## Key Metrics to Extract

### From Archive Logs (01-archive-logs.txt)
- [ ] Total redo generated (GB) during test window
- [ ] Number of log switches
- [ ] Redo generation by thread
- [ ] Minute-by-minute redo generation

### From XStream Statistics (03-xstream-statistics.txt)
- [ ] Total messages captured
- [ ] Total messages sent
- [ ] Total bytes sent
- [ ] Capture state and status
- [ ] Last sent message time

### From Kafka Connector (05-kafka-connector-status.txt)
- [ ] Connector state (RUNNING/FAILED)
- [ ] Task state
- [ ] Connector throughput
- [ ] Any errors or warnings

### From Kafka Topics (06-kafka-topics.txt)
- [ ] Topic name
- [ ] Number of partitions
- [ ] Total messages in topic
- [ ] Message offset range

---

## Analysis Instructions

1. **Calculate Redo Rate:**
   - Extract total GB from archive logs during test window
   - Divide by test duration (22 minutes = 1,320 seconds)
   - Report as MB/sec

2. **Verify Events Captured:**
   - Check XStream total_messages_captured
   - Compare to row count (14,019,801)
   - Should be approximately equal

3. **Calculate CDC Lag:**
   - Check last_sent_message_create_time in XStream
   - Compare to test end time
   - Calculate difference in milliseconds

4. **Verify Kafka Throughput:**
   - Check Kafka topic message count
   - Should match row count (14,019,801)
   - Extract from GetOffsetShell output

5. **Generate Final Report:**
   - Use extracted metrics to update detailed report
   - Include actual vs estimated comparisons
   - Document any discrepancies

---

## Next Steps

1. Review each metrics file
2. Extract key numbers
3. Update comprehensive test report
4. Create executive summary with actuals
5. Generate charts and graphs

---

**Collection Date:** $(date)
**Collection Script:** `scripts/reference/collect-april16-test-metrics.sh` (in this repository)
**Output Directory:** ${OUTPUT_DIR}
EOF

echo "  ✓ Metrics summary created"

# =============================================================================
# 8. CREATE CSV FOR EXCEL IMPORT
# =============================================================================
echo ""
echo "=== 8. Creating CSV Template ==="
echo ""

cat > "${OUTPUT_DIR}/metrics-template.csv" <<'EOF'
Metric,Value,Unit,Notes
Test Date,2026-04-16,,
Test Start Time,00:29:37,IST,
Test End Time,00:51:33,IST,
Test Duration,22,minutes,
Test Duration,1320,seconds,
Baseline Rows,3493457,rows,
Final Rows,17513258,rows,
Rows Inserted,14019801,rows,
Concurrent Sessions,48,sessions,Peak during test
Average Throughput,1063,rows/sec,"14019801 / 1320"
Total Redo Generated,TBD,GB,From 01-archive-logs.txt
Total Log Switches,TBD,count,From 01-archive-logs.txt
Redo Rate,TBD,MB/sec,Total GB / 1320 seconds
XStream Messages Captured,TBD,messages,From 03-xstream-statistics.txt
XStream Messages Sent,TBD,messages,From 03-xstream-statistics.txt
XStream Bytes Sent,TBD,bytes,From 03-xstream-statistics.txt
Kafka Messages,TBD,messages,From 06-kafka-topics.txt
Kafka Topic,TBD,topic_name,From 06-kafka-topics.txt
Connector Status,TBD,status,From 05-kafka-connector-status.txt
CDC Lag,TBD,milliseconds,Calculated from timestamps
Success Rate,100,%,
Error Rate,0,%,
EOF

echo "  ✓ CSV template created (metrics-template.csv)"

# =============================================================================
# COMPLETION
# =============================================================================
echo ""
echo "=============================================="
echo "Metrics Collection Complete!"
echo "=============================================="
echo ""
echo "Output Directory: ${OUTPUT_DIR}/"
echo ""
echo "Files created:"
ls -lh "${OUTPUT_DIR}/"
echo ""
echo "Next Steps:"
echo "1. Review each metrics file"
echo "2. Extract key numbers and update metrics-template.csv"
echo "3. Update comprehensive test report with actual values"
echo "4. Generate charts and visualizations"
echo ""
echo "Key Files:"
echo "  - 00-METRICS-SUMMARY.md (start here)"
echo "  - metrics-template.csv (fill in TBD values)"
echo "  - 01-archive-logs.txt (redo generation data)"
echo "  - 03-xstream-statistics.txt (CDC metrics)"
echo ""
