-- =============================================================================
-- ORA-00257 / full FRA — what you can do with SQL*Plus only (as SYSDBA)
--
-- You CANNOT safely remove archived log files from +RECO with SQL alone.
-- Supported cleanup: RMAN (DELETE ARCHIVELOG / DELETE OBSOLETE) or OCI backup policy.
--
-- You CAN:
--   1) See FRA usage (below)
--   2) Raise the logical FRA cap IF the underlying ASM/disk has space (often after
--      OCI "Scale storage up" on the DB system recovery area)
-- =============================================================================
SET PAGESIZE 100 LINESIZE 200 FEEDBACK OFF VERIFY OFF

PROMPT === Current FRA (before) ===
SELECT ROUND(space_limit/1024/1024/1024,2) AS gb_limit,
       ROUND(space_used/1024/1024/1024,2) AS gb_used,
       ROUND(100*space_used/NULLIF(space_limit,0),1) AS pct_used
FROM   v$recovery_file_dest;

PROMPT === Optional: increase logical FRA size (uncomment ONE line after scaling disk in OCI) ===
PROMPT === Example: after OCI adds recovery GB, set below to slightly below new quota ===
-- ALTER SYSTEM SET db_recovery_file_dest_size = 400G SCOPE=BOTH;

PROMPT === Re-check after ALTER (if you ran it) ===
-- SELECT ROUND(space_used/1024/1024/1024,2) gb_used,
--        ROUND(100*space_used/NULLIF(space_limit,0),1) pct
-- FROM   v$recovery_file_dest;

PROMPT Done. Without RMAN: free space via OCI scale-up, then optional ALTER above.
