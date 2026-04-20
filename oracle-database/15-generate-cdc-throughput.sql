-- =============================================================================
-- Oracle XStream CDC - Generate CDC throughput for Grafana visibility
-- Run as: sqlplus ordermgmt/<password>@//<host>:1521/<service> @15-generate-cdc-throughput.sql
-- Example: sqlplus ordermgmt/YourP@ssw0rd123@//racdb-scan.example.com:1521/XSTRPDB.example.oraclevcn.com @15-generate-cdc-throughput.sql
--
-- Inserts ~200 rows into ORDERS over ~30 seconds to produce visible CDC throughput
-- in Grafana "Oracle XStream Connector Throughput" and "CDC Throughput" panels.
-- =============================================================================

SET SERVEROUTPUT ON
PROMPT Generating CDC throughput - 200 inserts over ~30 seconds...
PROMPT Watch Grafana: Oracle XStream Connector Throughput, CDC Throughput
PROMPT

DECLARE
  v_count NUMBER := 0;
BEGIN
  FOR i IN 1..200 LOOP
    INSERT INTO orders (customer_id, status, salesman_id, order_date)
    VALUES (
      MOD(i, 3) + 1,           -- customer_id 1, 2, or 3
      CASE MOD(i, 3) WHEN 0 THEN 'Shipped' WHEN 1 THEN 'Pending' ELSE 'Processing' END,
      1,
      SYSDATE
    );
    v_count := v_count + 1;
    IF MOD(i, 20) = 0 THEN
      COMMIT;
      DBMS_LOCK.SLEEP(3);      -- pause every 20 rows to spread over ~30 sec
    END IF;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Inserted ' || v_count || ' rows. CDC should appear in Grafana within 10-30 seconds.');
END;
/

PROMPT
PROMPT Done. Check Grafana dashboard for throughput spike.
