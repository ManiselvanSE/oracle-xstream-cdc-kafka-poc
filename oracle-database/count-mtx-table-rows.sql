-- Row counts for all ORDERMGMT tables whose name starts with MTX (HammerDB / CDC sanity).
-- Run as user with SELECT on ORDERMGMT (e.g. ORDERMGMT, SYS, or DBA).
--   sqlplus ordermgmt/...@service @count-mtx-table-rows.sql
--
SET SERVEROUTPUT ON SIZE UNLIMITED FORMAT WRAPPED
SET LINESIZE 200

PROMPT === COUNT(*) per ORDERMGMT.MTX* table ===
DECLARE
  cnt NUMBER;
BEGIN
  FOR r IN (
    SELECT table_name
    FROM   dba_tables
    WHERE  owner = 'ORDERMGMT'
    AND    table_name LIKE 'MTX%'
    ORDER BY table_name
  ) LOOP
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ORDERMGMT.' || r.table_name INTO cnt;
    DBMS_OUTPUT.PUT_LINE(RPAD(r.table_name, 40, ' ') || cnt);
  END LOOP;
END;
/

PROMPT === Done ===
