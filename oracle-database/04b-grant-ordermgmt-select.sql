-- =============================================================================
-- Grant SELECT on ORDERMGMT tables to connector user (c##cfltuser)
-- Run as SYSDBA - REQUIRED for connector to process all tables
-- Without this, connector skips tables with "database user does not have access"
-- =============================================================================

ALTER SESSION SET CONTAINER = XSTRPDB;

BEGIN
  FOR r IN (SELECT table_name FROM all_tables WHERE owner = 'ORDERMGMT') LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT ON ordermgmt.' || r.table_name || ' TO c##cfltuser';
  END LOOP;
END;
/
