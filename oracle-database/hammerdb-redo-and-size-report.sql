-- Run as SYSDBA. Redo related to ORDERMGMT (HammerDB MTX) + MTX table / row sizing.
SET LINESIZE 200 PAGESIZE 100 FEEDBACK ON VERIFY OFF HEADING ON TIMING OFF
COLUMN redo_mb FORMAT 999,999,999.99
COLUMN mb FORMAT 999,999,999.99
COLUMN avg_row_len FORMAT 999,999,999
COLUMN num_rows FORMAT 999,999,999,999

PROMPT ========== 1) Instance redo (V$SYSSTAT — cumulative since startup) ==========
SELECT name, value AS bytes,
       ROUND(value/1024/1024, 2) AS redo_mb
FROM v$sysstat
WHERE name IN ('redo size', 'redo wastage', 'redo writes', 'redo write time')
ORDER BY name;

PROMPT ========== 2) Archived redo last 1 hour (generation volume) ==========
SELECT COUNT(*) AS arch_logs,
       ROUND(SUM(blocks * block_size) / 1024 / 1024, 2) AS total_mb,
       TO_CHAR(MIN(first_time), 'YYYY-MM-DD HH24:MI:SS') AS first_arch_time,
       TO_CHAR(MAX(first_time), 'YYYY-MM-DD HH24:MI:SS') AS last_arch_time
FROM v$archived_log
WHERE first_time > SYSDATE - (1/24)
  AND dest_id IN (SELECT dest_id FROM v$archive_dest WHERE status = 'VALID' AND target = 'PRIMARY');

PROMPT ========== 3) Sessions ORDERMGMT — redo attributed (V$SESSTAT redo size) ==========
SELECT s.sid, s.serial#, s.username, SUBSTR(s.program, 1, 60) AS program,
       ROUND(st.value / 1024 / 1024, 2) AS redo_mb
FROM v$session s
JOIN v$sesstat st ON s.sid = st.sid
JOIN v$statname sn ON st.statistic# = sn.statistic#
WHERE sn.name = 'redo size'
  AND s.username = 'ORDERMGMT'
ORDER BY st.value DESC;

PROMPT ========== 4) Any active HammerDB / sqlplus style programs (same redo stat) ==========
SELECT s.sid, s.username, SUBSTR(s.program, 1, 80) AS program,
       ROUND(st.value / 1024 / 1024, 2) AS redo_mb
FROM v$session s
JOIN v$sesstat st ON s.sid = st.sid
JOIN v$statname sn ON st.statistic# = sn.statistic#
WHERE sn.name = 'redo size'
  AND (UPPER(s.program) LIKE '%SQLPLUS%' OR UPPER(s.program) LIKE '%HAMMER%' OR UPPER(s.program) LIKE '%ORATCL%')
ORDER BY st.value DESC;

PROMPT ========== 5) ORDERMGMT.MTX* tables — row counts, avg row len (proxy for event payload size) ==========
SELECT table_name,
       num_rows,
       avg_row_len,
       ROUND(num_rows * NVL(avg_row_len, 0) / 1024 / 1024, 2) AS approx_data_mb
FROM dba_tables
WHERE owner = 'ORDERMGMT'
  AND table_name LIKE 'MTX%'
ORDER BY num_rows DESC NULLS LAST
FETCH FIRST 25 ROWS ONLY;

PROMPT ========== 6) Sample: widest MTX table (max estimated row bytes from statistics) ==========
SELECT MAX(avg_row_len) AS max_avg_row_bytes_among_mtx
FROM dba_tables
WHERE owner = 'ORDERMGMT' AND table_name LIKE 'MTX%' AND avg_row_len IS NOT NULL;

EXIT;
