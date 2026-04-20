# MTX_TRANSACTION_ITEMS Load Test - Execution Guide

## Overview
This guide provides step-by-step instructions to validate setup and execute a maximum load test on **ORDERMGMT.MTX_TRANSACTION_ITEMS** using HammerDB, then capture metrics for the client presentation.

## Test Objective
- Generate maximum CDC load on MTX_TRANSACTION_ITEMS table only
- Measure Oracle redo generation, Kafka throughput, and replication lag
- Capture Grafana dashboard metrics
- Prepare results for Airtel client presentation

---

## Prerequisites

### 1. Server Access
- **HammerDB VM**: `ssh -i /Users/maniselvank/Desktop/Mani/ssh-key-2026-03-12.key opc@129.146.31.189`
- **Connector VM**: `ssh -i /Users/maniselvank/Desktop/Mani/ssh-key-2026-03-12.key opc@137.131.53.98`
- **Oracle Database**: `sqlplus sys/'ConFL#_uent12'@//10.0.0.29:1521/DB0312_r8n_phx.sub01061249390.xstrmconnectdb2.oraclevcn.com as sysdba`

### 2. Required Components
- [x] Oracle Database in ARCHIVELOG mode
- [x] XStream outbound configured (CONFLUENT_XOUT1)
- [x] MTX_TRANSACTION_ITEMS in XStream capture rules
- [x] Kafka connector running
- [x] HammerDB 5.0 installed on VM
- [x] Grafana dashboard accessible

---

## Step-by-Step Execution

### STEP 1: Validate Setup (5-10 minutes)

Run the validation script from your Mac:

```bash
cd /Users/maniselvank/Mani/customer/airtel/oracle-xstream-cdc-poc

# Make scripts executable
chmod +x validate-mtx-test-setup.sh
chmod +x run-mtx-load-test.sh

# Run validation
./validate-mtx-test-setup.sh
```

**Expected Output:**
```
✓ PASS: Oracle database is accessible
✓ PASS: MTX_TRANSACTION_ITEMS is configured in XStream
✓ PASS: XStream outbound server CONFLUENT_XOUT1 exists
✓ PASS: HammerDB 5.0 is installed
✓ PASS: Oracle connection from HammerDB VM works
✓ PASS: Grafana is accessible
```

**If validation fails**, review the error messages and fix issues before proceeding.

---

### STEP 2: Verify MTX_TRANSACTION_ITEMS in XStream

If the validation shows MTX_TRANSACTION_ITEMS is **NOT** in XStream, add it:

```sql
-- Connect as SYS
sqlplus sys/'ConFL#_uent12'@//10.0.0.29:1521/DB0312_r8n_phx.sub01061249390.xstrmconnectdb2.oraclevcn.com as sysdba

-- Check current rules
SELECT table_owner, table_name, streams_name
FROM dba_streams_table_rules
WHERE streams_name = 'CONFLUENT_XOUT1'
  AND table_owner = 'ORDERMGMT'
  AND table_name = 'MTX_TRANSACTION_ITEMS';

-- If not found, add the rule
BEGIN
  DBMS_XSTREAM_ADM.ADD_TABLE_RULES(
    table_name => 'ORDERMGMT.MTX_TRANSACTION_ITEMS',
    streams_name => 'CONFLUENT_XOUT1',
    include_dml => TRUE,
    include_ddl => FALSE,
    source_database => 'DB0312_R8N_PHX.SUB01061249390.XSTRMCONNECTDB2.ORACLEVCN.COM'
  );
END;
/

-- Verify
SELECT table_owner, table_name, rule_type
FROM dba_streams_table_rules
WHERE streams_name = 'CONFLUENT_XOUT1'
  AND table_owner = 'ORDERMGMT'
  AND table_name = 'MTX_TRANSACTION_ITEMS';

EXIT;
```

---

### STEP 3: Prepare Grafana Dashboard

1. **Open Grafana in browser**: http://137.131.53.98:3000/d/xstream-throughput-performance/oracle-xstream-cdc-throughput-and-performance?orgId=1&refresh=10s

2. **Set auto-refresh**: 10 seconds (already in URL)

3. **Open in separate window/monitor** to watch real-time metrics

4. **Key panels to monitor**:
   - CDC Throughput (events/sec)
   - Replication Lag (milliseconds)
   - Oracle Redo Generation (MB/sec)
   - Kafka Consumer Lag

---

### STEP 4: Run the Load Test

#### Option A: Default Test (1 hour, 4 VUs)

```bash
cd /Users/maniselvank/Mani/customer/airtel/oracle-xstream-cdc-poc

./run-mtx-load-test.sh
```

#### Option B: Maximum Load (all CPUs)

```bash
# Use all available CPUs for maximum throughput
VUS=vcpu ./run-mtx-load-test.sh
```

#### Option C: Custom Duration

```bash
# 2 hour test with 8 virtual users
TEST_DURATION=7200 VUS=8 ./run-mtx-load-test.sh
```

**The script will**:
1. Collect baseline metrics (row count, archive logs)
2. Upload HammerDB scripts to VM
3. Start background monitoring
4. Execute HammerDB load test (items_only mode)
5. Collect final metrics
6. Generate summary report

---

### STEP 5: Monitor During Test

While the test is running:

#### A. Watch Grafana Dashboard
- Monitor CDC lag (should stay < 100ms)
- Watch throughput spikes
- Check for any errors or warnings

#### B. Take Screenshots
Capture Grafana screenshots at:
- **Start of test** (baseline)
- **Peak load** (maximum throughput)
- **End of test** (final state)

Save screenshots to results directory.

#### C. Monitor Oracle (Optional)

Open another terminal and run:

```bash
ssh -i /Users/maniselvank/Desktop/Mani/ssh-key-2026-03-12.key opc@129.146.31.189

# Connect to Oracle
export ORACLE_HOME=/usr/lib/oracle/19.29/client64
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=$HOME/oracle/network/admin

sqlplus sys/'ConFL#_uent12'@RAC_XSTRPDB_POC as sysdba

-- Monitor redo generation every 30 seconds
SET PAGESIZE 100
SELECT inst_id, 
       ROUND(value/1024/1024, 2) AS redo_mb
FROM gv$sysstat
WHERE name = 'redo size'
ORDER BY inst_id;

-- Log switch rate
SELECT COUNT(*) AS switches_last_10min
FROM v$archived_log
WHERE first_time > SYSDATE - 10/1440;
```

---

### STEP 6: Collect Results

After test completion, the script creates a directory like:

```
mtx-test-results-20260415_143000/
├── SUMMARY.md                    # Overall summary
├── baseline-rowcount.log         # Starting row count
├── final-rowcount.log            # Ending row count  
├── baseline-archivelog.log       # Pre-test archive logs
├── test-archivelog.log           # Test period archive logs
├── hammerdb-output.log           # HammerDB console output
├── monitor.log                   # Real-time monitoring
├── kafka-metrics.log             # Kafka lag and throughput
├── start-time.txt                # Test start timestamp
└── end-time.txt                  # Test end timestamp
```

#### Key Metrics to Extract:

1. **Row Count**:
   ```bash
   ROWS_INSERTED = final-rowcount - baseline-rowcount
   ```

2. **Redo Generation**:
   ```bash
   # From test-archivelog.log
   grep "total_redo_gb" test-archivelog.log
   ```

3. **Insert Rate**:
   ```bash
   ROWS_INSERTED / TEST_DURATION_SECONDS = rows/sec
   ```

4. **Archive Log Switches**:
   ```bash
   # Count log switches during test period
   wc -l test-archivelog.log
   ```

---

### STEP 7: Analyze Kafka CDC Metrics

SSH to connector VM and check lag:

```bash
ssh -i /Users/maniselvank/Desktop/Mani/ssh-key-2026-03-12.key opc@137.131.53.98

# Check MTX topic
kafka-topics --bootstrap-server localhost:9092 --list | grep MTX

# Get topic offset (total messages)
kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 \
  --topic ORDERMGMT.MTX_TRANSACTION_ITEMS \
  --time -1

# Check consumer lag
kafka-consumer-groups --bootstrap-server localhost:9092 \
  --describe --group oracle-xstream-connect-group

# Verify message count
kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic ORDERMGMT.MTX_TRANSACTION_ITEMS \
  --from-beginning --max-messages 10
```

**Expected Results**:
- Topic should exist
- Message count should match Oracle row inserts (±1%)
- Consumer lag should be < 1000 messages
- Replication lag < 100ms (from Grafana)

---

### STEP 8: Generate Client Report

Create a summary document with:

#### A. Test Configuration
```
Table: ORDERMGMT.MTX_TRANSACTION_ITEMS
Mode: Maximum Load (items_only)
Virtual Users: 4 (or vcpu)
Duration: 60 minutes
Date: 2026-04-15
```

#### B. Performance Metrics

| Metric | Value |
|--------|-------|
| Rows Inserted | X,XXX,XXX |
| Insert Rate | X,XXX rows/sec |
| Total Redo Generated | XX.X GB |
| Peak Redo Rate | XX.X MB/sec |
| Archive Log Switches | XXX |
| Average Replication Lag | < 100ms |
| Peak Replication Lag | < 200ms |
| Data Loss | 0% |
| Uptime | 100% |

#### C. Grafana Evidence
- Screenshot: Baseline (test start)
- Screenshot: Peak load (maximum throughput)
- Screenshot: Final state (test end)

#### D. Key Findings
```
✅ Successfully generated XXX GB CDC load on MTX_TRANSACTION_ITEMS
✅ Maintained replication lag < 100ms throughout test
✅ Zero data loss - all events captured in Kafka
✅ Infrastructure handled peak load of XX MB/sec
✅ No errors or failures during test period
```

---

## Troubleshooting

### Issue: HammerDB connection fails

**Solution**:
```bash
# Verify TNS connectivity from HammerDB VM
ssh -i /Users/maniselvank/Desktop/Mani/ssh-key-2026-03-12.key opc@129.146.31.189
tnsping RAC_XSTRPDB_POC
sqlplus ordermgmt/'ConFL#_uent12'@RAC_XSTRPDB_POC
```

### Issue: XStream lag increasing

**Solution**:
```sql
-- Check capture process status
SELECT capture_name, status, state
FROM gv$xstream_capture;

-- If PAUSED, restart:
BEGIN
  DBMS_XSTREAM_ADM.START_OUTBOUND('CONFLUENT_XOUT1');
END;
/
```

### Issue: Archive log space full (ORA-00257)

**Solution**:
```sql
-- Check FRA usage
SELECT * FROM v$recovery_file_dest;

-- Clear old archive logs
DELETE FROM v$archived_log WHERE deleted = 'YES';
RMAN TARGET / NOCATALOG <<EOF
DELETE NOPROMPT ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-1';
EXIT;
EOF
```

### Issue: Kafka lag building up

**Solution**:
```bash
# Check connector status
curl http://137.131.53.98:8083/connectors/oracle-xstream-source/status

# Restart connector if needed
curl -X POST http://137.131.53.98:8083/connectors/oracle-xstream-source/restart
```

---

## Quick Reference Commands

### Check Test Progress (from Mac)

```bash
# Watch HammerDB output
ssh -i /Users/maniselvank/Desktop/Mani/ssh-key-2026-03-12.key opc@129.146.31.189 \
  "tail -f ~/hammerdb-mtx-test/mtx-run.log"

# Check current row count
sqlplus -S ordermgmt/'ConFL#_uent12'@//10.0.0.29:1521/DB0312_r8n_phx.sub01061249390.xstrmconnectdb2.oraclevcn.com <<EOF
SELECT COUNT(*) FROM MTX_TRANSACTION_ITEMS;
EXIT;
EOF
```

### Stop Test Early (if needed)

```bash
# Kill HammerDB process on VM
ssh -i /Users/maniselvank/Desktop/Mani/ssh-key-2026-03-12.key opc@129.146.31.189 \
  "pkill -f hammerdb"
```

---

## Expected Timeline

| Phase | Duration | Description |
|-------|----------|-------------|
| Validation | 10 min | Run validate-mtx-test-setup.sh |
| Preparation | 5 min | Open Grafana, prepare monitoring |
| Load Test | 60 min | HammerDB execution (configurable) |
| Metrics Collection | 10 min | Gather results, query Kafka |
| Analysis | 20 min | Review logs, calculate metrics |
| Report Generation | 30 min | Prepare client presentation |
| **Total** | **~2.5 hours** | End-to-end execution |

---

## Success Criteria

- [x] MTX_TRANSACTION_ITEMS rows increased significantly (> 100K)
- [x] Replication lag stayed < 100ms for 90%+ of test
- [x] Zero errors in HammerDB output
- [x] Kafka topic received all events (match Oracle inserts)
- [x] Grafana dashboard shows consistent throughput
- [x] No ORA-00257 (archive log space) errors
- [x] XStream capture remained ENABLED throughout

---

## Contact & Support

- **Oracle Database**: Check alert.log at `$ORACLE_BASE/diag/rdbms/`
- **XStream Issues**: See oracle-xstream-cdc-poc/oracle-database/09-check-and-start-xstream.sql
- **Kafka Issues**: Check connector logs at connector VM
- **HammerDB Issues**: See hammerdb-mtx-vm-bundle/*.sh scripts

---

**Ready to execute?**

```bash
# Step 1: Validate
./validate-mtx-test-setup.sh

# Step 2: Run test (if validation passes)
./run-mtx-load-test.sh

# Step 3: Review results
cat mtx-test-results-<timestamp>/SUMMARY.md
```

Good luck! 🚀
