-- =============================================================================
-- Enable supplemental logging on ALL ORDERMGMT tables named MTX% (LogMiner / XStream CDC)
-- Run as SYS AS SYSDBA (same privilege model as hammerdb-tpcc-onboard-xstream.sql)
--
--   sqlplus sys/<pwd>@//host:1521/<service> AS SYSDBA @ordermgmt-mtx-supplemental-logging.sql
--
-- Idempotent: ORA-32588 (already enabled) is ignored per table.
-- ORA-00054: pause HammerDB/other sessions locking ORDERMGMT tables, or re-run.
-- PDB: edit XSTRPDB below if your connector uses a different PDB.
-- =============================================================================

ALTER SESSION SET CONTAINER = XSTRPDB;
ALTER SESSION SET DDL_LOCK_TIMEOUT = 600;

SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
  PROCEDURE add_supp(p_owner VARCHAR2, p_tab VARCHAR2) IS
    v_full VARCHAR2(261);
  BEGIN
    v_full := p_owner || '.' || p_tab;
    -- table_name from dba_tables only (no user input)
    EXECUTE IMMEDIATE 'ALTER TABLE ' || v_full || ' ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS';
    DBMS_OUTPUT.PUT_LINE('OK: ' || v_full);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -32588 THEN
        DBMS_OUTPUT.PUT_LINE('Skip (already): ' || v_full);
      ELSE
        DBMS_OUTPUT.PUT_LINE('ERR ' || SQLERRM || ' — ' || v_full);
        RAISE;
      END IF;
  END;
BEGIN
  FOR r IN (
    SELECT table_name
    FROM   dba_tables
    WHERE  owner = 'ORDERMGMT'
    AND    table_name LIKE 'MTX%'
    ORDER BY table_name
  ) LOOP
    add_supp('ORDERMGMT', r.table_name);
  END LOOP;
END;
/

PROMPT === Verify: dba_log_groups for ORDERMGMT.MTX* (sample) ===
SELECT owner, table_name, log_group_name, log_group_type
FROM   dba_log_groups
WHERE  owner = 'ORDERMGMT'
AND    table_name LIKE 'MTX%'
ORDER BY table_name
FETCH FIRST 50 ROWS ONLY;

PROMPT Done. Next: GRANT SELECT (if needed), ug-prod-onboard-xstream.sh for XStream rules, connector table.include.list.
