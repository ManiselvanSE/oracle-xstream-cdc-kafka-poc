-- ORA-00257: archiver error — run as SYSDBA (CDB). Review output then free FRA / archives per policy.
SET PAGESIZE 200 LINESIZE 200 FEEDBACK OFF VERIFY OFF
PROMPT === Archive mode ===
ARCHIVE LOG LIST;

PROMPT === FRA parameters ===
SHOW PARAMETER db_recovery_file_dest

PROMPT === v$recovery_file_dest ===
SELECT ROUND(space_limit/1024/1024/1024,2) AS gb_limit,
       ROUND(space_used/1024/1024/1024,2) AS gb_used,
       ROUND(100*space_used/NULLIF(space_limit,0),1) AS pct_used
FROM   v$recovery_file_dest;

PROMPT === v$recovery_area_usage (top consumers) ===
SELECT * FROM v$recovery_area_usage ORDER BY percent_space_used DESC;

PROMPT Done. If pct_used is high and ARCHIVED LOG dominates, free FRA (RMAN delete archivelogs per backup policy) or raise db_recovery_file_dest_size.
