# Oracle CDC XStream Connector Setup in OCI RAC - Execution Guide

This document records **all commands and expected outputs** in execution order. Use it as a reference for anyone setting up or troubleshooting the setup.

> **Primary deployment:** This project uses the **Docker 3-broker cluster**. See [IMPLEMENTATION-GUIDE.md](IMPLEMENTATION-GUIDE.md) for the recommended setup. Parts 1–5 (Oracle Database) apply to both Docker and bare-metal. Parts 6+ document legacy bare-metal Confluent setup for reference.

---

## Overview

| Phase | Where | Purpose |
|-------|-------|---------|
| **1. Oracle Database** | RAC DB (SQL*Plus) | Enable XStream, create users, sample schema, outbound server |
| **2. VM Setup** | Connector VM | Install Confluent, Oracle client, JARs |
| **3. Connector** | VM | Start services, deploy connector |
| **4. Validation** | VM | Verify Kafka, Connect, connector, CDC events |
| **5. Start/Stop** | VM | Start/stop individual components, check status |
| **0. Teardown** | DB + VM | Remove XStream outbound, connector, Kafka data (start from scratch) |

---

# Part 0: Teardown (Start from Scratch)

**When:** To remove all CDC configuration and start fresh.

## 0.1 Full teardown (DB + VM)

**From VM:**
```bash
cd /home/opc/oracle-xstream-cdc-poc

# DB + VM teardown (drops XStream outbound, stops Confluent, deletes Kafka data)
DB_SYS_PWD='<sys_password>' ./admin-commands/teardown-all.sh

# VM only (skip DB):
./admin-commands/teardown-all.sh --vm-only

# DB only (skip VM):
DB_SYS_PWD='<pwd>' ./admin-commands/teardown-all.sh --db-only
```

**Full VM reinstall** (remove Confluent + Oracle client, then run setup-vm.sh again):
```bash
TEARDOWN_FULL=true ./admin-commands/teardown-all.sh --vm-only
# Then: sudo ./admin-commands/setup-vm.sh
```

## 0.2 Setup from scratch (after teardown)

```bash
cd /home/opc/oracle-xstream-cdc-poc

# VM only (Confluent + connector; assumes DB 01-06 already run)
./admin-commands/setup-from-scratch.sh

# Full (DB outbound + VM)
DB_SYS_PWD='<pwd>' ./admin-commands/setup-from-scratch.sh --with-db

# If c##xstrmadmin has a different password:
DB_SYS_PWD='<sys_pwd>' DB_XSTRM_PWD='<xstrmadmin_pwd>' ./admin-commands/setup-from-scratch.sh --with-db
```

**Prerequisites for --with-db:** Oracle scripts 01-05 must have been run at least once (schema, users, supplemental logging). The teardown only drops the XStream outbound (06); it does not drop the schema.

---

# Part 1: Oracle Database Setup

**Where:** Connect to RAC database via SQL*Plus (from VM or any host with Oracle client)  
**User:** SYSDBA for most scripts; `ordermgmt` for data load; `c##xstrmadmin` for outbound

---

## 1.1 Connect to Database

```bash
# From VM or host with SQL*Plus
sqlplus sys/'<SYS_password>'@//racdb-scan.<your-vcn>.oraclevcn.com:1521/<db-service>.oraclevcn.com as sysdba
```

**Why:** Establish session as SYSDBA to run admin scripts.

**Expected output:**
```
SQL*Plus: Release 19.0.0.0.0 - Production
Connected to:
Oracle Database 19c EE ...
SQL>
```

**Check:** You see `SQL>` and no connection error.

---

## 1.2 Run 01-create-sample-schema.sql

```sql
SQL> @01-create-sample-schema.sql
```

**Why:** Creates ORDERMGMT schema (tablespaces, user, tables) in PDB XSTRPDB. This is the source schema for CDC.

**Expected output:**
```
Session altered.
PL/SQL procedure successfully completed.
User created.
Grant succeeded.
...
Table created.
...
```

**Check:**
- No `ORA-65096` (would mean running in CDB root instead of PDB)
- No `ORA-28003` (password policy – use `<password>` or similar)
- `User created` and `Table created` for all objects

**Common errors:**
| Error | Cause | Fix |
|-------|-------|-----|
| ORA-65096 | In CDB root | Script includes `ALTER SESSION SET CONTAINER = XSTRPDB` |
| ORA-28003 | Password too weak | Use password with 2+ uppercase, 2+ lowercase, 1+ digit, 1+ special |
| ORA-01543 | Tablespace exists | Script handles this; safe to ignore |

---

## 1.3 Run 02-enable-xstream.sql

```sql
SQL> @02-enable-xstream.sql
```

**Why:** Enables XStream (GoldenGate replication) and checks ARCHIVELOG. Required for CDC.

**Expected output:**
```
System altered.

INSTANCE_NAME    VALUE
---------------- -----
1                TRUE
2                TRUE

LOG_MODE
------------
ARCHIVELOG
```

**Check:**
- `VALUE` = `TRUE` for all instances
- `LOG_MODE` = `ARCHIVELOG`

---

## 1.4 Run 03-supplemental-logging.sql

```sql
SQL> @03-supplemental-logging.sql
```

**Why:** Enables supplemental logging so full row data is in redo logs for CDC.

**Expected output:**
```
Database altered.
Session altered.
Table altered.
... (for each ORDERMGMT table)
```

**Check:** No `ORA-00942` (table or view does not exist). If you see it, run 01 first.

---

## 1.5 Run 04-create-xstream-users.sql

```sql
SQL> @04-create-xstream-users.sql
```

**Why:** Creates XStream admin (`c##xstrmadmin`) and connect user (`c##cfltuser`) with required privileges.

**Expected output:**
```
Session altered.
PL/SQL procedure successfully completed.
...
User created.
Grant succeeded.
...
```

**Check:**
- No `ORA-28003` (password policy)
- No `ORA-01917` (user does not exist) – means CREATE USER failed earlier

---

## 1.6 Run 05-load-sample-data.sql

**Connect as ordermgmt:**
```bash
sqlplus ordermgmt/"<password>"@//racdb-scan.<your-vcn>.oraclevcn.com:1521/XSTRPDB.<your-vcn>.oraclevcn.com
```

```sql
SQL> @05-load-sample-data.sql
```

**Why:** Loads sample data into ORDERMGMT tables for CDC testing.

**Expected output:**
```
1 row created.
...
Commit complete.
```

**Check:** No `ORA-00942` (table does not exist).

---

## 1.7 Run 06-create-outbound-ordermgmt.sql

**Connect as c##xstrmadmin:**
```bash
sqlplus c##xstrmadmin/'<password>'@//racdb-scan.../DB0312... as sysdba
```

```sql
SQL> @06-create-outbound-ordermgmt.sql
```

**Why:** Creates XStream Out (capture process, queue, outbound server) for ORDERMGMT tables.

**Expected output:**
```
PL/SQL procedure successfully completed.
PL/SQL procedure successfully completed.
...

SERVER_NAME  CONNECT_USER   CAPTURE_NAME
------------ -------------- ----------------
XOUT         C##CFLTUSER    CONFLUENT_XOUT1
```

**Check:**
- `CONNECT_USER` = `C##CFLTUSER`
- `SERVER_NAME` = `XOUT`

---

## 1.7a Run 04b-grant-ordermgmt-select.sql (REQUIRED – fixes "only REGIONS topic")

**Connect as SYSDBA:**
```sql
SQL> @04b-grant-ordermgmt-select.sql
```

**Why:** Grants SELECT on all ORDERMGMT tables to `c##cfltuser`. Without this, the connector skips all tables except REGIONS with "database user does not have access to this table".

**Expected output:**
```
Session altered.
PL/SQL procedure successfully completed.
```

**Check:** If you see only `racdb.XSTRPDB.ORDERMGMT.REGIONS` topic, run this script and then trigger data changes (see 1.7b).

---

## 1.7b Trigger data changes (creates topics for other tables)

**Root cause:** The connector creates topics when it first writes data. In CDC streaming mode, it only writes when changes (INSERT/UPDATE/DELETE) occur. Tables with no changes since the connector started never get topics.

**Fix:** Load sample data to trigger CDC events on all tables. Run as `ordermgmt`:

```bash
export LD_LIBRARY_PATH=/opt/oracle/instantclient/instantclient_19_30:$LD_LIBRARY_PATH
export PATH=/opt/oracle/instantclient/instantclient_19_30:$PATH

sqlplus ordermgmt/"<password>"@//racdb-scan.<your-vcn>.oraclevcn.com:1521/XSTRPDB.<your-vcn>.oraclevcn.com @/home/opc/oracle-xstream-cdc-poc/oracle-database/05-load-sample-data.sql
```

Then restart the connector and wait 2–3 minutes:

```bash
curl -X POST http://localhost:8083/connectors/oracle-xstream-rac-connector/restart
sleep 120
/opt/confluent/confluent/bin/kafka-topics --bootstrap-server localhost:9092 --list | grep racdb
```

---

## 1.8 Get XStream Service Name (for connector config)

```sql
SQL> SELECT inst_id, service_id, name, network_name 
  2  FROM gv$SERVICES 
  3  WHERE NAME LIKE '%XOUT%';
```

**Why:** Connector needs `database.service.name` = `network_name` for RAC.

**Expected output:**
```
   INST_ID SERVICE_ID
---------- ----------
NAME
----------------------------------------------------------------
NETWORK_NAME
--------------------------------------------------------------------------------
         1          3
SYS.Q$_XOUT_5
SYS$SYS.Q$_XOUT_5.DB0312.<YOUR_SERVICE>.ORACLEVCN.COM
```

**Check:** Copy `NETWORK_NAME` into `oracle-xstream-rac.json` as `database.service.name`.

---

## 1.8a Check and start XStream capture/apply (if disabled)

**When:** After creating outbound (1.7), or when connector shows no CDC events and capture/apply may be stopped.

**From VM (recommended):**
```bash
cd /home/opc/oracle-xstream-cdc-poc
DB_SYS_PWD='<sys_password>' ./admin-commands/check-and-start-xstream.sh
```

**Or manually via SQL*Plus:**
```sql
SQL> @08-verify-xstream-outbound.sql   -- verify status
SQL> @09-check-and-start-xstream.sql   -- start capture/apply if disabled
```

**Why:** Capture (CONFLUENT_XOUT1) and Apply (XOUT) must be ENABLED for CDC. If they are DISABLED or not found, the connector receives no events.

**Expected output (when outbound exists):**
```
Outbound: XOUT ENABLED
Capture:  CONFLUENT_XOUT1 ENABLED
Apply:    XOUT ENABLED
```

**If capture/apply not found:** Run `06-create-outbound-ordermgmt.sql` as `c##xstrmadmin` first (see 1.7).

---

# Part 2: VM Setup (Connector Host)

**Where:** connector-vm (<vm-public-ip>)  
**User:** opc

---

## 2.1 Copy Project to VM (from Mac)

```bash
cd /Users/maniselvank/Mani/customer/airtel
scp -i /path/to/your-ssh-key.pem -r oracle-xstream-cdc-poc opc@<vm-public-ip>:/home/opc/
```

**Why:** Bring scripts, configs, and connector JSON to the VM.

**Expected output:**
```
oracle-xstream-rac.json    100%  ...
...
```

**Check:** No permission or connection errors.

---

## 2.2 Run setup-vm.sh

```bash
ssh -i /path/to/ssh-key-2026-03-12.key opc@<vm-public-ip>

chmod +x /home/opc/oracle-xstream-cdc-poc/admin-commands/setup-vm.sh
sudo /home/opc/oracle-xstream-cdc-poc/admin-commands/setup-vm.sh
```

**Why:** Installs Java 17, Confluent Platform 7.9, Oracle XStream CDC connector.

**Expected output:**
```
=== Oracle XStream CDC - VM Setup (Confluent Platform 7.9.0) ===
Installing prerequisites...
...
Downloading Confluent Platform 7.9.0...
...
Installing Oracle XStream CDC connector...
=== Setup complete ===
```

**Check:** No download or install failures. Allow ~10–15 minutes.

---

## 2.3 Install Oracle Instant Client

**Why:** Provides native Oracle libraries and JARs for the connector.

1. Download `instantclient-basic-linux.x64-19.*.zip` from Oracle.
2. On VM:

```bash
sudo cp instantclient-basic-linux.x64-19.30.0.0.0dbru.zip /opt/oracle/instantclient/
cd /opt/oracle/instantclient
sudo unzip instantclient-basic-linux.x64-19.30.0.0.0dbru.zip
```

**Expected output:**
```
inflating: instantclient_19_30/ojdbc8.jar
...
```

**Check:** `ojdbc8.jar` and `xstreams.jar` exist under `instantclient_19_30/`.

---

## 2.4 Copy Oracle JARs to Connector Lib

```bash
sudo cp /opt/oracle/instantclient/instantclient_19_30/ojdbc8.jar \
  /opt/confluent/confluent/share/confluent-hub-components/confluentinc-kafka-connect-oracle-xstream-cdc-source/lib/
sudo cp /opt/oracle/instantclient/instantclient_19_30/xstreams.jar \
  /opt/confluent/confluent/share/confluent-hub-components/confluentinc-kafka-connect-oracle-xstream-cdc-source/lib/
```

**Why:** Connector needs these JARs to talk to Oracle XStream.

**Verify:**
```bash
ls -la /opt/confluent/confluent/share/confluent-hub-components/confluentinc-kafka-connect-oracle-xstream-cdc-source/lib/
```

**Expected:** `ojdbc8.jar` and `xstreams.jar` listed.

---

## 2.5 Set LD_LIBRARY_PATH

```bash
export LD_LIBRARY_PATH=/opt/oracle/instantclient/instantclient_19_30:$LD_LIBRARY_PATH
echo 'export LD_LIBRARY_PATH=/opt/oracle/instantclient/instantclient_19_30:$LD_LIBRARY_PATH' | sudo tee /etc/profile.d/oracle-instantclient.sh
```

**Why:** Kafka Connect loads Oracle native libs from this path.

---

## 2.6 Fix Confluent Logs Permissions (first run only)

```bash
sudo mkdir -p /opt/confluent/confluent/logs
sudo chown -R opc:opc /opt/confluent/confluent/logs
```

**Why:** Confluent was installed with sudo; `opc` needs write access to logs.

---

## 2.7 Start Confluent Platform (KRaft)

```bash
export LD_LIBRARY_PATH=/opt/oracle/instantclient/instantclient_19_30:$LD_LIBRARY_PATH
cd /home/opc/oracle-xstream-cdc-poc
chmod +x admin-commands/start-confluent-kraft.sh
./admin-commands/start-confluent-kraft.sh
```

**Why:** Starts Kafka (KRaft), Schema Registry, and Kafka Connect without Zookeeper.

**Expected output:**
```
=== Starting Confluent Platform 7.9 (KRaft mode) ===
Formatting Kafka storage for KRaft...
Starting Kafka (KRaft)...
Waiting for Kafka broker...
Kafka ready.
Starting Schema Registry...
Starting Kafka Connect (config: .../docs/optional/connect-distributed-kraft.properties)...
Waiting 120s for Connect to join cluster (avoids 'ensuring membership' timeout)...

=== Confluent Platform started (KRaft mode) ===
Kafka: localhost:9092
Schema Registry: http://localhost:8081
Kafka Connect: http://localhost:8083
```

**Check:** No `Permission denied` or `kafka-storage: No such file or directory`. The script uses `docs/optional/connect-distributed-kraft.properties` (longer timeouts) to avoid "ensuring membership" timeouts.

---

# Part 3: Connector Deployment

---

## 3.1 Update Connector Config

Edit `xstream-connector/oracle-xstream-rac.json`:

- `database.service.name` = `network_name` from step 1.8
- `database.password` = connect user password
- `table.include.list` = ORDERMGMT tables (or your schema.table list)

---

## 3.2 Deploy Connector

```bash
cd /home/opc/oracle-xstream-cdc-poc
curl -X POST -H "Content-Type: application/json" \
  --data @xstream-connector/oracle-xstream-rac.json \
  http://localhost:8083/connectors
```

**Why:** Registers the Oracle XStream CDC connector with Kafka Connect.

**Expected output:**
```json
{"name":"oracle-xstream-rac-connector","config":{...},"tasks":[],"type":"source"}
```

**Check:** JSON returned with `"name":"oracle-xstream-rac-connector"`. No HTTP error.

---

# Part 4: Validation

---

## 4.1 Validate Kafka

```bash
/opt/confluent/confluent/bin/kafka-broker-api-versions --bootstrap-server localhost:9092 | head -5
```

**Why:** Confirms Kafka broker is up and reachable.

**Expected output:**
```
localhost:9092 (id: 1 rack: null) -> (
    Produce(0): 0 to 11 [usable: 11],
    Fetch(1): 0 to 17 [usable: 17],
    ...
```

**Check:** Broker ID and API versions listed. No connection refused.

---

## 4.2 Validate Kafka Connect

```bash
curl -s http://localhost:8083/
```

**Why:** Confirms Kafka Connect REST API is up.

**Expected output:**
```json
{"version":"7.9.0-ce","commit":"473b953fc5d32797","kafka_cluster_id":"5WYYQc08RJe3CXbfyygzBQ"}
```

**Check:** JSON with `version` and `kafka_cluster_id`. HTTP 200.

---

## 4.3 Validate Connector Status

```bash
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status
```

**Why:** Shows connector and task state.

**Expected output (running):**
```json
{"name":"oracle-xstream-rac-connector","connector":{"state":"RUNNING","worker_id":"..."},"tasks":[{"id":0,"state":"RUNNING","worker_id":"..."}]}
```

**Check:**
- `connector.state` = `RUNNING`
- `tasks[].state` = `RUNNING`

**If FAILED:** Inspect `curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status` and Connect worker logs.

---

## 4.4 List Connectors

```bash
curl -s http://localhost:8083/connectors
```

**Expected output:**
```json
["oracle-xstream-rac-connector"]
```

---

## 4.5 List Kafka Topics (CDC)

```bash
/opt/confluent/confluent/bin/kafka-topics --bootstrap-server localhost:9092 --list | grep racdb
```

**Why:** Confirms CDC topics created by the connector.

**Expected output (example):**
```
racdb.XSTRPDB.ORDERMGMT.REGIONS
racdb.XSTRPDB.ORDERMGMT.COUNTRIES
...
```

---

## 4.6 Consume CDC Events

```bash
/opt/confluent/confluent/bin/kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic racdb.XSTRPDB.ORDERMGMT.REGIONS --from-beginning
```

**Why:** Verifies CDC records are produced.

**Expected:** JSON change events (snapshot and/or streamed). Press Ctrl+C to stop.

---

## 4.7 Test CDC (Optional)

In Oracle, run DML:

```sql
-- Connect as ordermgmt
INSERT INTO regions (region_id, region_name) VALUES (99, 'Test Region');
COMMIT;
```

Then consume again; you should see a new event for the insert.

---

# Part 5: Confluent Platform – Start, Status, Stop

**Where:** VM (connector-vm)  
**Prerequisite:** `export LD_LIBRARY_PATH=/opt/oracle/instantclient/instantclient_19_30:$LD_LIBRARY_PATH`

---

## 5.1 Start All Components (Recommended)

```bash
cd /home/opc/oracle-xstream-cdc-poc
./admin-commands/start-confluent-kraft.sh
```

**Why:** Starts Kafka, Schema Registry, and Kafka Connect in the correct order with built-in delays.

**Expected output:**
```
=== Starting Confluent Platform 7.9 (KRaft mode) ===
Formatting Kafka storage for KRaft...   (first run only)
Starting Kafka (KRaft)...
Starting Schema Registry...
Starting Kafka Connect...
=== Confluent Platform started (KRaft mode) ===
```

---

## 5.2 Start Individual Components

Use when you need to start or restart components separately.

### Start Kafka (must run first)

```bash
export LD_LIBRARY_PATH=/opt/oracle/instantclient/instantclient_19_30:$LD_LIBRARY_PATH
cd /home/opc/oracle-xstream-cdc-poc

/opt/confluent/confluent/bin/kafka-server-start -daemon config/server-kraft.properties
```

**Why:** Kafka broker is the foundation; Schema Registry and Connect depend on it.

**Check status:** Wait ~15 seconds, then run 5.4.1 below.

---

### Start Schema Registry (after Kafka)

```bash
/opt/confluent/confluent/bin/schema-registry-start -daemon config/schema-registry-kraft.properties
sleep 10
```

**Why:** Schema Registry stores Avro/JSON schemas; some connectors use it.

**Check status:** Run 5.4.2 below.

---

### Start Kafka Connect (after Kafka is ready)

**Recommended:** Use project config with longer timeouts (avoids "ensuring membership" issues):

```bash
cd /home/opc/oracle-xstream-cdc-poc
# Ensure Kafka is ready first
/opt/confluent/confluent/bin/kafka-broker-api-versions --bootstrap-server localhost:9092 | head -1

/opt/confluent/confluent/bin/connect-distributed -daemon docs/optional/connect-distributed-kraft.properties
sleep 120
```

**Fallback:** Confluent default config (may timeout on slow VMs):

```bash
/opt/confluent/confluent/bin/connect-distributed -daemon /opt/confluent/confluent/etc/kafka/connect-distributed.properties
sleep 120
```

**Why:** Kafka Connect must join the cluster before accepting connector deploys. The project config increases `rebalance.timeout.ms` and `session.timeout.ms` so Connect has more time to join.

**Check status:** Run 5.4.3 below.

---

## 5.3 Stop All Components

```bash
cd /home/opc/oracle-xstream-cdc-poc
./admin-commands/stop-confluent-kraft.sh
```

**Why:** Gracefully stops Connect, Schema Registry, and Kafka.

**Or stop manually:**
```bash
pkill -f connect-distributed
pkill -f schema-registry
pkill -f kafka-server
sleep 3
```

---

## 5.4 Check Status of Each Component

### 5.4.1 Kafka

```bash
/opt/confluent/confluent/bin/kafka-broker-api-versions --bootstrap-server localhost:9092 | head -3
```

**Expected output:**
```
localhost:9092 (id: 1 rack: null) -> (
    Produce(0): 0 to 11 [usable: 11],
    Fetch(1): 0 to 17 [usable: 17],
```

**Check:** Broker ID and API versions listed. No "Connection refused".

---

### 5.4.2 Schema Registry

```bash
curl -s http://localhost:8081/
```

**Expected output:**
```json
{"schema_registry":"..."}
```

**Check:** JSON response. HTTP 200.

---

### 5.4.3 Kafka Connect

```bash
curl -s http://localhost:8083/
```

**Expected output:**
```json
{"version":"7.9.0-ce","commit":"...","kafka_cluster_id":"..."}
```

**Check:** `version` and `kafka_cluster_id` present. Do not deploy connector until this returns successfully.

---

### 5.4.4 Connector

```bash
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status
```

**Expected output (running):**
```json
{"name":"oracle-xstream-rac-connector","connector":{"state":"RUNNING",...},"tasks":[{"state":"RUNNING",...}]}
```

**Check:** `connector.state` and `tasks[].state` = `RUNNING`.

---

### 5.4.5 Process Check (all components)

```bash
ps aux | grep -E "kafka|Kafka|schema-registry|connect" | grep -v grep
```

**Expected:** One process each for:
- `kafka.Kafka` (broker)
- `SchemaRegistryMain` (Schema Registry)
- `ConnectDistributed` (Kafka Connect)

---

### 5.4.6 Port Check

```bash
ss -tlnp | grep -E "9092|8081|8083"
```

**Expected:**
```
LISTEN  0  128  *:9092  *:*  users:(("java",...))
LISTEN  0  128  *:8081  *:*  users:(("java",...))
LISTEN  0  128  *:8083  *:*  users:(("java",...))
```

---

## 5.5 Start Order Summary

| Order | Component | Command | Wait before next |
|-------|-----------|---------|------------------|
| 1 | Kafka | `kafka-server-start -daemon config/server-kraft.properties` | Until `kafka-broker-api-versions` succeeds |
| 2 | Schema Registry | `schema-registry-start -daemon config/schema-registry-kraft.properties` | 10 sec |
| 3 | Connect | `connect-distributed -daemon docs/optional/connect-distributed-kraft.properties` | 120 sec |
| 4 | Connector | `curl -X POST .../connectors` | — |

---

## 5.6 Stop Order Summary

| Order | Component | Command |
|-------|-----------|---------|
| 1 | Connect | `pkill -f connect-distributed` |
| 2 | Schema Registry | `pkill -f schema-registry` |
| 3 | Kafka | `pkill -f kafka-server` |

Or use: `./admin-commands/stop-confluent-kraft.sh`

---

# Part 6: Onboard New Tables to Existing CDC Pipeline

**When:** You have an existing CDC pipeline and want to add more tables without recreating the outbound server.

**Prerequisites:** XStream outbound already running (06-create-outbound-ordermgmt.sql completed); connector deployed and running.

**Official reference:** [Confluent – Add tables to the capture set](https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/examples.html#add-tables-to-the-capture-set). This guide aligns with that approach.

---

## 6.1 Overview

To add a new table to the CDC pipeline, you must:

1. **Oracle DB:** Add supplemental logging for the new table
2. **Oracle DB:** Grant SELECT on the table to `c##cfltuser`
3. **Oracle DB:** Add the table to the XStream capture and outbound rules
4. **Connector:** Update `table.include.list` and restart the connector

---

## 6.2 Step 1: Supplemental Logging (Oracle)

Connect as SYSDBA to the PDB and enable supplemental logging for the new table:

```sql
ALTER SESSION SET CONTAINER = XSTRPDB;

-- Replace SCHEMA.TABLE with your table (e.g. ORDERMGMT.NEW_ORDERS)
ALTER TABLE ORDERMGMT.NEW_ORDERS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
```

---

## 6.3 Step 2: Grant SELECT (Oracle)

Grant SELECT to the connector user:

```sql
ALTER SESSION SET CONTAINER = XSTRPDB;

GRANT SELECT ON ORDERMGMT.NEW_ORDERS TO c##cfltuser;
```

---

## 6.4 Step 3: Add Table to XStream Outbound (Oracle)

Connect as **c##xstrmadmin** (XStream admin) to the **CDB** (not PDB). Get the queue name first:

```sql
-- Get queue used by capture (run as SYSDBA)
SELECT queue_owner, queue_name FROM dba_capture WHERE capture_name = 'CONFLUENT_XOUT1';
-- Example output: SYS  SYS_XSTREAM$_XOUT_QUEUE
```

Then add the table to both capture and apply (outbound) rules:

```sql
-- Connect as: sqlplus c##xstrmadmin/<pwd>@//host:1521/DB0312_r8n_phx... as sysdba

-- Replace SCHEMA.TABLE and queue_owner.queue_name with your values
-- Example: ORDERMGMT.NEW_ORDERS and SYS.SYS_XSTREAM$_XOUT_QUEUE

-- 1. Add to capture (so changes are captured from redo)
DBMS_XSTREAM_ADM.ADD_TABLE_RULES(
  table_name             => 'ORDERMGMT.NEW_ORDERS',
  streams_type           => 'capture',
  streams_name           => 'confluent_xout1',
  queue_name             => 'SYS.SYS_XSTREAM$_XOUT_QUEUE',  -- from query above
  include_dml            => TRUE,
  include_ddl            => FALSE,
  source_container_name  => 'XSTRPDB');

-- 2. Add to apply/outbound (so changes are streamed to connector)
DBMS_XSTREAM_ADM.ADD_TABLE_RULES(
  table_name             => 'ORDERMGMT.NEW_ORDERS',
  streams_type           => 'apply',
  streams_name           => 'xout',
  queue_name             => 'SYS.SYS_XSTREAM$_XOUT_QUEUE',  -- from query above
  include_dml            => TRUE,
  include_ddl            => FALSE,
  source_container_name  => 'XSTRPDB');
```

**Note:** Queue name may vary (e.g. `SYS.SYS_XSTREAM$_XOUT_QUEUE` or `C##XSTRMADMIN.XOUT_QUEUE`). Always query `dba_capture` first.

---

## 6.5 Step 4: Update Connector Config (VM)

1. Edit `xstream-connector/oracle-xstream-rac-docker.json` (Docker) or `oracle-xstream-rac.json` (standalone) and add the new table to `table.include.list`:

```json
"table.include.list": "ORDERMGMT\\.(REGIONS|COUNTRIES|LOCATIONS|WAREHOUSES|EMPLOYEES|PRODUCT_CATEGORIES|PRODUCTS|CUSTOMERS|CONTACTS|ORDERS|ORDER_ITEMS|INVENTORIES|NOTES|NEW_ORDERS)"
```

2. Update the connector config via REST API (no need to delete/recreate):

```bash
cd /home/opc/oracle-xstream-cdc-poc

# Get current config, update table.include.list, then PUT
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/config | \
  jq '. + {"table.include.list": "ORDERMGMT\\.(REGIONS|COUNTRIES|LOCATIONS|WAREHOUSES|EMPLOYEES|PRODUCT_CATEGORIES|PRODUCTS|CUSTOMERS|CONTACTS|ORDERS|ORDER_ITEMS|INVENTORIES|NOTES|NEW_ORDERS)"}' | \
  jq 'del(.name)' | \
  curl -s -X PUT -H "Content-Type: application/json" -d @- \
  http://localhost:8083/connectors/oracle-xstream-rac-connector/config

# Restart connector to pick up new tables
curl -X POST "http://localhost:8083/connectors/oracle-xstream-rac-connector/restart?includeTasks=true"
```

3. Verify the new topic (Docker):

```bash
docker exec kafka2 kafka-topics --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 --list | grep NEW_ORDERS
```

For standalone Confluent: `kafka-topics --bootstrap-server localhost:9092 --list | grep NEW_ORDERS`

---

## 6.6 Snapshot Mode for New Tables

- **`snapshot.mode=initial`:** Connector will run a full snapshot of the new table on restart (creates topic with existing data).
- **`snapshot.mode=no_data`:** Connector will only stream changes; no initial snapshot. Use if you only need incremental changes.

---

## 6.7 Scripted Approach

Use `oracle-database/11-add-table-to-cdc.sql` to add a table to XStream in one go (steps 6.2 and 6.3 must be run first):

```bash
# From VM or host with SQL*Plus, connect as c##xstrmadmin to CDB
sqlplus c##xstrmadmin/<pwd>@//racdb-scan...:1521/DB0312_r8n_phx... as sysdba @11-add-table-to-cdc.sql "ORDERMGMT.NEW_ORDERS"
```

---

## 6.8 UG Production Tables (Bulk Onboard in ORDERMGMT)

To onboard all UG prod tables from `UG-prod-DDL.txt` (excluding `MTX_TRANSACTION_ITEMS`, which already exists in ORDERMGMT), use the pattern from `MTX_TRANSACTION_ITEMS`: schema **ORDERMGMT**, tablespace **ordermgmt_tbs**, supplemental logging, and grants.

**Steps:**

1. **Drop and recreate tables in ORDERMGMT** (run as SYSDBA in PDB):

   ```bash
   sqlplus c##xstrmadmin/<pwd>@//host:1521/SERVICE as sysdba @oracle-database/ug-prod-ordermgmt-drop-and-create.sql
   ```

   This script drops any existing UG prod tables in ORDERMGMT, recreates them with `TABLESPACE ordermgmt_tbs` (no FKs), adds supplemental logging, and grants `SELECT` to `c##cfltuser`.

2. **Add tables to XStream capture/apply**:

   ```bash
   cd oracle-database
   export ORACLE_PWD='<c##xstrmadmin password>'
   export ORACLE_CONN='//racdb-scan...:1521/DB0312...'  # optional; default localhost
   ./ug-prod-onboard-xstream.sh
   ```

3. **On VM – deploy topics and connector** (automatic):

   ```bash
   ./docker/scripts/onboard-tables-deploy-on-vm.sh
   ```

   This pre-creates topics, syncs `table.include.list` from `.example`, and restarts the connector. Optional: run from DB host with `ONBOARD_VM_IP=<vm-ip> ./ug-prod-onboard-xstream.sh` to trigger via SSH.

4. **Populate tables for CDC** (so topics receive data):

   ```bash
   cd oracle-database && ./run-generate-ug-prod-cdc-load.sh
   ```

**Tables onboarded:** 30 tables in **ORDERMGMT** (excludes MTX_TRANSACTION_ITEMS). See `oracle-database/ug-prod-ordermgmt-drop-and-create.sql` and `ug-prod-onboard-xstream.sh` for the full list.

---

# Quick Reference: Execution Order

| # | Phase | Command / Action |
|---|-------|------------------|
| 1 | DB | `@01-create-sample-schema.sql` |
| 2 | DB | `@02-enable-xstream.sql` |
| 3 | DB | `@03-supplemental-logging.sql` |
| 4 | DB | `@04-create-xstream-users.sql` |
| 5 | DB | `@05-load-sample-data.sql` (as ordermgmt) |
| 6 | DB | `@06-create-outbound-ordermgmt.sql` (as c##xstrmadmin) |
| 7 | DB | Get `network_name` from `gv$SERVICES` |
| 8 | VM | Copy project, run `setup-vm.sh` |
| 9 | VM | Install Instant Client, copy JARs |
| 10 | VM | Fix logs permissions, start Confluent |
| 11 | VM | Deploy connector via curl |
| 12 | VM | Validate Kafka, Connect, connector, consume events |

---

# Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| Connector FAILED | `curl .../status` | Inspect `trace` in response; check DB connectivity, user, service name |
| No topics | Connector running? | Wait for snapshot; verify `table.include.list` matches outbound |
| Only REGIONS topic | table.include.list format | Use PDB format: `.*\.ORDERMGMT\.(REGIONS|COUNTRIES|...)` – see [FIX-ONLY-REGIONS-TOPIC.md](FIX-ONLY-REGIONS-TOPIC.md) |
| ORA-12514 | Service name | Use `network_name` from `gv$SERVICES` |
| Permission denied (logs) | Ownership | `sudo chown -R opc:opc /opt/confluent/confluent/logs` |
| kafka-storage not found | Confluent install | Use full Confluent tar; ensure `bin/kafka-storage` exists |
| "Request timed out... ensuring membership" | See below | Use project Connect config, Kafka readiness check, longer wait |
| Connection to localhost:9092 could not be established | Kafka down | Start Kafka first; verify with `kafka-broker-api-versions` |
| 404 No status for connector | Connector not deployed | Deploy with `curl -X POST .../connectors`; previous deploy may have timed out |

---

## "Ensuring Membership" Timeout – Detailed Fix

If connector deploy returns `500 Request timed out. The worker is currently ensuring membership in the cluster` even after waiting 90+ seconds:

### Root cause: Stale consumer group from unclean shutdown

When Connect is killed with pkill (or crashes) without graceful shutdown: (1) Connect does not send LeaveGroup to the broker; (2) the broker keeps the old worker in the connect-cluster group; (3) when you restart, the new worker joins and triggers a rebalance; (4) the rebalance waits for all members including the dead one to sync; (5) the dead member never responds—the broker removes it only after session.timeout.ms (30 sec); (6) until then, Connect is stuck in "ensuring membership". Restarting without waiting does not help.

### Fix 1: Wait for dead member to time out (required)

After stopping Connect, wait at least 40 seconds before starting again (must exceed session.timeout.ms = 30 sec):

```bash
pkill -f connect-distributed
sleep 40
cd /home/opc/oracle-xstream-cdc-poc
/opt/confluent/confluent/bin/connect-distributed -daemon docs/optional/connect-distributed-kraft.properties
sleep 120
curl -X POST -H "Content-Type: application/json" --data @xstream-connector/oracle-xstream-rac.json http://localhost:8083/connectors
```

### Fix 2: Reset connect-cluster group (clean slate)

If Fix 1 still fails, delete the consumer group so Connect starts fresh:

```bash
pkill -f connect-distributed
sleep 40
/opt/confluent/confluent/bin/kafka-consumer-groups --bootstrap-server localhost:9092 --group connect-cluster --delete
cd /home/opc/oracle-xstream-cdc-poc
/opt/confluent/confluent/bin/connect-distributed -daemon docs/optional/connect-distributed-kraft.properties
sleep 120
curl -X POST -H "Content-Type: application/json" --data @xstream-connector/oracle-xstream-rac.json http://localhost:8083/connectors
```

### Fix 3: Use reset script

```bash
./admin-commands/reset-connect-cluster.sh
```

### Fix 4: Ensure Kafka is ready before Connect

Connect cannot join if Kafka is not ready. Before starting Connect:

```bash
/opt/confluent/confluent/bin/kafka-broker-api-versions --bootstrap-server localhost:9092 | head -1
```

If this fails, wait 15–30 seconds after starting Kafka and retry.

### Fix 5: Use start script (includes Kafka readiness)

```bash
./admin-commands/start-confluent-kraft.sh
```

The script waits for Kafka to be ready, uses the project Connect config, and waits 120 seconds before Connect is considered ready.

### Fix 6: Check Connect logs

```bash
tail -100 /opt/confluent/confluent/logs/connectDistributed.out
```

Look for `Connection to node -1 (localhost/127.0.0.1:9092) could not be established` – Kafka is down or unreachable. Fix Kafka first, then restart Connect.
