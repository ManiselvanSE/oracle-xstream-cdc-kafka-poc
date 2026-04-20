-- =============================================================================
-- Oracle XStream CDC - Step 7: Data generator procedure (from ora0600/confluent-new-cdc-connector)
-- Run as: sqlplus ordermgmt/<password>@//<host>:1521/XSTRPDB...
-- =============================================================================

-- Generate orders every 5 seconds (for testing CDC)
CREATE OR REPLACE PROCEDURE produce_orders
AUTHID CURRENT_USER
AS
BEGIN
  FOR x IN 1..3600 LOOP
    INSERT INTO orders (customer_id, status, salesman_id, order_date)
    VALUES (DBMS_RANDOM.VALUE(1,10), 'Pending', 1, SYSDATE);
    COMMIT;
    DBMS_LOCK.SLEEP(seconds => 5);
  END LOOP;
END;
/

-- Quick test: insert 10 orders
CREATE OR REPLACE PROCEDURE produce_orders_quick
AUTHID CURRENT_USER
AS
BEGIN
  FOR x IN 1..10 LOOP
    INSERT INTO orders (customer_id, status, salesman_id, order_date)
    VALUES (DBMS_RANDOM.VALUE(1,3), 'Pending', 1, SYSDATE);
    COMMIT;
    DBMS_LOCK.SLEEP(seconds => 1);
  END LOOP;
END;
/

-- Usage:
-- EXEC produce_orders_quick;   -- 10 orders, 1 sec apart
-- EXEC produce_orders;        -- 3600 orders over ~5 hours
