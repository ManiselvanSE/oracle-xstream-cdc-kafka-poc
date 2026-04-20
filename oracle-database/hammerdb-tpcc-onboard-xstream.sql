-- =============================================================================
-- HammerDB TPC-C schema: supplemental logging + connector read access (PDB)
-- Run as SYS AS SYSDBA (ALTER TABLE TPCC.* + GRANT need owner/DBA — c##xstrmadmin gets ORA-01031).
--   sqlplus sys/<pwd>@//host:1521/<CDB_or_PDB_service> AS SYSDBA @hammerdb-tpcc-onboard-xstream.sql
-- fix-tpcc-xstream-oracle.sh runs this as SYS (ORACLE_SYS_PWD), then c##xstrmadmin for ADD_TABLE_RULES.
-- After this: ./hammerdb-tpcc-onboard-xstream.sh (adds XStream capture/apply rules)
-- Then on Connect VM: ./docker/scripts/onboard-tables-deploy-on-vm.sh
-- ORA-00054 on ALTER TABLE: another session holds TPCC (HammerDB load, etc.). Pause load
-- or rely on DDL_LOCK_TIMEOUT below; if it still fails, stop competing sessions and re-run.
-- ORA-32588: supplemental logging already enabled — ignored (idempotent re-run).
-- =============================================================================

ALTER SESSION SET CONTAINER = XSTRPDB;
ALTER SESSION SET DDL_LOCK_TIMEOUT = 600;

SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
  PROCEDURE add_supp(p_tab VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE 'ALTER TABLE ' || p_tab || ' ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS';
    DBMS_OUTPUT.PUT_LINE('Supplemental log: ' || p_tab);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -32588 THEN
        DBMS_OUTPUT.PUT_LINE('Supplemental log already on ' || p_tab || ' (ORA-32588); skip.');
      ELSE
        RAISE;
      END IF;
  END;
BEGIN
  add_supp('TPCC.DISTRICT');
  add_supp('TPCC.CUSTOMER');
  add_supp('TPCC.HISTORY');
  add_supp('TPCC.ITEM');
  add_supp('TPCC.WAREHOUSE');
  add_supp('TPCC.STOCK');
  add_supp('TPCC.ORDERS');
  add_supp('TPCC.NEW_ORDER');
  add_supp('TPCC.ORDER_LINE');
END;
/

GRANT SELECT ON TPCC.DISTRICT   TO c##cfltuser;
GRANT SELECT ON TPCC.CUSTOMER   TO c##cfltuser;
GRANT SELECT ON TPCC.HISTORY    TO c##cfltuser;
GRANT SELECT ON TPCC.ITEM       TO c##cfltuser;
GRANT SELECT ON TPCC.WAREHOUSE  TO c##cfltuser;
GRANT SELECT ON TPCC.STOCK      TO c##cfltuser;
GRANT SELECT ON TPCC.ORDERS     TO c##cfltuser;
GRANT SELECT ON TPCC.NEW_ORDER  TO c##cfltuser;
GRANT SELECT ON TPCC.ORDER_LINE TO c##cfltuser;

PROMPT Done: supplemental logging + grants. Run hammerdb-tpcc-onboard-xstream.sh next.
