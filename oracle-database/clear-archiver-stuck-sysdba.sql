-- Run as SYSDBA after FRA space is fixed — helps clear ORA-00257 for non-SYSDBA users.
SET FEEDBACK ON
PROMPT === Archive destinations (errors) ===
SELECT dest_id, dest_name, status, target, error FROM v$archive_dest WHERE dest_id <= 10 ORDER BY dest_id;

PROMPT === Force archive current log ===
ALTER SYSTEM ARCHIVE LOG CURRENT;

PROMPT === Done. Retry app/connector user. ===
