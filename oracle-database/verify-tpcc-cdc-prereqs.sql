-- =============================================================================
-- Verify TPCC is ready for XStream CDC (run in PDB as SYSDBA or DBA)
-- sqlplus sys/...@//host:1521/SERVICE as sysdba @verify-tpcc-cdc-prereqs.sql
-- =============================================================================
SET PAGESIZE 200 LINESIZE 200 VERIFY OFF FEEDBACK ON

PROMPT === PDB ===
ALTER SESSION SET CONTAINER = XSTRPDB;

PROMPT === Supplemental log groups on TPCC (expect rows per table) ===
SELECT owner, table_name, log_group_name, log_group_type
FROM   dba_log_groups
WHERE  owner = 'TPCC'
ORDER BY table_name;

PROMPT === GRANT SELECT to connector user c##cfltuser ===
SELECT owner, table_name, privilege
FROM   dba_tab_privs
WHERE  grantee = 'C##CFLTUSER'
AND    owner = 'TPCC'
ORDER BY table_name;

PROMPT === XStream rules for TPCC (expect rows once 11-add-table-to-cdc.sql has been run) ===
SELECT schema_name, object_name, rule_name
FROM   dba_xstream_rules
WHERE  schema_name = 'TPCC'
ORDER BY object_name;

PROMPT === Capture process (CDB) — expect CONFLUENT_XOUT1 ===
ALTER SESSION SET CONTAINER = CDB$ROOT;
SELECT capture_name, status FROM dba_capture
WHERE  capture_name LIKE '%XOUT%' OR capture_name LIKE '%CONFLUENT%';

PROMPT Done. If TPCC rules or supplemental log rows are missing, run hammerdb-tpcc-onboard-xstream.sql and hammerdb-tpcc-onboard-xstream.sh
