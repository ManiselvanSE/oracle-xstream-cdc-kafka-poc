-- =============================================================================
-- Teardown: Drop XStream Outbound Server (capture, apply, queue)
-- Run as: c##xstrmadmin or SYSDBA - connect to CDB
-- sqlplus c##xstrmadmin/<password>@//<host>:1521/<db-service> as sysdba
-- =============================================================================

SET SERVEROUTPUT ON
PROMPT === Dropping XStream Outbound (xout) ===

DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM DBA_XSTREAM_OUTBOUND WHERE SERVER_NAME = 'XOUT';
  IF v_exists = 0 THEN
    DBMS_OUTPUT.PUT_LINE('Outbound xout does not exist (already dropped).');
  ELSE
    DBMS_XSTREAM_ADM.DROP_OUTBOUND(server_name => 'xout');
    DBMS_OUTPUT.PUT_LINE('Dropped outbound server: xout');
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
    RAISE;
END;
/

PROMPT === Verify (should be empty) ===
SELECT SERVER_NAME FROM DBA_XSTREAM_OUTBOUND WHERE SERVER_NAME = 'XOUT';
-- Expected: no rows selected
