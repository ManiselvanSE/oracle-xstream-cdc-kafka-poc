#!/usr/bin/env bash
# =============================================================================
# MTX_TRANSACTION_ITEMS Load Test Execution Script
# This script orchestrates the HammerDB load test for MTX_TRANSACTION_ITEMS only
# =============================================================================

set -euo pipefail

# Configuration
HAMMERDB_VM="129.146.31.189"
SSH_KEY="/Users/maniselvank/Desktop/Mani/ssh-key-2026-03-12.key"
CONNECTOR_VM="137.131.53.98"
DB_HOST="10.0.0.29"
DB_PORT="1521"
DB_SERVICE="DB0312_r8n_phx.sub01061249390.xstrmconnectdb2.oraclevcn.com"
ORDERMGMT_PASS="ConFL#_uent12"
SYS_PASS="ConFL#_uent12"

# Test parameters
TEST_DURATION="${TEST_DURATION:-3600}"  # 1 hour default
VUS="${VUS:-4}"  # Virtual users (set to vcpu for max load)
TOTAL_ITERATIONS="${TOTAL_ITERATIONS:-1000000}"  # High number for sustained load

echo "=========================================="
echo "MTX_TRANSACTION_ITEMS Load Test"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  HammerDB VM: ${HAMMERDB_VM}"
echo "  Virtual Users: ${VUS} (use 'vcpu' for max)"
echo "  Total Iterations: ${TOTAL_ITERATIONS}"
echo "  Test Duration: ~${TEST_DURATION} seconds"
echo ""

# Create results directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="mtx-test-results-${TIMESTAMP}"
mkdir -p "${RESULTS_DIR}"

echo "Results will be saved to: ${RESULTS_DIR}"
echo ""

# Step 1: Get baseline metrics
echo "=== STEP 1: Collecting Baseline Metrics ==="
echo ""

echo "Getting baseline row count..."
sqlplus -S ordermgmt/"${ORDERMGMT_PASS}"@//"${DB_HOST}:${DB_PORT}/${DB_SERVICE}" <<EOF > "${RESULTS_DIR}/baseline-rowcount.log"
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF
SELECT COUNT(*) FROM MTX_TRANSACTION_ITEMS;
EXIT;
EOF
BASELINE_ROWS=$(cat "${RESULTS_DIR}/baseline-rowcount.log" | tr -d ' ')
echo "Baseline MTX_TRANSACTION_ITEMS rows: ${BASELINE_ROWS}"

echo "Getting baseline archive log sequence..."
sqlplus -S sys/"${SYS_PASS}"@//"${DB_HOST}:${DB_PORT}/${DB_SERVICE}" as sysdba <<EOF > "${RESULTS_DIR}/baseline-archivelog.log"
SET PAGESIZE 100 FEEDBACK OFF VERIFY OFF HEADING ON
SELECT thread#, sequence#, first_time, next_time,
       blocks*block_size/1024/1024 AS size_mb
FROM v\$archived_log
WHERE dest_id = 1
  AND first_time > SYSDATE - 1/24
ORDER BY first_time DESC
FETCH FIRST 10 ROWS ONLY;
EXIT;
EOF

echo "Baseline metrics saved."
echo ""

# Step 2: Prepare HammerDB VM
echo "=== STEP 2: Preparing HammerDB VM ==="
echo ""

echo "Uploading HammerDB scripts to VM..."
ssh -i "${SSH_KEY}" opc@${HAMMERDB_VM} "mkdir -p ~/hammerdb-mtx-test"

# Copy the necessary files
scp -i "${SSH_KEY}" \
    oracle-xstream-cdc-poc/hammerdb-mtx-vm-bundle/*.{sh,tcl,sql,py} \
    opc@${HAMMERDB_VM}:~/hammerdb-mtx-test/ 2>/dev/null || echo "Some files may not exist, continuing..."

echo "Scripts uploaded."
echo ""

# Step 3: Start monitoring
echo "=== STEP 3: Starting Monitoring ==="
echo ""

# Start background monitoring on HammerDB VM
echo "Starting Oracle monitoring script..."
ssh -i "${SSH_KEY}" opc@${HAMMERDB_VM} <<'EOSSH' > "${RESULTS_DIR}/monitor.log" 2>&1 &
export ORACLE_HOME=/usr/lib/oracle/19.29/client64
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export PATH=$ORACLE_HOME/bin:$PATH
export TNS_ADMIN=$HOME/oracle/network/admin

# Monitor every 30 seconds
while true; do
    echo "=== $(date) ==="
    sqlplus -S sys/'ConFL#_uent12'@RAC_XSTRPDB_POC as sysdba <<EOF
    SET PAGESIZE 100 LINESIZE 200
    -- Redo generation rate
    SELECT inst_id,
           ROUND(SUM(value)/1024/1024, 2) AS redo_mb
    FROM gv\$sysstat
    WHERE name = 'redo size'
    GROUP BY inst_id;

    -- Archive log switches in last 10 minutes
    SELECT COUNT(*) AS log_switches_10min
    FROM v\$archived_log
    WHERE first_time > SYSDATE - 10/1440;

    -- MTX table session count
    SELECT COUNT(*) AS mtx_sessions
    FROM gv\$session
    WHERE username = 'ORDERMGMT';

    EXIT;
EOF
    sleep 30
done
EOSSH

MONITOR_PID=$!
echo "Monitoring started (PID: ${MONITOR_PID})"
echo ""

# Step 4: Run the load test
echo "=== STEP 4: Running HammerDB Load Test ==="
echo ""
echo "Starting HammerDB with MTX_TRANSACTION_ITEMS only mode..."
echo "Mode: items_only (maximum throughput)"
echo ""

# Record start time
START_TIME=$(date +%s)
echo "Test started at: $(date)"
echo "${START_TIME}" > "${RESULTS_DIR}/start-time.txt"

# Execute HammerDB on the VM
ssh -i "${SSH_KEY}" opc@${HAMMERDB_VM} <<EOSSH > "${RESULTS_DIR}/hammerdb-output.log" 2>&1
cd ~/hammerdb-mtx-test

# Source Oracle environment
source hammerdb-oracle-env.sh

# Set test parameters
export HDB_MTX_USER="ordermgmt"
export HDB_MTX_PASS="${ORDERMGMT_PASS}"
export HDB_MTX_TNS="RAC_XSTRPDB_POC"
export HDB_MTX_TOTAL_ITERATIONS="${TOTAL_ITERATIONS}"
export HDB_MTX_MODE="items_only"  # Only MTX_TRANSACTION_ITEMS
export HDB_MTX_VUS="${VUS}"
export HDB_MTX_NO_TC="true"  # Skip transaction counter
export HDB_MTX_RAISEERROR="false"
export HDB_MTX_SCRIPT_DIR="\${HOME}/hammerdb-mtx-test"

echo "==================================="
echo "HammerDB MTX Load Test"
echo "==================================="
echo "Mode: items_only"
echo "VUs: ${VUS}"
echo "Iterations: ${TOTAL_ITERATIONS}"
echo "Started: \$(date)"
echo ""

# Run HammerDB
./hammerdb-mtx-run-production.sh

echo ""
echo "Test completed: \$(date)"
EOSSH

# Record end time
END_TIME=$(date +%s)
echo "Test completed at: $(date)"
echo "${END_TIME}" > "${RESULTS_DIR}/end-time.txt"

DURATION=$((END_TIME - START_TIME))
echo "Total test duration: ${DURATION} seconds ($((DURATION/60)) minutes)"
echo ""

# Stop monitoring
echo "Stopping monitoring..."
kill ${MONITOR_PID} 2>/dev/null || true
echo ""

# Step 5: Collect final metrics
echo "=== STEP 5: Collecting Final Metrics ==="
echo ""

echo "Getting final row count..."
sqlplus -S ordermgmt/"${ORDERMGMT_PASS}"@//"${DB_HOST}:${DB_PORT}/${DB_SERVICE}" <<EOF > "${RESULTS_DIR}/final-rowcount.log"
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF
SELECT COUNT(*) FROM MTX_TRANSACTION_ITEMS;
EXIT;
EOF
FINAL_ROWS=$(cat "${RESULTS_DIR}/final-rowcount.log" | tr -d ' ')
ROWS_INSERTED=$((FINAL_ROWS - BASELINE_ROWS))
echo "Final MTX_TRANSACTION_ITEMS rows: ${FINAL_ROWS}"
echo "Rows inserted during test: ${ROWS_INSERTED}"

echo "Getting archive log generation during test..."
sqlplus -S sys/"${SYS_PASS}"@//"${DB_HOST}:${DB_PORT}/${DB_SERVICE}" as sysdba <<EOF > "${RESULTS_DIR}/test-archivelog.log"
SET PAGESIZE 1000 FEEDBACK OFF VERIFY OFF HEADING ON LINESIZE 200
COL first_time FORMAT A20
COL next_time FORMAT A20

SELECT thread#, sequence#,
       TO_CHAR(first_time, 'YYYY-MM-DD HH24:MI:SS') AS first_time,
       TO_CHAR(next_time, 'YYYY-MM-DD HH24:MI:SS') AS next_time,
       blocks*block_size/1024/1024 AS size_mb
FROM v\$archived_log
WHERE dest_id = 1
  AND first_time >= TO_DATE('$(date -r ${START_TIME} '+%Y-%m-%d %H:%M:%S')', 'YYYY-MM-DD HH24:MI:SS')
  AND next_time <= TO_DATE('$(date -r ${END_TIME} '+%Y-%m-%d %H:%M:%S')', 'YYYY-MM-DD HH24:MI:SS')
ORDER BY first_time;

-- Total redo generated
SELECT SUM(blocks*block_size/1024/1024/1024) AS total_redo_gb
FROM v\$archived_log
WHERE dest_id = 1
  AND first_time >= TO_DATE('$(date -r ${START_TIME} '+%Y-%m-%d %H:%M:%S')', 'YYYY-MM-DD HH24:MI:SS')
  AND next_time <= TO_DATE('$(date -r ${END_TIME} '+%Y-%m-%d %H:%M:%S')', 'YYYY-MM-DD HH24:MI:SS');

EXIT;
EOF

echo "Archive log metrics collected."
echo ""

# Step 6: Check Kafka lag and throughput
echo "=== STEP 6: Checking Kafka Metrics ==="
echo ""

ssh -i "${SSH_KEY}" opc@${CONNECTOR_VM} <<'EOSSH' > "${RESULTS_DIR}/kafka-metrics.log" 2>&1
echo "Kafka Topics for MTX_TRANSACTION_ITEMS:"
kafka-topics --bootstrap-server localhost:9092 --list | grep -i mtx_transaction_items || echo "No MTX topic found"

echo ""
echo "Consumer group lag:"
kafka-consumer-groups --bootstrap-server localhost:9092 --describe --all-groups | grep -i mtx || echo "No consumer groups found"

echo ""
echo "Topic details:"
kafka-topics --bootstrap-server localhost:9092 --describe --topic ORDERMGMT.MTX_TRANSACTION_ITEMS 2>/dev/null || echo "Topic not found"
EOSSH

echo "Kafka metrics collected."
echo ""

# Step 7: Generate summary report
echo "=== STEP 7: Generating Summary Report ==="
echo ""

cat > "${RESULTS_DIR}/SUMMARY.md" <<EOSUM
# MTX_TRANSACTION_ITEMS Load Test Results
## Test Run: ${TIMESTAMP}

### Test Configuration
- **Test Mode**: items_only (MTX_TRANSACTION_ITEMS only)
- **Virtual Users**: ${VUS}
- **Total Iterations**: ${TOTAL_ITERATIONS}
- **Duration**: ${DURATION} seconds ($((DURATION/60)) minutes)
- **Start Time**: $(date -r ${START_TIME})
- **End Time**: $(date -r ${END_TIME})

### Database Metrics
- **Baseline Row Count**: ${BASELINE_ROWS}
- **Final Row Count**: ${FINAL_ROWS}
- **Rows Inserted**: ${ROWS_INSERTED}
- **Insert Rate**: $((ROWS_INSERTED / DURATION)) rows/sec

### Archive Log Generation
See: test-archivelog.log for detailed redo generation

### Kafka CDC Metrics
See: kafka-metrics.log for topic lag and throughput

### Files Generated
- baseline-rowcount.log - Initial row count
- final-rowcount.log - Final row count
- baseline-archivelog.log - Pre-test archive logs
- test-archivelog.log - Archive logs during test
- hammerdb-output.log - HammerDB console output
- monitor.log - Real-time monitoring output
- kafka-metrics.log - Kafka consumer lag and throughput

### Grafana Dashboard
Monitor real-time metrics at:
http://137.131.53.98:3000/d/xstream-throughput-performance/oracle-xstream-cdc-throughput-and-performance?orgId=1&refresh=10s

Filter time range: $(date -r ${START_TIME} '+%Y-%m-%d %H:%M') to $(date -r ${END_TIME} '+%Y-%m-%d %H:%M')

### Next Steps
1. Review Grafana dashboard for CDC lag metrics
2. Check monitor.log for any errors or spikes
3. Verify Kafka topic has received all events
4. Calculate replication lag from XStream to Kafka
5. Prepare client presentation with these metrics
EOSUM

echo "Summary report generated: ${RESULTS_DIR}/SUMMARY.md"
echo ""

# Display summary
cat "${RESULTS_DIR}/SUMMARY.md"

echo ""
echo "=========================================="
echo "Test Complete!"
echo "=========================================="
echo ""
echo "All results saved in: ${RESULTS_DIR}/"
echo ""
echo "Key metrics:"
echo "  - Rows inserted: ${ROWS_INSERTED}"
echo "  - Insert rate: $((ROWS_INSERTED / DURATION)) rows/sec"
echo "  - Test duration: ${DURATION} seconds"
echo ""
echo "Next: Review ${RESULTS_DIR}/SUMMARY.md and check Grafana dashboard"
echo "Grafana: http://137.131.53.98:3000/d/xstream-throughput-performance/oracle-xstream-cdc-throughput-and-performance"
