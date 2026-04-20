-- =============================================================================
-- Compare ORDERMGMT vs TPCC CDC prerequisites (XStream) in PDB XSTRPDB
-- Run as SYS (or user with DBA + SELECT_CATALOG_ROLE), e.g.:
--   sqlplus sys/password@//host:1521/<SERVICE> as sysdba @verify-ordermgmt-vs-tpcc-cdc-prereqs.sql
--
-- Compares: supplemental log groups, GRANT SELECT to C##CFLTUSER, DBA_XSTREAM_RULES
-- Plus CDB: capture (and apply if present). Connector user is C##CFLTUSER (Kafka).
--
-- Fix gaps:
--   ORDERMGMT — ug-prod / repo onboarding scripts (03-supplemental-logging, ug-prod-onboard-xstream.*)
--   TPCC      — hammerdb-tpcc-onboard-xstream.sql + hammerdb-tpcc-onboard-xstream.sh (fix-tpcc-xstream-oracle.sh)
-- =============================================================================
SET PAGESIZE 500 LINESIZE 220 VERIFY OFF FEEDBACK ON TIMING OFF

PROMPT
PROMPT ========== 0) DATABASE-LEVEL supplemental logging (CDB) ==========
ALTER SESSION SET CONTAINER = CDB$ROOT;
SELECT SUPPLEMENTAL_LOG_DATA_MIN AS min_log,
       SUPPLEMENTAL_LOG_DATA_ALL AS all_col_log
FROM   v$database;

PROMPT
PROMPT ========== 1) PDB and schema users ==========
ALTER SESSION SET CONTAINER = XSTRPDB;
SELECT username, account_status, default_tablespace
FROM   dba_users
WHERE  username IN ('ORDERMGMT','TPCC','C##CFLTUSER','C##XSTRMADMIN')
ORDER BY username;

PROMPT
PROMPT ========== 2) SUMMARY COUNTS: ORDERMGMT vs TPCC ==========
SELECT 'ORDERMGMT' AS schema_name,
       (SELECT COUNT(DISTINCT table_name) FROM dba_log_groups WHERE owner = 'ORDERMGMT') AS tables_with_log_group,
       (SELECT COUNT(*) FROM dba_tab_privs WHERE grantee = 'C##CFLTUSER' AND owner = 'ORDERMGMT' AND privilege = 'SELECT') AS grants_select_to_cflt,
       (SELECT COUNT(*) FROM dba_xstream_rules WHERE schema_name = 'ORDERMGMT') AS xstream_rule_rows
FROM   dual
UNION ALL
SELECT 'TPCC',
       (SELECT COUNT(DISTINCT table_name) FROM dba_log_groups WHERE owner = 'TPCC'),
       (SELECT COUNT(*) FROM dba_tab_privs WHERE grantee = 'C##CFLTUSER' AND owner = 'TPCC' AND privilege = 'SELECT'),
       (SELECT COUNT(*) FROM dba_xstream_rules WHERE schema_name = 'TPCC')
FROM   dual;

PROMPT
PROMPT === Expected (rule of thumb): TPCC has 9 tables / 9 grants / 9 rules if fully onboarded ===
PROMPT === ORDERMGMT counts depend on how many tables were added to capture (often >> 9) ===

PROMPT
PROMPT ========== 3) SUPPLEMENTAL LOG — detail by schema ==========
SELECT owner, table_name, log_group_name, log_group_type
FROM   dba_log_groups
WHERE  owner IN ('ORDERMGMT', 'TPCC')
ORDER BY owner, table_name;

PROMPT
PROMPT ========== 4) GAP: application tables without a row in DBA_LOG_GROUPS ==========
PROMPT === (If rows appear here, run supplemental logging ALTERs for those tables) ===
SELECT s.owner, s.table_name
FROM   dba_tables s
WHERE  s.owner IN ('ORDERMGMT', 'TPCC')
AND    s.temporary = 'N'
AND    s.table_name NOT LIKE 'BIN$%'
AND    NOT EXISTS (
         SELECT 1 FROM dba_log_groups lg
         WHERE  lg.owner = s.owner AND lg.table_name = s.table_name
       )
ORDER BY s.owner, s.table_name;

PROMPT
PROMPT ========== 5) GRANT SELECT to C##CFLTUSER (connector) — by schema ==========
SELECT owner, table_name, privilege
FROM   dba_tab_privs
WHERE  grantee = 'C##CFLTUSER'
AND    owner IN ('ORDERMGMT', 'TPCC')
AND    privilege = 'SELECT'
ORDER BY owner, table_name;

PROMPT
PROMPT ========== 6) GAP: tables in schema but no SELECT grant to C##CFLTUSER ==========
SELECT s.owner, s.table_name
FROM   dba_tables s
WHERE  s.owner IN ('ORDERMGMT', 'TPCC')
AND    s.temporary = 'N'
AND    s.table_name NOT LIKE 'BIN$%'
AND    NOT EXISTS (
         SELECT 1 FROM dba_tab_privs p
         WHERE  p.grantee = 'C##CFLTUSER'
         AND    p.owner = s.owner
         AND    p.table_name = s.table_name
         AND    p.privilege = 'SELECT'
       )
ORDER BY s.owner, s.table_name;

PROMPT
PROMPT ========== 7) XSTREAM RULES — ORDERMGMT vs TPCC ==========
SELECT schema_name, object_name, rule_name
FROM   dba_xstream_rules
WHERE  schema_name IN ('ORDERMGMT', 'TPCC')
ORDER BY schema_name, object_name, rule_name;

PROMPT
PROMPT ========== 8) CDB: capture / apply (XStream) ==========
ALTER SESSION SET CONTAINER = CDB$ROOT;
SELECT capture_name, status, capture_user
FROM   dba_capture
WHERE  capture_name LIKE '%XOUT%' OR capture_name LIKE '%CONFLUENT%'
ORDER BY capture_name;

SELECT apply_name, status, apply_user
FROM   dba_apply
WHERE  apply_name LIKE '%XOUT%' OR apply_name LIKE '%CONFLUENT%'
ORDER BY apply_name;

PROMPT
PROMPT ========== Done ==========
PROMPT Interpretation:
PROMPT  • If ORDERMGMT counts >> 0 and TPCC counts = 0 or low: run TPCC-only onboarding (fix-tpcc-xstream-oracle.sh).
PROMPT  • If section 4 or 6 shows gaps for TPCC: hammerdb-tpcc-onboard-xstream.sql (log + grants).
PROMPT  • If section 7 empty for TPCC: hammerdb-tpcc-onboard-xstream.sh (ADD_TABLE_RULES).
PROMPT  • Shared DB settings (8) apply to both schemas; ORDERMGMT working implies capture is up — TPCC issues are usually table-level rules/grants.
PROMPT
