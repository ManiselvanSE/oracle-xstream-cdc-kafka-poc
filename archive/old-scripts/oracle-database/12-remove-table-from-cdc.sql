-- =============================================================================
-- Oracle XStream CDC - Remove table from existing capture + outbound apply
-- Run as SYS AS SYSDBA (same as 11-add-table-to-cdc.sql):
--   sqlplus sys/<pwd>@//host:1521/<CDB_svc> AS SYSDBA @12-remove-table-from-cdc.sql "TPCC.CUSTOMER"
-- Use when Confluent reports: LCR schema differs from table's current schema
-- (e.g. after HammerDB rebuild/DDL). After removal, re-run 11-add-table-to-cdc.sql
-- for each table, then connector: delete + recreate with snapshot.mode=initial
-- (and optionally delete __orcl-schema-changes.racdb on Connect VM).
-- =============================================================================

SET SERVEROUTPUT ON
SET DEFINE ON

DECLARE
  v_table VARCHAR2(128) := '&1';
  v_qo VARCHAR2(128);
  v_qn VARCHAR2(128);
BEGIN
  IF v_table IS NULL OR LENGTH(TRIM(v_table)) = 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'Usage: @12-remove-table-from-cdc.sql "SCHEMA.TABLE"');
  END IF;

  EXECUTE IMMEDIATE 'ALTER SESSION SET CONTAINER = CDB$ROOT';
  SELECT queue_owner, queue_name INTO v_qo, v_qn
  FROM dba_capture WHERE capture_name = 'CONFLUENT_XOUT1';

  DBMS_OUTPUT.PUT_LINE('Removing table: ' || v_table);
  DBMS_OUTPUT.PUT_LINE('Queue: ' || v_qo || '.' || v_qn);

  BEGIN
    DBMS_XSTREAM_ADM.REMOVE_TABLE_RULES(
      table_name             => v_table,
      streams_type           => 'capture',
      streams_name           => 'confluent_xout1',
      queue_name             => v_qo || '.' || v_qn,
      source_container_name  => 'XSTRPDB');
    DBMS_OUTPUT.PUT_LINE('Removed from capture.');
  EXCEPTION
    WHEN OTHERS THEN
      IF INSTR(LOWER(SQLERRM), 'does not exist') > 0
         OR INSTR(LOWER(SQLERRM), 'not found') > 0
         OR INSTR(LOWER(SQLERRM), 'no rule') > 0 THEN
        DBMS_OUTPUT.PUT_LINE('No capture rule for ' || v_table || '; skipping.');
      ELSE
        RAISE;
      END IF;
  END;

  BEGIN
    DBMS_XSTREAM_ADM.REMOVE_TABLE_RULES(
      table_name             => v_table,
      streams_type           => 'apply',
      streams_name           => 'xout',
      queue_name             => v_qo || '.' || v_qn,
      source_container_name  => 'XSTRPDB');
    DBMS_OUTPUT.PUT_LINE('Removed from outbound.');
  EXCEPTION
    WHEN OTHERS THEN
      IF INSTR(LOWER(SQLERRM), 'does not exist') > 0
         OR INSTR(LOWER(SQLERRM), 'not found') > 0
         OR INSTR(LOWER(SQLERRM), 'no rule') > 0 THEN
        DBMS_OUTPUT.PUT_LINE('No apply rule for ' || v_table || '; skipping.');
      ELSE
        RAISE;
      END IF;
  END;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Done. Re-add with @11-add-table-to-cdc.sql "' || v_table || '" then fix connector.');
END;
/
