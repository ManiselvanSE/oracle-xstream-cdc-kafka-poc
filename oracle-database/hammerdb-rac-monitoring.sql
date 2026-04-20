-- =============================================================================
-- RAC monitoring snippets for HammerDB TPC-C validation (Oracle 19c+)
-- Run as user with gv$ access (e.g. SELECT on gv$ views or DBA role).
-- Adjust 'TPCC' / service name / sql_id filters for your environment.
-- Diagnostic Pack: gv$active_session_history requires license on production.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Session counts by instance (is load spread across RAC nodes?)
-- -----------------------------------------------------------------------------
SELECT inst_id,
       username,
       status,
       COUNT(*) AS session_count
FROM   gv$session
WHERE  username IN ('TPCC', 'SYSTEM')
GROUP BY inst_id, username, status
ORDER BY inst_id, username;

-- -----------------------------------------------------------------------------
-- 2) Active sessions by instance + machine (client hostnames)
-- -----------------------------------------------------------------------------
SELECT s.inst_id,
       s.username,
       s.machine,
       s.program,
       COUNT(*) AS cnt
FROM   gv$session s
WHERE  s.username = 'TPCC'
  AND  s.status = 'ACTIVE'
GROUP BY s.inst_id, s.username, s.machine, s.program
ORDER BY s.inst_id;

-- -----------------------------------------------------------------------------
-- 3) gv$active_session_history — wait event mix (last 10 minutes, if licensed)
-- -----------------------------------------------------------------------------
SELECT a.inst_id,
       a.event,
       COUNT(*) AS ash_samples
FROM   gv$active_session_history a
WHERE  a.sample_time > SYSDATE - (10 / 1440)
  AND  a.user_id = (SELECT user_id FROM dba_users WHERE username = 'TPCC')
GROUP BY a.inst_id, a.event
ORDER BY ash_samples DESC;

-- -----------------------------------------------------------------------------
-- 4) gv$sql — top SQL by elapsed time (recent footprint; not time-windowed)
-- -----------------------------------------------------------------------------
SELECT s.inst_id,
       s.sql_id,
       SUBSTR(s.sql_text, 1, 100) AS sql_preview,
       s.executions,
       ROUND(s.elapsed_time / 1e6, 2) AS elapsed_sec
FROM   gv$sql s
WHERE  UPPER(s.sql_text) LIKE '%TPCC%'
    OR UPPER(s.sql_text) LIKE '%NEWORD%'
ORDER BY s.elapsed_time DESC
FETCH FIRST 30 ROWS ONLY;

-- -----------------------------------------------------------------------------
-- 5) Service-level: which instances run the service (srvctl is authoritative;
--    this query shows runtime service registration)
-- -----------------------------------------------------------------------------
SELECT inst_id, name, network_name
FROM   gv$services
WHERE  name NOT LIKE 'SYS%'
ORDER BY inst_id, name;
