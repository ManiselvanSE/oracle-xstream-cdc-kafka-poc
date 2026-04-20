-- Oracle Database Monitoring User Setup for XStream CDC
-- Create a dedicated monitoring user with read-only access to required views

-- Create monitoring user
CREATE USER oracledb_exporter IDENTIFIED BY "your_secure_password_here";

-- Grant basic connect and session privileges
GRANT CONNECT TO oracledb_exporter;
GRANT CREATE SESSION TO oracledb_exporter;

-- Grant SELECT on required system views for XStream monitoring
GRANT SELECT ON v$database TO oracledb_exporter;
GRANT SELECT ON v$streams_capture TO oracledb_exporter;
GRANT SELECT ON v$xstream_outbound_server TO oracledb_exporter;
GRANT SELECT ON v$archived_log TO oracledb_exporter;
GRANT SELECT ON v$logmnr_session TO oracledb_exporter;
GRANT SELECT ON v$sgastat TO oracledb_exporter;
GRANT SELECT ON v$streams_transaction TO oracledb_exporter;

-- Grant SELECT on DBA views (alternative: create views in monitoring schema)
GRANT SELECT ON dba_capture TO oracledb_exporter;
GRANT SELECT ON dba_data_files TO oracledb_exporter;
GRANT SELECT ON dba_segments TO oracledb_exporter;

-- Grant SELECT_CATALOG_ROLE for broader access (optional, more permissive)
-- GRANT SELECT_CATALOG_ROLE TO oracledb_exporter;

-- If using RAC, grant additional privileges
GRANT SELECT ON gv$instance TO oracledb_exporter;
GRANT SELECT ON gv$streams_capture TO oracledb_exporter;

-- Verify grants
SELECT grantee, privilege
FROM dba_sys_privs
WHERE grantee = 'ORACLEDB_EXPORTER';

SELECT grantee, owner, table_name, privilege
FROM dba_tab_privs
WHERE grantee = 'ORACLEDB_EXPORTER'
ORDER BY owner, table_name;

-- Test connection as monitoring user
-- CONNECT oracledb_exporter/your_secure_password_here@your_database
-- SELECT * FROM v$streams_capture;
