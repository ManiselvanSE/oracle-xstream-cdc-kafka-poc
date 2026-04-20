-- =============================================================================
-- Oracle XStream CDC - Step 2: Enable XStream and Verify Prerequisites
-- Run as SYSDBA on the RAC database
-- =============================================================================

-- 1. Enable XStream (GoldenGate replication)
-- All RAC instances must have the same setting
ALTER SYSTEM SET enable_goldengate_replication=TRUE SCOPE=BOTH;

-- 2. Verify XStream is enabled
SELECT INSTANCE_NAME, VALUE 
FROM GV$PARAMETER 
WHERE NAME = 'enable_goldengate_replication';

-- 3. Verify ARCHIVELOG mode (required for CDC)
SELECT LOG_MODE FROM V$DATABASE;
-- If not ARCHIVELOG, DBA must enable it:
-- srvctl stop database -d <db_name>
-- srvctl start database -d <db_name> -o mount
-- ALTER DATABASE ARCHIVELOG;
-- srvctl stop database -d <db_name>
-- srvctl start database -d <db_name>

-- 4. Check Streams pool (used by XStream)
-- Should be non-zero for XStream to work
SHOW PARAMETER streams_pool_size;
