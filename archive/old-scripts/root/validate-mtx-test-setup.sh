#!/usr/bin/env bash
# =============================================================================
# Validation Script: MTX_TRANSACTION_ITEMS Load Test Prerequisites
# Run this before starting the HammerDB load test to ensure all components are ready
# =============================================================================

set -euo pipefail

echo "=========================================="
echo "MTX_TRANSACTION_ITEMS Load Test Validation"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
WARN=0

check_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASS++))
}

check_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAIL++))
}

check_warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
    ((WARN++))
}

echo "=== 1. ORACLE DATABASE VALIDATION ==="
echo ""

# Check Oracle connectivity
echo "Checking Oracle database connectivity..."
if sqlplus -S sys/'ConFL#_uent12'@//10.0.0.29:1521/DB0312_r8n_phx.sub01061249390.xstrmconnectdb2.oraclevcn.com as sysdba <<EOF > /tmp/oracle_check.log 2>&1
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT 'ORACLE_CONNECTED' FROM dual;
EXIT;
EOF
then
    if grep -q "ORACLE_CONNECTED" /tmp/oracle_check.log; then
        check_pass "Oracle database is accessible"
    else
        check_fail "Oracle database connection failed - check credentials"
        cat /tmp/oracle_check.log
    fi
else
    check_fail "Cannot connect to Oracle database"
    cat /tmp/oracle_check.log
fi

# Check XStream configuration for MTX_TRANSACTION_ITEMS
echo ""
echo "Checking XStream capture rules for MTX_TRANSACTION_ITEMS..."
sqlplus -S sys/'ConFL#_uent12'@//10.0.0.29:1521/DB0312_r8n_phx.sub01061249390.xstrmconnectdb2.oraclevcn.com as sysdba <<EOF > /tmp/xstream_check.log 2>&1
SET PAGESIZE 100 FEEDBACK OFF VERIFY OFF HEADING ON ECHO OFF LINESIZE 200
COL table_name FORMAT A30
COL streams_name FORMAT A20
COL rule_type FORMAT A15

SELECT table_owner, table_name, streams_name, rule_type
FROM dba_streams_table_rules
WHERE streams_name = 'CONFLUENT_XOUT1'
  AND table_owner = 'ORDERMGMT'
  AND table_name = 'MTX_TRANSACTION_ITEMS';

EXIT;
EOF

if grep -q "MTX_TRANSACTION_ITEMS" /tmp/xstream_check.log; then
    check_pass "MTX_TRANSACTION_ITEMS is configured in XStream"
    cat /tmp/xstream_check.log | grep -A5 "TABLE_OWNER"
else
    check_fail "MTX_TRANSACTION_ITEMS NOT found in XStream capture rules"
    echo "You need to add it using:"
    echo "  DBMS_XSTREAM_ADM.ADD_TABLE_RULES(..."
    cat /tmp/xstream_check.log
fi

# Check XStream outbound status
echo ""
echo "Checking XStream outbound server status..."
sqlplus -S sys/'ConFL#_uent12'@//10.0.0.29:1521/DB0312_r8n_phx.sub01061249390.xstrmconnectdb2.oraclevcn.com as sysdba <<EOF > /tmp/xstream_status.log 2>&1
SET PAGESIZE 100 FEEDBACK OFF VERIFY OFF HEADING ON ECHO OFF LINESIZE 200
COL server_name FORMAT A20
COL capture_name FORMAT A20
COL capture_user FORMAT A20
COL connect_user FORMAT A20
COL source_database FORMAT A20

SELECT server_name, capture_name, capture_user, connect_user, source_database
FROM dba_xstream_outbound
WHERE server_name = 'CONFLUENT_XOUT1';

-- Check if capture process is running
SELECT capture_name, status, state
FROM gv\$xstream_capture
WHERE capture_name = 'CONFLUENT_CAP1';

EXIT;
EOF

if grep -q "CONFLUENT_XOUT1" /tmp/xstream_status.log; then
    check_pass "XStream outbound server CONFLUENT_XOUT1 exists"
    cat /tmp/xstream_status.log | grep -A10 "SERVER_NAME"
else
    check_fail "XStream outbound server not configured properly"
    cat /tmp/xstream_status.log
fi

# Check MTX_TRANSACTION_ITEMS row count
echo ""
echo "Checking MTX_TRANSACTION_ITEMS current row count..."
sqlplus -S ordermgmt/'ConFL#_uent12'@//10.0.0.29:1521/DB0312_r8n_phx.sub01061249390.xstrmconnectdb2.oraclevcn.com <<EOF > /tmp/mtx_count.log 2>&1
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT 'MTX_ROWS:' || COUNT(*) FROM MTX_TRANSACTION_ITEMS;
EXIT;
EOF

if grep -q "MTX_ROWS:" /tmp/mtx_count.log; then
    ROW_COUNT=$(grep "MTX_ROWS:" /tmp/mtx_count.log | cut -d: -f2 | tr -d ' ')
    check_pass "MTX_TRANSACTION_ITEMS current rows: ${ROW_COUNT}"
else
    check_warn "Could not get MTX_TRANSACTION_ITEMS row count"
    cat /tmp/mtx_count.log
fi

# Check archivelog mode and FRA space
echo ""
echo "Checking archivelog mode and FRA space..."
sqlplus -S sys/'ConFL#_uent12'@//10.0.0.29:1521/DB0312_r8n_phx.sub01061249390.xstrmconnectdb2.oraclevcn.com as sysdba <<EOF > /tmp/archive_check.log 2>&1
SET PAGESIZE 100 FEEDBACK OFF VERIFY OFF HEADING ON ECHO OFF LINESIZE 200
SELECT log_mode FROM v\$database;
SELECT name, space_limit/1024/1024/1024 AS space_limit_gb,
       space_used/1024/1024/1024 AS space_used_gb,
       ROUND((space_used/space_limit)*100, 2) AS pct_used
FROM v\$recovery_file_dest;
EXIT;
EOF

if grep -q "ARCHIVELOG" /tmp/archive_check.log; then
    check_pass "Database is in ARCHIVELOG mode"
else
    check_fail "Database is NOT in ARCHIVELOG mode"
fi

cat /tmp/archive_check.log | grep -A5 "NAME"

echo ""
echo "=== 2. KAFKA & CONNECTOR VALIDATION ==="
echo ""

# We'll do these checks from the connector VM via SSH

echo ""
echo "=== 3. HAMMERDB VM VALIDATION ==="
echo ""

echo "Testing SSH connectivity to HammerDB VM..."
if ssh -i /Users/maniselvank/Desktop/Mani/ssh-key-2026-03-12.key -o ConnectTimeout=5 opc@129.146.31.189 "echo 'SSH_OK'" 2>/dev/null | grep -q "SSH_OK"; then
    check_pass "SSH connection to HammerDB VM successful"
else
    check_fail "Cannot SSH to HammerDB VM (129.146.31.189)"
fi

echo ""
echo "Checking HammerDB installation..."
ssh -i /Users/maniselvank/Desktop/Mani/ssh-key-2026-03-12.key opc@129.146.31.189 <<'EOSSH' > /tmp/hammerdb_check.log 2>&1
# Check HammerDB installation
if [ -d "/opt/HammerDB-5.0" ]; then
    echo "HAMMERDB_INSTALLED"
    ls -la /opt/HammerDB-5.0/hammerdbcli 2>&1
else
    echo "HAMMERDB_NOT_FOUND"
fi

# Check Oracle Instant Client
if [ -d "/usr/lib/oracle/19.29/client64" ] || [ -d "/usr/lib/oracle/19.30/client64" ]; then
    echo "ORACLE_CLIENT_INSTALLED"
    rpm -qa | grep oracle-instantclient
else
    echo "ORACLE_CLIENT_NOT_FOUND"
fi

# Check TNS configuration
if [ -f "$HOME/oracle/network/admin/tnsnames.ora" ]; then
    echo "TNS_CONFIG_EXISTS"
    grep -i "RAC_XSTRPDB_POC" $HOME/oracle/network/admin/tnsnames.ora | head -5
else
    echo "TNS_CONFIG_NOT_FOUND"
fi
EOSSH

if grep -q "HAMMERDB_INSTALLED" /tmp/hammerdb_check.log; then
    check_pass "HammerDB 5.0 is installed"
else
    check_fail "HammerDB is not installed on the VM"
fi

if grep -q "ORACLE_CLIENT_INSTALLED" /tmp/hammerdb_check.log; then
    check_pass "Oracle Instant Client is installed"
else
    check_fail "Oracle Instant Client is not installed"
fi

if grep -q "TNS_CONFIG_EXISTS" /tmp/hammerdb_check.log; then
    check_pass "TNS configuration file exists"
    if grep -q "RAC_XSTRPDB_POC" /tmp/hammerdb_check.log; then
        check_pass "RAC_XSTRPDB_POC TNS entry found"
    else
        check_warn "RAC_XSTRPDB_POC TNS entry not found"
    fi
else
    check_warn "TNS configuration not found"
fi

cat /tmp/hammerdb_check.log

echo ""
echo "Testing Oracle connectivity from HammerDB VM..."
ssh -i /Users/maniselvank/Desktop/Mani/ssh-key-2026-03-12.key opc@129.146.31.189 <<'EOSSH' > /tmp/hammerdb_oracle.log 2>&1
export ORACLE_HOME=/usr/lib/oracle/19.29/client64
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export PATH=$ORACLE_HOME/bin:$PATH
export TNS_ADMIN=$HOME/oracle/network/admin

echo "Testing SQLPlus connection..."
echo "SELECT 'CONNECTED_FROM_HAMMERDB_VM' FROM dual;" | sqlplus -S ordermgmt/'ConFL#_uent12'@RAC_XSTRPDB_POC
EOSSH

if grep -q "CONNECTED_FROM_HAMMERDB_VM" /tmp/hammerdb_oracle.log; then
    check_pass "Oracle connection from HammerDB VM works"
else
    check_fail "Cannot connect to Oracle from HammerDB VM"
    cat /tmp/hammerdb_oracle.log
fi

echo ""
echo "=== 4. GRAFANA DASHBOARD VALIDATION ==="
echo ""

echo "Checking Grafana dashboard accessibility..."
if curl -s -o /dev/null -w "%{http_code}" "http://137.131.53.98:3000/api/health" | grep -q "200"; then
    check_pass "Grafana is accessible at http://137.131.53.98:3000"
else
    check_warn "Grafana may not be accessible (check if it's running)"
fi

echo ""
echo "Dashboard URL: http://137.131.53.98:3000/d/xstream-throughput-performance/oracle-xstream-cdc-throughput-and-performance?orgId=1&refresh=10s"

echo ""
echo "=========================================="
echo "VALIDATION SUMMARY"
echo "=========================================="
echo -e "${GREEN}PASSED: ${PASS}${NC}"
echo -e "${RED}FAILED: ${FAIL}${NC}"
echo -e "${YELLOW}WARNINGS: ${WARN}${NC}"
echo ""

if [ $FAIL -gt 0 ]; then
    echo -e "${RED}⚠ CRITICAL ISSUES FOUND - Fix before running load test${NC}"
    exit 1
elif [ $WARN -gt 0 ]; then
    echo -e "${YELLOW}⚠ Some warnings found - Review before proceeding${NC}"
    exit 0
else
    echo -e "${GREEN}✓ All validations passed - Ready for load test${NC}"
    exit 0
fi

# Cleanup
rm -f /tmp/oracle_check.log /tmp/xstream_check.log /tmp/xstream_status.log /tmp/mtx_count.log /tmp/archive_check.log /tmp/hammerdb_check.log /tmp/hammerdb_oracle.log
