-- =============================================================================
-- TPCC CDC smoke test: DML that touches all 9 TPCC tables (redo for XStream)
--
-- Use when Kafka topics stay at offset 0 after import/load — confirms CDC path
-- with fresh changes (see snapshot.mode=no_data in connector config).
--
-- Run as schema owner:
--   sqlplus TPCC/<password>@<PDB_TNS_ALIAS> @tpcc-cdc-smoke-test.sql
--
-- Or as SYS: connect to PDB first, then run this script:
--   ALTER SESSION SET CONTAINER = XSTRPDB;
--   @tpcc-cdc-smoke-test.sql
-- =============================================================================
SET ECHO ON FEEDBACK ON VERIFY OFF SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
  v_w   NUMBER;
  v_d   NUMBER;
  v_o   NUMBER;
  v_rid ROWID;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== TPCC CDC smoke test (expect 1+ row per table where data exists) ===');

  UPDATE TPCC.WAREHOUSE
     SET W_YTD = NVL(W_YTD, 0) + 0.0001
   WHERE W_ID = (SELECT MIN(W_ID) FROM TPCC.WAREHOUSE);
  DBMS_OUTPUT.PUT_LINE('WAREHOUSE  updated: ' || SQL%ROWCOUNT);

  UPDATE TPCC.DISTRICT
     SET D_YTD = NVL(D_YTD, 0) + 0.0001
   WHERE ROWID IN (
         SELECT rid
           FROM (SELECT ROWID rid FROM TPCC.DISTRICT ORDER BY D_W_ID, D_ID)
          WHERE ROWNUM = 1);
  DBMS_OUTPUT.PUT_LINE('DISTRICT  updated: ' || SQL%ROWCOUNT);

  UPDATE TPCC.CUSTOMER
     SET C_BALANCE = NVL(C_BALANCE, 0) + 0.0001
   WHERE ROWID IN (
         SELECT rid
           FROM (SELECT ROWID rid FROM TPCC.CUSTOMER ORDER BY C_W_ID, C_D_ID, C_ID)
          WHERE ROWNUM = 1);
  DBMS_OUTPUT.PUT_LINE('CUSTOMER  updated: ' || SQL%ROWCOUNT);

  UPDATE TPCC.ITEM
     SET I_PRICE = NVL(I_PRICE, 0) + 0.0001
   WHERE I_ID = (SELECT MIN(I_ID) FROM TPCC.ITEM);
  DBMS_OUTPUT.PUT_LINE('ITEM      updated: ' || SQL%ROWCOUNT);

  UPDATE TPCC.STOCK
     SET S_YTD = NVL(S_YTD, 0) + 0.0001
   WHERE ROWID IN (
         SELECT rid
           FROM (SELECT ROWID rid FROM TPCC.STOCK ORDER BY S_W_ID, S_I_ID)
          WHERE ROWNUM = 1);
  DBMS_OUTPUT.PUT_LINE('STOCK     updated: ' || SQL%ROWCOUNT);

  UPDATE TPCC.ORDERS
     SET O_OL_CNT = CASE WHEN NVL(O_OL_CNT, 0) >= 15 THEN 5 ELSE NVL(O_OL_CNT, 0) + 1 END
   WHERE ROWID IN (
         SELECT rid
           FROM (SELECT ROWID rid FROM TPCC.ORDERS ORDER BY O_W_ID, O_D_ID, O_ID)
          WHERE ROWNUM = 1);
  DBMS_OUTPUT.PUT_LINE('ORDERS    updated: ' || SQL%ROWCOUNT);

  -- NEW_ORDER is usually key-only; delete + re-insert same key to emit redo
  BEGIN
    SELECT NO_W_ID, NO_D_ID, NO_O_ID, ROWID
      INTO v_w, v_d, v_o, v_rid
      FROM TPCC.NEW_ORDER
     WHERE ROWNUM = 1;
    DELETE FROM TPCC.NEW_ORDER WHERE ROWID = v_rid;
    INSERT INTO TPCC.NEW_ORDER (NO_W_ID, NO_D_ID, NO_O_ID) VALUES (v_w, v_d, v_o);
    DBMS_OUTPUT.PUT_LINE('NEW_ORDER delete+insert: 1 row cycled');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('NEW_ORDER  skipped (no rows — run HammerDB Virtual User or benchmark)');
  END;

  UPDATE TPCC.ORDER_LINE
     SET OL_AMOUNT = NVL(OL_AMOUNT, 0) + 0.0001
   WHERE ROWID IN (
         SELECT rid
           FROM (SELECT ROWID rid FROM TPCC.ORDER_LINE ORDER BY OL_W_ID, OL_D_ID, OL_O_ID, OL_NUMBER)
          WHERE ROWNUM = 1);
  DBMS_OUTPUT.PUT_LINE('ORDER_LINE updated: ' || SQL%ROWCOUNT);

  UPDATE TPCC.HISTORY
     SET H_AMOUNT = NVL(H_AMOUNT, 0) + 0.0001
   WHERE ROWID IN (
         SELECT rid
           FROM (SELECT ROWID rid FROM TPCC.HISTORY ORDER BY H_C_W_ID, H_C_D_ID, H_C_ID, H_D_ID, H_W_ID, H_DATE)
          WHERE ROWNUM = 1);
  DBMS_OUTPUT.PUT_LINE('HISTORY   updated: ' || SQL%ROWCOUNT);

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('=== COMMIT done. Check Kafka offsets within ~1–2 min (connector + XStream lag). ===');
END;
/

EXIT;
