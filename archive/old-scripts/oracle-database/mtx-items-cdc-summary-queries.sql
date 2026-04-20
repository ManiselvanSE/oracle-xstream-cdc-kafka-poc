-- Queries aligned with client summary-style reporting (redo / archives).
-- Run as a user with access to v$archived_log (e.g. SYSDBA) during or after HammerDB load.
-- Pair with: HammerDB console output (tee mtx-run.log) and Kafka/Connect metrics (lag, EPS).

SET LINESIZE 200 PAGESIZE 500
COL Day FORMAT A12

-- Per-day, per-thread archived log volume (matches summary.docx style table)
SELECT TRUNC(completion_time, 'DD') AS day,
       thread#,
       ROUND(SUM(blocks * block_size) / 1024 / 1024 / 1024, 2) AS gb,
       COUNT(*) AS archives_generated
  FROM v$archived_log
 GROUP BY TRUNC(completion_time, 'DD'), thread#
 ORDER BY 1, 2;

-- Optional: rough MB/sec for a chosen hour window (adjust literals)
-- SELECT ROUND(SUM(blocks * block_size) / 1024 / 1024 / 3600, 2) AS mb_per_sec
--   FROM v$archived_log
--  WHERE completion_time >= TIMESTAMP '2026-04-15 10:00:00'
--    AND completion_time <  TIMESTAMP '2026-04-15 11:00:00';
