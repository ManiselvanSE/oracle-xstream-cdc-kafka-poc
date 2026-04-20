-- =============================================================================
-- GRANT SELECT on ALL ORDERMGMT.MTX* tables to C##CFLTUSER (Kafka Connect / XStream reader)
-- Run as SYS AS SYSDBA (or user with GRANT ANY OBJECT PRIVILEGE on ORDERMGMT)
--
--   sqlplus sys/<pwd>@//host:1521/<service> AS SYSDBA @ordermgmt-mtx-grant-cfltuser.sql
--
-- Dynamic list from DBA_TABLES — stays in sync when new MTX tables are added.
-- Re-run is safe: duplicate GRANT is a no-op.
-- PDB: edit XSTRPDB if needed.
-- =============================================================================

ALTER SESSION SET CONTAINER = XSTRPDB;

SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
  n PLS_INTEGER := 0;
BEGIN
  FOR r IN (
    SELECT table_name
    FROM   dba_tables
    WHERE  owner = 'ORDERMGMT'
    AND    table_name LIKE 'MTX%'
    ORDER BY table_name
  ) LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT ON ORDERMGMT.' || r.table_name || ' TO c##cfltuser';
    DBMS_OUTPUT.PUT_LINE('GRANT SELECT ON ORDERMGMT.' || r.table_name);
    n := n + 1;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('--- Total tables granted: ' || n);
END;
/

PROMPT === Verify: SELECT privileges for C##CFLTUSER on ORDERMGMT.MTX* ===
SELECT COUNT(*) AS grant_count
FROM   dba_tab_privs
WHERE  grantee = 'C##CFLTUSER'
AND    owner = 'ORDERMGMT'
AND    table_name LIKE 'MTX%'
AND    privilege = 'SELECT';

PROMPT === Detail (optional) ===
SELECT owner, table_name, privilege
FROM   dba_tab_privs
WHERE  grantee = 'C##CFLTUSER'
AND    owner = 'ORDERMGMT'
AND    table_name LIKE 'MTX%'
ORDER BY table_name;

PROMPT Done: ordermgmt-mtx-grant-cfltuser.sql
