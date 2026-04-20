-- =============================================================================
-- Oracle XStream CDC - Step 4: Create XStream Administrator and Connect Users
-- Run as SYSDBA - for CDB/PDB (multi-tenant) environment
-- Based on: https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/prereqs-validation.html
-- =============================================================================
-- Password must meet Oracle policy: 2+ uppercase, 2+ lowercase, 1+ digit, 1+ special
-- Change v_pass below if using a different password (must match connector config)
-- PDB: XSTRPDB

-- -----------------------------------------------------------------------------
-- 1. Create tablespace for XStream administrator (in ALL containers)
-- -----------------------------------------------------------------------------
ALTER SESSION SET CONTAINER = CDB$ROOT;

BEGIN
  EXECUTE IMMEDIATE 'CREATE TABLESPACE xstream_adm_tbs DATAFILE ''+DATA'' SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED';
EXCEPTION
  WHEN OTHERS THEN IF SQLCODE != -1543 THEN RAISE; END IF;  -- ORA-01543: already exists
END;
/

ALTER SESSION SET CONTAINER = XSTRPDB;

BEGIN
  EXECUTE IMMEDIATE 'CREATE TABLESPACE xstream_adm_tbs DATAFILE ''+DATA'' SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED';
EXCEPTION
  WHEN OTHERS THEN IF SQLCODE != -1543 THEN RAISE; END IF;
END;
/

-- -----------------------------------------------------------------------------
-- 2. Create XStream Administrator (capture user - common user)
-- -----------------------------------------------------------------------------
ALTER SESSION SET CONTAINER = CDB$ROOT;

DECLARE
  v_pass VARCHAR2(50) := 'YourP@ssw0rd123';  -- Change to your password; must match connector config
BEGIN
  EXECUTE IMMEDIATE 'CREATE USER c##xstrmadmin IDENTIFIED BY "' || v_pass || '" DEFAULT TABLESPACE xstream_adm_tbs QUOTA UNLIMITED ON xstream_adm_tbs CONTAINER=ALL';
EXCEPTION
  WHEN OTHERS THEN IF SQLCODE != -1920 THEN RAISE; END IF;  -- ORA-01920: user already exists
END;
/

GRANT CREATE SESSION, SET CONTAINER TO c##xstrmadmin CONTAINER=ALL;

BEGIN
  DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
    grantee                 => 'c##xstrmadmin',
    privilege_type          => 'CAPTURE',
    grant_select_privileges => TRUE,
    container               => 'ALL');
END;
/

-- -----------------------------------------------------------------------------
-- 3. Create tablespace for XStream connect user (in ALL containers)
-- -----------------------------------------------------------------------------
ALTER SESSION SET CONTAINER = CDB$ROOT;

BEGIN
  EXECUTE IMMEDIATE 'CREATE TABLESPACE xstream_tbs DATAFILE ''+DATA'' SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED';
EXCEPTION
  WHEN OTHERS THEN IF SQLCODE != -1543 THEN RAISE; END IF;
END;
/

ALTER SESSION SET CONTAINER = XSTRPDB;

BEGIN
  EXECUTE IMMEDIATE 'CREATE TABLESPACE xstream_tbs DATAFILE ''+DATA'' SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED';
EXCEPTION
  WHEN OTHERS THEN IF SQLCODE != -1543 THEN RAISE; END IF;
END;
/

-- -----------------------------------------------------------------------------
-- 4. Create XStream Connect User (common user - used by connector)
-- -----------------------------------------------------------------------------
ALTER SESSION SET CONTAINER = CDB$ROOT;

DECLARE
  v_pass VARCHAR2(50) := 'YourP@ssw0rd123';  -- Change to your password; must match connector config
BEGIN
  EXECUTE IMMEDIATE 'CREATE USER c##cfltuser IDENTIFIED BY "' || v_pass || '" DEFAULT TABLESPACE xstream_tbs QUOTA UNLIMITED ON xstream_tbs CONTAINER=ALL';
EXCEPTION
  WHEN OTHERS THEN IF SQLCODE != -1920 THEN RAISE; END IF;
END;
/

GRANT CREATE SESSION, SET CONTAINER TO c##cfltuser CONTAINER=ALL;
GRANT SELECT_CATALOG_ROLE TO c##cfltuser CONTAINER=ALL;
GRANT SELECT ANY TABLE TO c##cfltuser CONTAINER=ALL;
GRANT LOCK ANY TABLE TO c##cfltuser CONTAINER=ALL;
GRANT FLASHBACK ANY TABLE TO c##cfltuser CONTAINER=ALL;

-- Explicit SELECT on ORDERMGMT tables (connector needs this for LAST_DDL_TIME / metadata)
-- Run after 01-create-sample-schema.sql; re-run if new tables added
ALTER SESSION SET CONTAINER = XSTRPDB;
BEGIN
  FOR r IN (SELECT table_name FROM all_tables WHERE owner = 'ORDERMGMT') LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT ON ordermgmt.' || r.table_name || ' TO c##cfltuser';
  END LOOP;
END;
/
