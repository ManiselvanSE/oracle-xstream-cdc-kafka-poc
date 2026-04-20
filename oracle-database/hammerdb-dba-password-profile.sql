-- =============================================================================
-- Share with DBA: HammerDB TPC-C user (TPCC) vs Oracle password verify profile
-- Run in PDB XSTRPDB (or target PDB) as SYS / SYSTEM with DBA privileges.
-- Lab / PoC only — review security before production.
--
-- NOTE: HammerDB issues CREATE USER without PROFILE → new users get DEFAULT profile
-- (strict PASSWORD_VERIFY_FUNCTION). Either use a tpcc_pass that passes DEFAULT
-- (see repo TCL, e.g. two $ in password) or create profile hammerdb_tpcc below.
-- =============================================================================

-- --- 1) Inspect: which profile applies to TPCC (after user exists) ---
ALTER SESSION SET CONTAINER = XSTRPDB;

SELECT username, profile, account_status
FROM   dba_users
WHERE  username = 'TPCC';

-- --- 2) See password-related limits on that profile ---
SELECT profile, resource_name, limit
FROM   dba_profiles
WHERE  profile = (SELECT profile FROM dba_users WHERE username = 'TPCC')
  AND  resource_type = 'PASSWORD'
ORDER BY resource_name;

-- Password verify function name (often ORA12C_VERIFY_FUNCTION or custom):
SELECT profile, limit AS verify_function
FROM   dba_profiles
WHERE  resource_name = 'PASSWORD_VERIFY_FUNCTION'
  AND  profile = (SELECT profile FROM dba_users WHERE username = 'TPCC');

-- =============================================================================
-- OPTION A (recommended): Dedicated profile for TPCC — relax verify for benchmark only
-- =============================================================================

-- CREATE PROFILE hammerdb_tpcc LIMIT
--   PASSWORD_VERIFY_FUNCTION NULL
--   PASSWORD_LIFE_TIME UNLIMITED
--   FAILED_LOGIN_ATTEMPTS UNLIMITED;

-- ALTER USER tpcc PROFILE hammerdb_tpcc;

-- If TPCC does not exist yet, create with this profile after HammerDB password is chosen:
-- CREATE USER tpcc IDENTIFIED BY <password> PROFILE hammerdb_tpcc ...

-- =============================================================================
-- OPTION B: One-off — assign NULL verify only to TPCC (if profile allows override)
-- Some sites use ALTER USER ... NO AUTHENTICATION — NOT recommended; use OPTION A.
-- =============================================================================

-- Same as OPTION A: create small profile + ALTER USER tpcc PROFILE hammerdb_tpcc;

-- =============================================================================
-- OPTION C (avoid): Alter DEFAULT profile — affects all users — NOT recommended
-- =============================================================================
-- ALTER PROFILE DEFAULT LIMIT PASSWORD_VERIFY_FUNCTION NULL;

-- =============================================================================
-- After change: HammerDB can use alphanumeric tpcc_pass (e.g. HammerTpcc9912) in TCL
-- or a quoted password if you pre-create TPCC manually.
-- =============================================================================
