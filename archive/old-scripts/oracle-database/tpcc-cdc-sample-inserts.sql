-- =============================================================================
-- TPCC sample INSERTs for CDC streaming (snapshot.mode=no_data)
-- Inserts one new warehouse chain (W → D → C → I → S → O → NO → OL → H) with
-- fresh primary keys so redo/XStream emits events to Kafka.
--
-- Prereqs: HammerDB TPCC schema populated (at least one warehouse); XStream rules
-- for TPCC tables; connector RUNNING with TPCC in table.include.list.
--
-- Run as TPCC:
--   sqlplus TPCC/<password>@<PDB_TNS> @tpcc-cdc-sample-inserts.sql
--
-- Column layout matches HammerDB Oracle TPROC-C (oraoltp.tcl).
-- =============================================================================
SET ECHO ON FEEDBACK ON VERIFY OFF SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
  src_w NUMBER;
  src_i NUMBER;
  v_w   NUMBER;
  v_i   NUMBER;
  v_o   NUMBER;
  nstk  NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== TPCC sample INSERTs (streaming CDC) ===');

  SELECT MIN(W_ID) INTO src_w FROM TPCC.WAREHOUSE;
  IF src_w IS NULL THEN
    RAISE_APPLICATION_ERROR(-20001, 'TPCC.WAREHOUSE is empty — build HammerDB schema first.');
  END IF;

  SELECT NVL(MAX(W_ID), 0) + 1 INTO v_w FROM TPCC.WAREHOUSE;
  SELECT MIN(I_ID) INTO src_i FROM TPCC.ITEM;
  IF src_i IS NULL THEN
    RAISE_APPLICATION_ERROR(-20002, 'TPCC.ITEM is empty.');
  END IF;

  -- 1) WAREHOUSE (new id)
  INSERT INTO TPCC.WAREHOUSE (W_ID, W_YTD, W_TAX, W_NAME, W_STREET_1, W_STREET_2, W_CITY, W_STATE, W_ZIP)
  SELECT v_w, W_YTD, W_TAX, W_NAME, W_STREET_1, W_STREET_2, W_CITY, W_STATE, W_ZIP
    FROM TPCC.WAREHOUSE WHERE W_ID = src_w;
  DBMS_OUTPUT.PUT_LINE('WAREHOUSE inserted W_ID=' || v_w);

  -- 2) DISTRICT (D_ID=1 for new warehouse; clone from template wh / dist 1)
  INSERT INTO TPCC.DISTRICT (D_ID, D_W_ID, D_YTD, D_TAX, D_NEXT_O_ID, D_NAME, D_STREET_1, D_STREET_2, D_CITY, D_STATE, D_ZIP)
  SELECT 1, v_w, D_YTD, D_TAX, D_NEXT_O_ID, D_NAME, D_STREET_1, D_STREET_2, D_CITY, D_STATE, D_ZIP
    FROM TPCC.DISTRICT WHERE D_W_ID = src_w AND D_ID = 1;
  DBMS_OUTPUT.PUT_LINE('DISTRICT inserted D_W_ID=' || v_w || ' D_ID=1');

  -- 3) CUSTOMER (first customer in new district)
  INSERT INTO TPCC.CUSTOMER (C_ID, C_D_ID, C_W_ID, C_FIRST, C_MIDDLE, C_LAST, C_STREET_1, C_STREET_2, C_CITY, C_STATE, C_ZIP, C_PHONE, C_SINCE, C_CREDIT, C_CREDIT_LIM, C_DISCOUNT, C_BALANCE, C_YTD_PAYMENT, C_PAYMENT_CNT, C_DELIVERY_CNT, C_DATA)
  SELECT 1, 1, v_w, C_FIRST, C_MIDDLE, C_LAST, C_STREET_1, C_STREET_2, C_CITY, C_STATE, C_ZIP, C_PHONE, C_SINCE, C_CREDIT, C_CREDIT_LIM, C_DISCOUNT, C_BALANCE, C_YTD_PAYMENT, C_PAYMENT_CNT, C_DELIVERY_CNT, C_DATA
    FROM TPCC.CUSTOMER WHERE C_W_ID = src_w AND C_D_ID = 1 AND C_ID = 1;
  DBMS_OUTPUT.PUT_LINE('CUSTOMER inserted C_W_ID=' || v_w || ' C_D_ID=1 C_ID=1');

  -- 4) ITEM (new global item id)
  SELECT NVL(MAX(I_ID), 0) + 1 INTO v_i FROM TPCC.ITEM;
  INSERT INTO TPCC.ITEM (I_ID, I_IM_ID, I_NAME, I_PRICE, I_DATA)
  SELECT v_i, I_IM_ID, I_NAME, I_PRICE, I_DATA
    FROM TPCC.ITEM WHERE I_ID = src_i;
  DBMS_OUTPUT.PUT_LINE('ITEM inserted I_ID=' || v_i);

  -- 5) STOCK (new warehouse × new item)
  INSERT INTO TPCC.STOCK (S_I_ID, S_W_ID, S_QUANTITY, S_DIST_01, S_DIST_02, S_DIST_03, S_DIST_04, S_DIST_05, S_DIST_06, S_DIST_07, S_DIST_08, S_DIST_09, S_DIST_10, S_YTD, S_ORDER_CNT, S_REMOTE_CNT, S_DATA)
  SELECT v_i, v_w, S_QUANTITY, S_DIST_01, S_DIST_02, S_DIST_03, S_DIST_04, S_DIST_05, S_DIST_06, S_DIST_07, S_DIST_08, S_DIST_09, S_DIST_10, S_YTD, S_ORDER_CNT, S_REMOTE_CNT, S_DATA
    FROM TPCC.STOCK WHERE S_W_ID = src_w AND S_I_ID = src_i;
  nstk := SQL%ROWCOUNT;
  IF nstk = 0 THEN
    RAISE_APPLICATION_ERROR(-20003, 'No STOCK row for template (S_W_ID=' || src_w || ', S_I_ID=' || src_i || ').');
  END IF;
  DBMS_OUTPUT.PUT_LINE('STOCK inserted S_W_ID=' || v_w || ' S_I_ID=' || v_i);

  -- 6) ORDERS
  SELECT NVL(MAX(O_ID), 0) + 1 INTO v_o FROM TPCC.ORDERS WHERE O_W_ID = v_w AND O_D_ID = 1;
  INSERT INTO TPCC.ORDERS (O_ID, O_W_ID, O_D_ID, O_C_ID, O_CARRIER_ID, O_OL_CNT, O_ALL_LOCAL, O_ENTRY_D)
  VALUES (v_o, v_w, 1, 1, NULL, 5, 1, SYSDATE);
  DBMS_OUTPUT.PUT_LINE('ORDERS inserted O_ID=' || v_o);

  -- 7) NEW_ORDER
  INSERT INTO TPCC.NEW_ORDER (NO_W_ID, NO_D_ID, NO_O_ID) VALUES (v_w, 1, v_o);
  DBMS_OUTPUT.PUT_LINE('NEW_ORDER inserted');

  -- 8) ORDER_LINE
  INSERT INTO TPCC.ORDER_LINE (OL_W_ID, OL_D_ID, OL_O_ID, OL_NUMBER, OL_I_ID, OL_DELIVERY_D, OL_AMOUNT, OL_SUPPLY_W_ID, OL_QUANTITY, OL_DIST_INFO)
  VALUES (v_w, 1, v_o, 1, v_i, NULL, 10.5, v_w, 5, RPAD('cdc', 24));
  DBMS_OUTPUT.PUT_LINE('ORDER_LINE inserted');

  -- 9) HISTORY (unique H_DATE vs repeated runs)
  INSERT INTO TPCC.HISTORY (H_C_ID, H_C_D_ID, H_C_W_ID, H_D_ID, H_W_ID, H_DATE, H_AMOUNT, H_DATA)
  VALUES (1, 1, v_w, 1, v_w, CAST(SYSTIMESTAMP AS DATE), 10.00, RPAD('cdc-ins', 24));
  DBMS_OUTPUT.PUT_LINE('HISTORY inserted');

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('=== COMMIT ok. New W_ID=' || v_w || ' I_ID=' || v_i || ' O_ID=' || v_o || ' ===');
  DBMS_OUTPUT.PUT_LINE('Wait ~1–2 min, then on Connect VM: ./docker/scripts/check-tpcc-kafka-offsets.sh');
END;
/

EXIT;
