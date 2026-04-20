-- ORDERMGMT.MTX* CDC path — run as SYS AS SYSDBA (captures rules live in CDB).
-- Use when Grafana shows ~0 MTX throughput but HammerDB load is running.
--
--   sqlplus sys/...@//host:1521/SERVICE as sysdba @diagnose-mtx-cdc.sql
--
SET PAGESIZE 200 LINESIZE 220 VERIFY OFF FEEDBACK ON

PROMPT === 1) PDB — supplemental log groups on ORDERMGMT.MTX* (expect rows) ===
ALTER SESSION SET CONTAINER = XSTRPDB;
SELECT COUNT(*) AS mtx_log_groups
FROM   dba_log_groups
WHERE  owner = 'ORDERMGMT' AND table_name LIKE 'MTX%';

PROMPT === 2) XStream rules for ORDERMGMT.MTX* (expect >0 rows after onboarding) ===
SELECT COUNT(*) AS mtx_rules FROM dba_xstream_rules
WHERE schema_name = 'ORDERMGMT' AND object_name LIKE 'MTX%';

SELECT schema_name, object_name
FROM   dba_xstream_rules
WHERE  schema_name = 'ORDERMGMT' AND object_name LIKE 'MTX%'
ORDER BY object_name
FETCH FIRST 30 ROWS ONLY;

PROMPT === 3) Connector read user — GRANT SELECT on MTX tables (sample) ===
SELECT COUNT(*) AS grants_to_cflt
FROM   dba_tab_privs
WHERE  grantee = 'C##CFLTUSER' AND owner = 'ORDERMGMT' AND table_name LIKE 'MTX%';

PROMPT === 4) Recent DML — row counts (run HammerDB, re-run; counts should rise) ===
-- Heavy on large tables; comment out if too slow.
SELECT 'MTX_TRANSACTION_HEADER' AS tbl, COUNT(*) AS row_cnt FROM ORDERMGMT.MTX_TRANSACTION_HEADER
UNION ALL SELECT 'MTX_TRANSACTION_ITEMS', COUNT(*) FROM ORDERMGMT.MTX_TRANSACTION_ITEMS;

PROMPT === 5) CDB — capture process (expect ENABLED) ===
ALTER SESSION SET CONTAINER = CDB$ROOT;
SELECT capture_name, status, capture_user
FROM   dba_capture
WHERE  capture_name LIKE '%XOUT%' OR capture_name LIKE '%CONFLUENT%';

PROMPT === Done. If (1)=0 run ordermgmt-mtx-supplemental-logging.sql ===
PROMPT If (2)=0 run ug-prod-onboard-xstream.sh / 11-add-table-to-cdc.sql ===
PROMPT If (3)=0 run ordermgmt-mtx-grant-cfltuser.sql ===
PROMPT If (4) static under load — HammerDB not committing or wrong DB/service ===
PROMPT If (5) not ENABLED — fix capture before expecting Kafka throughput ===
