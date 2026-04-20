-- ORDERMGMT.MTX* rows in DBA_XSTREAM_RULES (outbound capture) — run as SYSDBA.
-- Expect one row per onboarded MTX table when ADD_TABLE_RULES was run (see ug-prod-onboard-xstream.sh).
--
-- Usage:
--   cd ~/oracle-xstream-cdc-poc/oracle-database
--   sqlplus sys/...@//host:1521/SERVICE as sysdba @verify-mtx-xstream-rules.sql
--
-- For full prereqs (supplemental log + grants + rules), use: @verify-mtx-cdc-prereqs.sql
SET PAGESIZE 200 LINESIZE 220 VERIFY OFF FEEDBACK ON

PROMPT === PDB ===
ALTER SESSION SET CONTAINER = XSTRPDB;

PROMPT === DBA_XSTREAM_RULES — ORDERMGMT tables starting with MTX ===
SELECT schema_name, object_name, rule_name
FROM   dba_xstream_rules
WHERE  schema_name = 'ORDERMGMT'
AND    object_name LIKE 'MTX%'
ORDER BY object_name;

PROMPT === Count: MTX rules vs non-MTX ORDERMGMT (should be 0 non-MTX for MTX-only policy) ===
SELECT SUM(CASE WHEN object_name LIKE 'MTX%' THEN 1 ELSE 0 END) AS mtx_rules,
       SUM(CASE WHEN object_name NOT LIKE 'MTX%' OR object_name IS NULL THEN 1 ELSE 0 END) AS non_mtx_ordermgmt_rules
FROM   dba_xstream_rules
WHERE  schema_name = 'ORDERMGMT';

PROMPT === DBA_APPLY (outbound) — status (query may need CDB; re-switch if empty) ===
ALTER SESSION SET CONTAINER = CDB$ROOT;
SELECT apply_name, status, apply_user
FROM   dba_apply
WHERE  UPPER(apply_name) LIKE '%XOUT%' OR UPPER(apply_name) LIKE '%CONFLUENT%'
ORDER BY apply_name;
