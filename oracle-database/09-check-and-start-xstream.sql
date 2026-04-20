-- =============================================================================
-- Check and Start XStream Capture & Outbound Server
-- Run as SYSDBA - connect to CDB (not PDB)
-- sqlplus sys/pwd@//racdb-scan...:1521/DB0312_r8n_phx... as sysdba
-- =============================================================================

SET SERVEROUTPUT ON
SET ECHO ON

PROMPT === 1. Current Status ===
SELECT SERVER_NAME, CONNECT_USER, CAPTURE_NAME, STATUS FROM DBA_XSTREAM_OUTBOUND WHERE SERVER_NAME = 'XOUT';
SELECT CAPTURE_NAME, STATUS FROM DBA_CAPTURE WHERE CAPTURE_NAME = 'CONFLUENT_XOUT1';
SELECT APPLY_NAME, STATUS FROM DBA_APPLY WHERE APPLY_NAME = 'XOUT';

PROMPT
PROMPT === 2. Start Capture if disabled ===
DECLARE
  v_found BOOLEAN := FALSE;
BEGIN
  FOR r IN (SELECT CAPTURE_NAME, STATUS FROM DBA_CAPTURE WHERE CAPTURE_NAME = 'CONFLUENT_XOUT1') LOOP
    v_found := TRUE;
    IF r.STATUS != 'ENABLED' THEN
      DBMS_CAPTURE_ADM.START_CAPTURE(capture_name => r.CAPTURE_NAME);
      DBMS_OUTPUT.PUT_LINE('Started capture: ' || r.CAPTURE_NAME);
    ELSE
      DBMS_OUTPUT.PUT_LINE('Capture already ENABLED: ' || r.CAPTURE_NAME);
    END IF;
  END LOOP;
  IF NOT v_found THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: Capture CONFLUENT_XOUT1 not found. Run 06-create-outbound-ordermgmt.sql as c##xstrmadmin first.');
  END IF;
END;
/

PROMPT
PROMPT === 3. Start Apply if disabled ===
DECLARE
  v_found BOOLEAN := FALSE;
BEGIN
  FOR r IN (SELECT APPLY_NAME, STATUS FROM DBA_APPLY WHERE APPLY_NAME = 'XOUT') LOOP
    v_found := TRUE;
    IF r.STATUS != 'ENABLED' THEN
      DBMS_APPLY_ADM.START_APPLY(apply_name => r.APPLY_NAME);
      DBMS_OUTPUT.PUT_LINE('Started apply: ' || r.APPLY_NAME);
    ELSE
      DBMS_OUTPUT.PUT_LINE('Apply already ENABLED: ' || r.APPLY_NAME);
    END IF;
  END LOOP;
  IF NOT v_found THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: Apply XOUT not found. Run 06-create-outbound-ordermgmt.sql as c##xstrmadmin first.');
  END IF;
END;
/

PROMPT
PROMPT === 4. Final Status ===
SELECT 'Outbound' comp, SERVER_NAME name, STATUS FROM DBA_XSTREAM_OUTBOUND WHERE SERVER_NAME = 'XOUT'
UNION ALL
SELECT 'Capture', CAPTURE_NAME, STATUS FROM DBA_CAPTURE WHERE CAPTURE_NAME = 'CONFLUENT_XOUT1'
UNION ALL
SELECT 'Apply', APPLY_NAME, STATUS FROM DBA_APPLY WHERE APPLY_NAME = 'XOUT';
