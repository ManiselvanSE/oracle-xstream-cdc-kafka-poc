-- =============================================================================
-- Verify XStream Outbound (CDB) + XStream rules for PDB schemas
-- RUN ONLY AS A FILE:
--   sqlplus -L sys/pwd@//host:1521/<CDB_service> AS SYSDBA @08-verify-xstream-outbound.sql
--
-- ORDERMGMT and TPCC are USER schemas in PDB XSTRPDB (not in CDB$ROOT).
-- Rule rows may appear in DBA_XSTREAM_RULES with session set to XSTRPDB, and/or
-- in CDB_XSTREAM_RULES at CDB$ROOT with CON_ID = that PDB (multitenant catalog).
-- =============================================================================

SET PAGESIZE 100 LINESIZE 200 FEEDBACK ON VERIFY OFF TIMING OFF
SET DEFINE OFF

PROMPT
PROMPT *** Use @script only. Do not paste into SQL*Plus. ***
PROMPT

ALTER SESSION SET CONTAINER = CDB$ROOT;

PROMPT ========== 0. Container ==========
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS current_container FROM DUAL;

PROMPT ========== 1. DBA_XSTREAM_OUTBOUND ==========
SELECT SERVER_NAME, CONNECT_USER, CAPTURE_NAME, QUEUE_OWNER, QUEUE_NAME, STATUS FROM DBA_XSTREAM_OUTBOUND;

PROMPT ========== 2. DBA_CAPTURE (CONFLUENT_XOUT1) ==========
SELECT CAPTURE_NAME, QUEUE_OWNER, QUEUE_NAME, STATUS, START_SCN, SOURCE_DATABASE FROM DBA_CAPTURE WHERE CAPTURE_NAME = 'CONFLUENT_XOUT1';

PROMPT ========== 3. DBA_CAPTURE_PARAMETERS (first 40 by PARAMETER name) ==========
SELECT CAPTURE_NAME, PARAMETER, VALUE FROM (SELECT CAPTURE_NAME, PARAMETER, VALUE FROM DBA_CAPTURE_PARAMETERS WHERE CAPTURE_NAME = 'CONFLUENT_XOUT1' ORDER BY PARAMETER) WHERE ROWNUM <= 40;

PROMPT ========== 4. GV$XSTREAM_CAPTURE (RAC, all instances) ==========
SELECT INST_ID, CAPTURE_NAME, STATE, STARTUP_TIME FROM GV$XSTREAM_CAPTURE WHERE CAPTURE_NAME = 'CONFLUENT_XOUT1';

PROMPT ========== 5. GV$SERVICES (XOUT network_name = connector database.service.name) ==========
SELECT INST_ID, SERVICE_ID, NAME, NETWORK_NAME FROM GV$SERVICES WHERE UPPER(NAME) LIKE '%XOUT%' OR UPPER(NETWORK_NAME) LIKE '%XOUT%';

PROMPT ========== 6. DBA_APPLY (xout) ==========
SELECT APPLY_NAME, QUEUE_OWNER, QUEUE_NAME, STATUS FROM DBA_APPLY WHERE APPLY_NAME = 'XOUT';

PROMPT ========== 7a. PDB XSTRPDB: map PDB (schemas ORDERMGMT/TPCC live here, not in CDB$ROOT) ==========
ALTER SESSION SET CONTAINER = XSTRPDB;
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS pdb_session, SYS_CONTEXT('USERENV','CURRENT_SCHEMA') AS current_schema FROM DUAL;

PROMPT ========== 7b. PDB XSTRPDB: DBA_XSTREAM_RULES counts for ORDERMGMT / TPCC ==========
SELECT s.schema_name, NVL(r.cnt, 0) AS rule_rows FROM (SELECT 'TPCC' AS schema_name FROM DUAL UNION ALL SELECT 'ORDERMGMT' FROM DUAL) s LEFT JOIN (SELECT schema_name, COUNT(*) AS cnt FROM dba_xstream_rules WHERE schema_name IN ('TPCC','ORDERMGMT') GROUP BY schema_name) r ON r.schema_name = s.schema_name ORDER BY s.schema_name;

PROMPT ========== 7c. CDB$ROOT: CDB_XSTREAM_RULES for PDB XSTRPDB (CON_ID) ==========
ALTER SESSION SET CONTAINER = CDB$ROOT;
SELECT con_id, name AS pdb_name FROM v$pdbs WHERE name = 'XSTRPDB';

SELECT s.schema_name, NVL(x.cnt, 0) AS rule_rows_cdb_view FROM (SELECT 'TPCC' AS schema_name FROM DUAL UNION ALL SELECT 'ORDERMGMT' FROM DUAL) s LEFT JOIN (SELECT schema_name, COUNT(*) AS cnt FROM cdb_xstream_rules WHERE con_id = (SELECT con_id FROM v$pdbs WHERE name = 'XSTRPDB') AND schema_name IN ('TPCC','ORDERMGMT') GROUP BY schema_name) x ON x.schema_name = s.schema_name ORDER BY s.schema_name;

PROMPT ========== 7d. CDB$ROOT: sample rows CDB_XSTREAM_RULES (XSTRPDB, max 25) ==========
SELECT schema_name, object_name, rule_name FROM (SELECT schema_name, object_name, rule_name FROM cdb_xstream_rules WHERE con_id = (SELECT con_id FROM v$pdbs WHERE name = 'XSTRPDB') AND schema_name IN ('ORDERMGMT','TPCC') ORDER BY schema_name, object_name) WHERE ROWNUM <= 25;

PROMPT ========== 7e. Capture INCLUDE_OBJECTS (may list table scope when VALUE non-empty) ==========
SELECT PARAMETER, LENGTH(VALUE) AS value_bytes, SUBSTR(VALUE,1,2000) AS value_preview FROM DBA_CAPTURE_PARAMETERS WHERE CAPTURE_NAME = 'CONFLUENT_XOUT1' AND PARAMETER = 'INCLUDE_OBJECTS';

PROMPT If 7b/7c/7d are 0 and TPCC Kafka empty: hammerdb-tpcc-onboard-xstream.sql + hammerdb-tpcc-onboard-xstream.sh

PROMPT ========== 8. Container (expect CDB$ROOT) ==========
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS current_container FROM DUAL;

PROMPT Done.
