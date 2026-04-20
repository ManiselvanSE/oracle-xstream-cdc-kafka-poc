-- Heavy MTX_TRANSACTION_ITEMS load test — redo volume and log switches (run as SYSDBA, correct PDB).
-- Log switches increase when online redo fills; sustained HammerDB load + smaller redo groups → more switches.
-- Tune redo with DBA (add groups, resize members) — not done from this repo.

SET LINESIZE 200 PAGESIZE 100

-- Online redo: size and group count (plan capacity during load tests)
COL GROUP# FORMAT 999
COL THREAD# FORMAT 999
COL MEMBER FORMAT A80
COL MB FORMAT 999999

PROMPT === Online redo groups (current) ===
SELECT group#, thread#, bytes/1024/1024 AS mb, status, archived
  FROM v$log
 ORDER BY thread#, group#;

PROMPT === Archived log — last 24h by hour (GB + switch count proxy) ===
SELECT TRUNC(completion_time, 'HH24') AS hr,
       thread#,
       ROUND(SUM(blocks * block_size) / 1024 / 1024 / 1024, 2) AS gb_redo,
       COUNT(*) AS archive_writes
  FROM v$archived_log
 WHERE completion_time >= SYSDATE - 1
 GROUP BY TRUNC(completion_time, 'HH24'), thread#
 ORDER BY 1, 2;

PROMPT === Last 2 hours — archived log detail (for HammerDB window) ===
SELECT TRUNC(completion_time, 'MI') AS minute_bucket,
       thread#,
       ROUND(SUM(blocks * block_size) / 1024 / 1024, 1) AS mb_redo,
       COUNT(*) AS archives_in_bucket
  FROM v$archived_log
 WHERE completion_time >= SYSDATE - (2/24)
 GROUP BY TRUNC(completion_time, 'MI'), thread#
 ORDER BY 1 DESC, 2;

PROMPT === Session redo from ORDERMGMT (optional — needs GV$ access) ===
-- SELECT s.username, SUM(s.value) / 1024 / 1024 AS mb_redo
--   FROM v$sesstat s JOIN v$statname n ON s.statistic# = n.statistic#
--  WHERE n.name = 'redo size' AND s.username = 'ORDERMGMT'
--  GROUP BY s.username;
