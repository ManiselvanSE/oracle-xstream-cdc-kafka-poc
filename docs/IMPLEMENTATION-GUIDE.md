# Oracle XStream CDC to Kafka – Complete Implementation Guide

**Version:** 1.0  
**Last Updated:** March 2026

---

## Table of Contents

1. [Title and Purpose](#1-title-and-purpose)
2. [Architecture Diagram & Overview](#2-architecture-diagram--overview)
3. [Prerequisites](#3-prerequisites)
4. [Detailed Step-by-Step Setup](#4-detailed-step-by-step-setup)
5. [Migration Steps](#5-migration-steps)
6. [Testing & Verification](#6-testing--verification)
7. [Operational Runbook](#7-operational-runbook)
8. [Troubleshooting](#8-troubleshooting)
9. [Appendices](#9-appendices)

---

## 1. Title and Purpose

### 1.1 Project Title

**Oracle XStream CDC to Kafka – End-to-End Implementation**

A self-managed Change Data Capture (CDC) pipeline that streams DML and DDL changes from Oracle RAC to Apache Kafka using the Confluent Oracle XStream CDC Source Connector.

### 1.2 What This Setup Accomplishes

- **Captures** all changes (INSERT, UPDATE, DELETE) from Oracle tables in real time
- **Streams** changes to Kafka topics in Debezium JSON format
- **Supports** Oracle RAC, multi-tenant (PDB), and schema evolution
- **Provides** at-least-once delivery with snapshot and streaming phases

### 1.3 Audience

| Role | Use Case |
|------|----------|
| **Developers** | Integrate Oracle data into Kafka-based streaming applications |
| **SREs / DevOps** | Deploy, operate, and troubleshoot the CDC pipeline |
| **Data Engineers** | Design and maintain CDC pipelines for data lakes and warehouses |

---

## 2. Architecture Diagram & Overview

### 2.1 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  OCI / On-Premises Environment                                                           │
│                                                                                           │
│  ┌─────────────────────────────────┐                    ┌──────────────────────────────┐ │
│  │  Oracle RAC Database             │                    │  Connector VM                │ │
│  │  ─────────────────────────────  │                    │  ──────────────────────────  │ │
│  │  • PDB: XSTRPDB                  │  1521/TCP          │  ┌────────────────────────────┐│ │
│  │  • Schema: ORDERMGMT             │ ◄───────────────► │  │ Kafka Connect              ││ │
│  │  • XStream Out outbound server   │  XStream API      │  │ • Oracle XStream Connector ││ │
│  │  • XStream Capture process       │                    │  │ • OCI driver + Instant     ││ │
│  │  • Supplemental logging         │                    │  │   Client                   ││ │
│  └─────────────────────────────────┘                    │  └────────────┬─────────────┘│ │
│           │                                              │               │               │ │
│           │ Redo log                                     │               │ produce       │ │
│           ▼                                              │               ▼               │ │
│  ┌─────────────────────┐                                │  ┌────────────────────────────┐│ │
│  │ XStream Capture      │                                │  │ 3-Broker Kafka Cluster     ││ │
│  │ (CONFLUENT_XOUT1)    │                                │  │  • kafka1:29092 (9092)     ││ │
│  │  → LCRs              │                                │  │  • kafka2:29092 (9094)     ││ │
│  └─────────────────────┘                                │  │  • kafka3:29092 (9095)     ││ │
│                                                          │  │  • Schema Registry: 8081   ││ │
│                                                          │  │  • RF: 3                   ││ │
│                                                          │  └────────────────────────────┘│ │
│                                                          └──────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow

```
Oracle INSERT/UPDATE/DELETE
    │
    ▼
Redo log (ARCHIVELOG)
    │
    ▼
XStream Capture process
    │
    ▼
XStream Out (outbound server)
    │
    ▼
Oracle XStream CDC Connector (Kafka Connect)
    │
    ▼
Kafka topic: racdb.ORDERMGMT.<TABLE_NAME>
    │
    ▼
Downstream consumers (Kafka Streams, Flink, etc.)
```

### 2.3 Component Interaction

| Component | Role |
|-----------|------|
| **Oracle RAC** | Source database; XStream reads from redo log |
| **XStream Out** | Outbound server; delivers LCRs to connector |
| **Kafka Connect** | Runs the Oracle XStream CDC connector |
| **Kafka brokers** | Store change events; replicate for fault tolerance |
| **Schema Registry** | Optional; schema evolution for Avro (if used) |

---

## 3. Prerequisites

### 3.1 Software Versions

| Software | Version | Notes |
|----------|---------|-------|
| Oracle Database | 19c or 21c Enterprise/Standard | RAC supported |
| Confluent Platform | 7.7+ | Kafka Connect 7.9.0 used |
| Oracle XStream CDC Connector | 1.4.0+ | From Confluent Hub |
| Oracle Instant Client | 19.x | Basic + SQL*Plus packages |
| Docker | 24+ | Docker Compose v2 |
| Java | 17+ | Required by connector |

### 3.2 Accounts and Permissions

| Account | Purpose |
|---------|---------|
| **Oracle SYSDBA** | Run XStream setup scripts (01–06) |
| **c##xstrmadmin** | XStream admin user |
| **c##cfltuser** | Connector connect user |
| **ordermgmt** | Sample schema owner |
| **VM opc** | Run Docker, Kafka Connect |

### 3.3 Ports

| Port | Service |
|------|---------|
| 1521 | Oracle RAC (SCAN) |
| 9092 | Kafka broker 1 |
| 9094 | Kafka broker 2 |
| 9095 | Kafka broker 3 |
| 8081 | Schema Registry |
| 8083 | Kafka Connect REST |

### 3.4 Network and Security

- **VM → Oracle RAC:** Port 1521 must be reachable (Security List / firewall)
- **SCAN hostname:** Must resolve from VM (add to `/etc/hosts` if needed)
- **SSH:** Port 22 for VM access

### 3.5 Oracle Database Requirements

- **ARCHIVELOG** mode enabled
- **XStream** enabled (`enable_goldengate_replication=TRUE`)
- **Supplemental logging** enabled for captured tables
- **XStream Out** outbound server configured

---

## 4. Detailed Step-by-Step Setup

### 4.1 Oracle Database Setup

1. **Connect to RAC as SYSDBA:**
   ```bash
   sqlplus sys/'<password>'@//racdb-scan.<vcn>.oraclevcn.com:1521/<service>.oraclevcn.com as sysdba
   ```

2. **Run scripts in order** (from `oracle-database/`):

   | Step | Script | Purpose |
   |------|--------|---------|
   | 1 | `01-create-sample-schema.sql` | ORDERMGMT schema and tables |
   | 2 | `02-enable-xstream.sql` | Enable XStream replication |
   | 3 | `03-supplemental-logging.sql` | Supplemental logging |
   | 4 | `04-create-xstream-users.sql` | XStream admin and connect users |
   | 5 | `05-load-sample-data.sql` | Sample data |
   | 6 | `06-create-outbound-ordermgmt.sql` | XStream Out outbound server |

3. **Get XStream service name** (for connector config):
   ```sql
   SELECT network_name FROM gv$SERVICES WHERE NAME LIKE '%XOUT%' AND ROWNUM=1;
   ```
   Example: `SYS$SYS.Q$_XOUT_65.DB0312.SUB01061249390.XSTRMCONNECTDB2.ORACLEVCN.COM`

### 4.2 VM Preparation

1. **Install Oracle Instant Client** (Basic + SQL*Plus):
   ```bash
   # Download from Oracle, extract to /opt/oracle/instantclient/instantclient_19_30
   # Ensure ojdbc8.jar, xstreams.jar, libclntsh.so* are present
   ```

2. **Clone or copy project** to VM:
   ```bash
   scp -r -i key.pem oracle-xstream-cdc-poc opc@<vm-ip>:/home/opc/
   ```

3. **Prepare environment:**
   ```bash
   cd ~/oracle-xstream-cdc-poc
   cp docker/.env.example docker/.env
   # Edit docker/.env: ORACLE_INSTANTCLIENT_PATH=/opt/oracle/instantclient/instantclient_19_30
   ```

### 4.3 Connector Configuration

1. **Create connector config:**
   ```bash
   cp xstream-connector/oracle-xstream-rac-docker.json.example xstream-connector/oracle-xstream-rac-docker.json
   ```

2. **Edit `xstream-connector/oracle-xstream-rac-docker.json`** – set these values:

   | Property | Value | Example |
   |----------|-------|---------|
   | `database.hostname` | RAC SCAN hostname | `racdb-scan.sub01061249390.xstrmconnectdb2.oraclevcn.com` |
   | `database.password` | c##cfltuser password | `your_password` |
   | `database.service.name` | XStream service (escape `$` as `\\$`) | `SYS\\$SYS.Q\\$_XOUT_65.DB0312.SUB01061249390.XSTRMCONNECTDB2.ORACLEVCN.COM` |

### 4.4 Start Docker Cluster

```bash
cd ~/oracle-xstream-cdc-poc
./docker/scripts/start-docker-cluster.sh
```

Wait for output: `Connect ready.`

### 4.5 Pre-create Topics

```bash
./docker/scripts/precreate-topics.sh
```

### 4.6 Deploy Connector

```bash
./docker/scripts/complete-migration-on-vm.sh
```

Or manually:
```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data @xstream-connector/oracle-xstream-rac-docker.json \
  http://localhost:8083/connectors
```

### 4.7 Set Replication Factor to 3 (Optional)

If topics were created with RF < 3:

```bash
./docker/scripts/increase-rf-to-3.sh
```

---

## 5. Migration Steps

### 5.1 From Single-Broker (Bare Metal) to 3-Broker Docker

| Step | Action |
|------|--------|
| 1 | Stop existing stack: `./docker/scripts/stop-docker-cluster.sh` (if running) |
| 2 | Copy project and Docker configs to VM |
| 3 | Set `ORACLE_INSTANTCLIENT_PATH` in `docker/.env` |
| 4 | Create `oracle-xstream-rac-docker.json` with credentials |
| 5 | Start Docker cluster: `./docker/scripts/start-docker-cluster.sh` |
| 6 | Pre-create topics: `./docker/scripts/precreate-topics.sh` |
| 7 | Deploy connector: `./docker/scripts/complete-migration-on-vm.sh` |

### 5.2 Data Preservation

- **Bare metal data** (`data/kafka/`) is not automatically migrated.
- Use **MirrorMaker 2** to replicate from old cluster to new cluster if preserving data.
- **Docker volumes** persist across `docker compose down`. Use `docker compose down -v` to remove.

### 5.3 Validation After Migration

1. Verify connector status: `curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq .`
2. Check topics: `docker exec kafka2 kafka-topics --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 --list | grep racdb`
3. Consume sample: `docker exec kafka2 kafka-console-consumer --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 --topic racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS --from-beginning --max-messages 3`

---

## 6. Testing & Verification

### 6.1 Connectivity Checks

```bash
# Connect REST API
curl -s http://localhost:8083/

# List connectors
curl -s http://localhost:8083/connectors

# Connector status
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq .

# Schema Registry
curl -s http://localhost:8081/
```

### 6.2 Kafka Topic Verification

```bash
# List CDC topics (use internal addresses to avoid connection warnings)
docker exec kafka2 kafka-topics --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 \
  --list | grep -E 'racdb|__orcl|__cflt'

# Describe topic
docker exec kafka2 kafka-topics --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 \
  --describe --topic racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS
```

### 6.3 End-to-End Smoke Test

1. **Insert test row in Oracle:**
   ```sql
   INSERT INTO ORDERMGMT.MTX_TRANSACTION_ITEMS (
     TRANSFER_ID, PARTY_ID, USER_TYPE, ENTRY_TYPE, ACCOUNT_ID,
     TRANSFER_DATE, TRANSACTION_TYPE, SECOND_PARTY, PROVIDER_ID,
     TXN_SEQUENCE_NUMBER, PAYMENT_TYPE_ID, SECOND_PARTY_PROVIDER_ID, UNIQUE_SEQ_NUMBER,
     REQUESTED_VALUE, APPROVED_VALUE, TRANSFER_STATUS, USER_NAME
   ) VALUES (
     'TRF-DEMO-001', 'P100', 'REG', 'DR', 'ACC-WALLET-001',
     SYSDATE, 'TRANS', 'P200', 1,
     9001, 1, 1, 'SEQ-DEMO-' || TO_CHAR(SYSDATE,'YYYYMMDDHH24MISS'),
     1500, 1500, 'COM', 'DemoPresenter'
   );
   COMMIT;
   ```

2. **Wait 10–30 seconds** (XStream latency)

3. **Consume from Kafka:**
   ```bash
   docker exec kafka2 kafka-console-consumer \
     --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 \
     --topic racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS \
     --from-beginning \
     --max-messages 5
   ```

4. **Expected:** JSON with `"op":"c"` (create/INSERT), `"after"` object with row data

---

## 7. Operational Runbook

### 7.1 Start Procedures

```bash
cd ~/oracle-xstream-cdc-poc
./docker/scripts/start-docker-cluster.sh
# Wait for "Connect ready"
./docker/scripts/precreate-topics.sh   # if topics don't exist
# Connector auto-starts if previously deployed
```

### 7.2 Stop Procedures

```bash
cd ~/oracle-xstream-cdc-poc
./docker/scripts/stop-docker-cluster.sh
# Or: docker compose -f docker/docker-compose.yml down
```

### 7.3 Restart Connector Only

```bash
curl -X POST http://localhost:8083/connectors/oracle-xstream-rac-connector/restart
```

### 7.4 Monitoring

| Check | Command |
|-------|---------|
| Container status | `docker ps --format '{{.Names}}: {{.Status}}' | grep -E 'kafka|connect|schema'` |
| Connector status | `curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq .` |
| Connect logs | `docker logs connect --tail 100` |
| Topic offsets | `docker exec -e KAFKA_OPTS= kafka2 kafka-get-offsets --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 --topic racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS --time -1` |

### 7.5 Failover Considerations

- **Kafka:** 3 brokers; cluster survives 1 broker failure
- **Connect:** Single instance; restart container on failure
- **Oracle:** RAC provides high availability

---

## 8. Troubleshooting

### 8.1 Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Connection reset by peer` on deploy | Connect not ready or OCI driver missing | Wait 60s after cluster start; ensure Oracle JARs in connector lib |
| `No suitable driver found for jdbc:oracle:oci` | Oracle JARs not in connector plugin lib | `connect-entrypoint.sh` copies ojdbc8.jar, xstreams.jar; verify `LD_LIBRARY_PATH` |
| `libnsl.so.1: cannot open shared object file` | Missing libnsl for OCI | Dockerfile installs libaio and creates libnsl.so.1 symlink |
| `Timeout expired while trying to create topic(s)` | Connect internal topics need RF 3, only 2 brokers up | Use `CONNECT_*_REPLICATION_FACTOR: 2` when kafka1 is down |
| `Connection to node 1/3 could not be established` | Using `localhost` from inside container | Use `kafka1:29092,kafka2:29092,kafka3:29092` for bootstrap |
| `ORA-12514` or connection fails | XStream service name changed | Re-query `gv$SERVICES`, update `database.service.name` |

### 8.2 Log Locations

| Component | Log Location |
|-----------|---------------|
| Connect | `docker logs connect` |
| Kafka broker | `docker logs kafka1` (or kafka2, kafka3) |
| Schema Registry | `docker logs schema-registry` |

### 8.3 Recovery Procedures

**Connector in FAILED state:**
```bash
# Check task error
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq .
# Restart
curl -X POST http://localhost:8083/connectors/oracle-xstream-rac-connector/restart
```

**Schema history topic missing:**
1. Delete connector
2. Create with `snapshot.mode: recovery`
3. Wait 90s
4. Update to `snapshot.mode: initial`, restart

**XStream Out service name changed:**
```sql
SELECT network_name FROM gv$SERVICES WHERE NAME LIKE '%XOUT%' AND ROWNUM=1;
```
Update connector config, escape `$` as `\\$`.

---

## 9. Appendices

### Appendix A: Configuration Reference

#### Connector Config (oracle-xstream-rac-docker.json)

```json
{
  "name": "oracle-xstream-rac-connector",
  "config": {
    "connector.class": "io.confluent.connect.oracle.xstream.cdc.OracleXStreamSourceConnector",
    "tasks.max": "1",
    "database.hostname": "racdb-scan.your-domain.oraclevcn.com",
    "database.port": "1521",
    "database.user": "c##cfltuser",
    "database.password": "YOUR_PASSWORD",
    "database.dbname": "DB0312",
    "database.service.name": "SYS\\$SYS.Q\\$_XOUT_XX.DB0312.YOUR_DOMAIN.ORACLEVCN.COM",
    "database.out.server.name": "xout",
    "database.pdb.name": "XSTRPDB",
    "confluent.topic.replication.factor": "3",
    "confluent.topic.bootstrap.servers": "kafka1:29092,kafka2:29092,kafka3:29092",
    "topic.prefix": "racdb",
    "table.include.list": "ORDERMGMT\\.(REGIONS|COUNTRIES|LOCATIONS|WAREHOUSES|EMPLOYEES|PRODUCT_CATEGORIES|PRODUCTS|CUSTOMERS|CONTACTS|ORDERS|ORDER_ITEMS|INVENTORIES|NOTES|MTX_TRANSACTION_ITEMS)|TPCC\\.(DISTRICT|CUSTOMER|HISTORY|ITEM|WAREHOUSE|STOCK|ORDERS|NEW_ORDER|ORDER_LINE)",
    "snapshot.mode": "initial",
    "heartbeat.interval.ms": "300000"
  }
}
```

#### Environment (.env)

```bash
ORACLE_INSTANTCLIENT_PATH=/opt/oracle/instantclient/instantclient_19_30
```

### Appendix B: Snapshot Modes

| Mode | Use Case |
|------|----------|
| `initial` | Full snapshot + streaming (first run) |
| `recovery` | Rebuild schema history when topic missing/corrupt |
| `no_data` | Streaming only; requires schema history from prior run |

### Appendix C: Quick Reference Commands

```bash
# Status summary
echo "=== Containers ===" && docker ps --format '{{.Names}}: {{.Status}}' | grep -E 'kafka|connect|schema'
echo "=== Connector ===" && curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq -r '.connector.state + " / task " + (.tasks[0].state // "N/A")'

# Consume CDC (use internal bootstrap)
docker exec kafka2 kafka-console-consumer \
  --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 \
  --topic racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS \
  --from-beginning --max-messages 5
```

### Appendix D: Change Event Format

```json
{
  "before": null,
  "after": {
    "TRANSFER_ID": "TRF001",
    "PARTY_ID": "P001",
    "REQUESTED_VALUE": "A+g=",
    ...
  },
  "source": {
    "connector": "Oracle XStream CDC",
    "schema": "ORDERMGMT",
    "table": "MTX_TRANSACTION_ITEMS",
    "snapshot": "true"
  },
  "op": "r",
  "ts_ms": 1773758751097
}
```

| `op` | Meaning |
|------|---------|
| `r` | Read (snapshot) |
| `c` | Create (INSERT) |
| `u` | Update |
| `d` | Delete |

---

## References

- [Confluent Oracle XStream CDC Connector – Overview](https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/overview.html#features)
- [Oracle XStream Documentation](https://docs.oracle.com/en/database/oracle/oracle-database/19/adxdb/change-data-capture.html)
- [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)
