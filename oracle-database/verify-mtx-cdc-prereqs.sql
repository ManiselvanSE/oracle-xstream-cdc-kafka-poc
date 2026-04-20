-- =============================================================================
-- Verify ORDERMGMT.MTX* is ready for XStream CDC (run as SYSDBA)
-- Same checks as verify-tpcc-cdc-prereqs.sql but for ORDERMGMT tables named MTX%.
--
-- Usage (from oracle-database directory, or use full path to this file):
--   sqlplus sys/...@//host:1521/SERVICE as sysdba @verify-mtx-cdc-prereqs.sql
--
-- If your PDB name is not XSTRPDB, edit the ALTER SESSION line below.
-- =============================================================================
SET PAGESIZE 200 LINESIZE 220 VERIFY OFF FEEDBACK ON

PROMPT === PDB (must match connector database.pdb.name) ===
ALTER SESSION SET CONTAINER = XSTRPDB;

PROMPT === Supplemental log groups on ORDERMGMT.MTX* (expect rows per captured table) ===
SELECT owner, table_name, log_group_name, log_group_type
FROM   dba_log_groups
WHERE  owner = 'ORDERMGMT'
AND    table_name LIKE 'MTX%'
ORDER BY table_name;

PROMPT === GRANT SELECT to connector user C##CFLTUSER on ORDERMGMT.MTX* ===
SELECT owner, table_name, privilege
FROM   dba_tab_privs
WHERE  grantee = 'C##CFLTUSER'
AND    owner = 'ORDERMGMT'
AND    table_name LIKE 'MTX%'
ORDER BY table_name;

PROMPT === XStream rules for ORDERMGMT.MTX* (expect rows after ug-prod-onboard-xstream.sh / 11-add-table-to-cdc.sql) ===
SELECT schema_name, object_name, rule_name
FROM   dba_xstream_rules
WHERE  schema_name = 'ORDERMGMT'
AND    object_name LIKE 'MTX%'
ORDER BY object_name;

PROMPT === Capture process (CDB) — expect CONFLUENT_XOUT1 ENABLED ===
ALTER SESSION SET CONTAINER = CDB$ROOT;
SELECT capture_name, status
FROM   dba_capture
WHERE  capture_name LIKE '%XOUT%' OR capture_name LIKE '%CONFLUENT%';

PROMPT === Done. ===
PROMPT If supplemental log is missing: @ordermgmt-mtx-supplemental-logging.sql
PROMPT If GRANT SELECT missing for any MTX table: @ordermgmt-mtx-grant-cfltuser.sql
PROMPT If XStream rules missing: ug-prod-onboard-xstream.sh
