-- =============================================================================
-- Oracle XStream CDC - Add New Table to Existing Outbound
-- Run as SYS AS SYSDBA (queries DBA_CAPTURE in CDB$ROOT; c##xstrmadmin often ORA-01031):
--   sqlplus sys/<pwd>@//host:1521/<svc> AS SYSDBA @11-add-table-to-cdc.sql "ORDERMGMT.NEW_ORDERS"
-- Legacy: XStream admin with full catalog grants may work as c##xstrmadmin.
-- =============================================================================
-- Prerequisites (run as SYSDBA in PDB first):
--   1. ALTER SESSION SET CONTAINER = XSTRPDB;
--   2. ALTER TABLE schema.table ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
--   3. GRANT SELECT ON schema.table TO c##cfltuser;
-- After this script: Update connector table.include.list and restart connector
-- =============================================================================

SET SERVEROUTPUT ON
-- Required for &1 script argument (parent SET DEFINE OFF would leave v_table as literal &1 → ORA-44004).
SET DEFINE ON

DECLARE
  v_table VARCHAR2(128) := '&1';
  v_qo VARCHAR2(128);
  v_qn VARCHAR2(128);
BEGIN
  IF v_table IS NULL OR LENGTH(TRIM(v_table)) = 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'Usage: @11-add-table-to-cdc.sql "SCHEMA.TABLE"');
  END IF;

  -- Capture metadata lives in CDB$ROOT; querying DBA_CAPTURE from a PDB often returns no rows (ORA-01403).
  EXECUTE IMMEDIATE 'ALTER SESSION SET CONTAINER = CDB$ROOT';
  SELECT queue_owner, queue_name INTO v_qo, v_qn
  FROM dba_capture WHERE capture_name = 'CONFLUENT_XOUT1';

  DBMS_OUTPUT.PUT_LINE('Adding table: ' || v_table);
  DBMS_OUTPUT.PUT_LINE('Queue: ' || v_qo || '.' || v_qn);

  -- Add to capture (idempotent: ORA-26654 if rule already exists)
  BEGIN
    DBMS_XSTREAM_ADM.ADD_TABLE_RULES(
      table_name             => v_table,
      streams_type           => 'capture',
      streams_name           => 'confluent_xout1',
      queue_name             => v_qo || '.' || v_qn,
      include_dml            => TRUE,
      include_ddl            => FALSE,
      source_container_name  => 'XSTRPDB');
    DBMS_OUTPUT.PUT_LINE('Added to capture.');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -26654 OR INSTR(LOWER(SQLERRM), 'already exists') > 0 THEN
        DBMS_OUTPUT.PUT_LINE('Capture rule already present for ' || v_table || '; skipping.');
      ELSE
        RAISE;
      END IF;
  END;

  -- Add to apply (outbound)
  BEGIN
    DBMS_XSTREAM_ADM.ADD_TABLE_RULES(
      table_name             => v_table,
      streams_type           => 'apply',
      streams_name           => 'xout',
      queue_name             => v_qo || '.' || v_qn,
      include_dml            => TRUE,
      include_ddl            => FALSE,
      source_container_name  => 'XSTRPDB');
    DBMS_OUTPUT.PUT_LINE('Added to outbound.');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -26654 OR INSTR(LOWER(SQLERRM), 'already exists') > 0 THEN
        DBMS_OUTPUT.PUT_LINE('Apply rule already present for ' || v_table || '; skipping.');
      ELSE
        RAISE;
      END IF;
  END;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Done. Update connector table.include.list and restart connector.');
END;
/
