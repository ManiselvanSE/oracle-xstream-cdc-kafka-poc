-- =============================================================================
-- XStream / capture rules for TPCC (and ORDERMGMT) — run as SYSDBA
-- Use when DBA_XSTREAM_RULES is empty but you need to confirm capture still filters tables.
-- =============================================================================
SET PAGESIZE 200 LINESIZE 220 VERIFY OFF FEEDBACK ON

PROMPT === DBA_XSTREAM_RULES (preferred) ===
PROMPT === For ORDERMGMT.MTX* only, also run: verify-mtx-xstream-rules.sql ===
SELECT schema_name, object_name, rule_name
FROM   dba_xstream_rules
WHERE  schema_name IN ('ORDERMGMT', 'TPCC')
ORDER BY schema_name, object_name;

PROMPT === DBA_CAPTURE (CDB) — CONFLUENT_XOUT1 ===
ALTER SESSION SET CONTAINER = CDB$ROOT;
SELECT capture_name, status, capture_user
FROM   dba_capture
WHERE  capture_name LIKE '%XOUT%' OR capture_name LIKE '%CONFLUENT%';

PROMPT === DBA_APPLY (outbound xout) ===
SELECT apply_name, status, apply_user
FROM   dba_apply
WHERE  UPPER(apply_name) LIKE '%XOUT%' OR UPPER(apply_name) LIKE '%CONFLUENT%'
ORDER BY apply_name;

PROMPT === Done. If section 1 has no TPCC rows, run hammerdb-tpcc-onboard-xstream.sh (ADD_TABLE_RULES). ===
PROMPT === (Some releases show few rows in DBA_XSTREAM_RULES even when capture works — compare to capture health above.) ===
