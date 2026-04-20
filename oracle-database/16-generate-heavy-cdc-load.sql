-- =============================================================================
-- Oracle XStream CDC - Heavy load generator for high connector throughput
-- Run as: sqlplus ordermgmt/<password>@XSTRPDB @16-generate-heavy-cdc-load.sql
-- Or: ./run-generate-heavy-cdc-load.sh
--
-- Inserts ~10,000 rows into ORDERS as fast as possible to produce sustained
-- high CDC throughput visible in Grafana (target: 100-500+ records/sec).
-- Duration: ~1-2 minutes depending on DB performance.
-- =============================================================================

SET SERVEROUTPUT ON
SET TIMING ON
PROMPT ================================================================================
PROMPT Heavy CDC Load - 10,000 inserts (no delay)
PROMPT Watch Grafana: Connector Throughput, CDC Throughput panels
PROMPT ================================================================================
PROMPT

-- Usage: @16-generate-heavy-cdc-load.sql [rows]  default 10000
DECLARE
  v_count    NUMBER := 0;
  v_batch    NUMBER := 100;   -- commit every N rows
  v_total    NUMBER := NVL(TO_NUMBER(TRIM('&1')), 10000);
  v_start    NUMBER;
  v_elapsed  NUMBER;
BEGIN
  v_start := DBMS_UTILITY.GET_TIME;
  FOR i IN 1..v_total LOOP
    INSERT INTO orders (customer_id, status, salesman_id, order_date)
    VALUES (
      MOD(i, 3) + 1,
      CASE MOD(i, 5) WHEN 0 THEN 'Shipped' WHEN 1 THEN 'Pending' WHEN 2 THEN 'Processing' WHEN 3 THEN 'Canceled' ELSE 'Completed' END,
      1,
      SYSDATE
    );
    v_count := v_count + 1;
    IF MOD(i, v_batch) = 0 THEN
      COMMIT;
    END IF;
  END LOOP;
  COMMIT;
  v_elapsed := (DBMS_UTILITY.GET_TIME - v_start) / 100;
  DBMS_OUTPUT.PUT_LINE('Inserted ' || v_count || ' rows in ' || ROUND(v_elapsed, 2) || ' seconds');
  DBMS_OUTPUT.PUT_LINE('Avg rate: ' || ROUND(v_count / NULLIF(v_elapsed, 0), 1) || ' rows/sec');
  DBMS_OUTPUT.PUT_LINE('CDC should appear in Grafana within 10-30 seconds.');
END;
/

PROMPT
PROMPT Done. Check Grafana for throughput spike.
