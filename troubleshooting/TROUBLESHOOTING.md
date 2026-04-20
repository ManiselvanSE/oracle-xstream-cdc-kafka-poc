# Oracle CDC XStream Connector – Troubleshooting (Docker)

## TPCC Kafka topics exist but offset stays 0 (imports / no messages)

**Symptom:** `racdb.XSTRPDB.TPCC.*` topics exist, `kafka-get-offsets` shows `:0`, or imports completed but nothing arrives.

**Typical causes:**

1. **`snapshot.mode=no_data`** — existing table data is **not** snapshotted; only **new** changes after streaming starts are produced. Imports alone do not fill topics unless you use **`snapshot.mode=initial`** (and accept a full snapshot) or generate **new** DML after CDC is wired.
2. **Oracle** — supplemental logging, **`GRANT SELECT`** to `C##CFLTUSER`, and **XStream rules** for all `TPCC` tables (`fix-tpcc-xstream-oracle.sh`, `verify-tpcc-cdc-prereqs.sql`).
3. **Connector** — `table.include.list` includes `TPCC\.(DISTRICT|…|ORDER_LINE)`; task **RUNNING** (`validate-tpcc-cdc-pipeline.sh`).
4. **Bulk tools** — some import paths minimize redo; confirm with controlled DML.

**Fix / verify:** Run **`oracle-database/run-tpcc-cdc-smoke-test.sh`** (after setting `TPCC_PASSWORD`) to touch all nine `TPCC` tables with small transactions, then re-check offsets on the Connect VM. See **`docs/HAMMERDB-RAC-LOAD.md` §8.1–8.2**.

**Backfill imported rows:** On the Connect VM, **`./docker/scripts/connector-apply-initial-snapshot.sh`** sets `snapshot.mode=initial` and restarts. If offsets already block a snapshot, use **`CONFIRM=yes ./docker/scripts/connector-recreate-full-snapshot.sh`** after setting **`snapshot.mode` to `initial`** in your connector JSON (see **`docs/HAMMERDB-RAC-LOAD.md` §8.3**).

**Docker CLI note:** Use `docker exec -e KAFKA_OPTS= ...` for `kafka-topics` / `kafka-get-offsets` inside broker containers (JMX port conflict). See **`docs/STATUS-CHECK.md` §2.0**.

---

## ORDERMGMT CDC worked before; TPCC topics stay empty

**Why:** **ORDERMGMT** and **TPCC** are different schemas. The PoC onboarded **ORDERMGMT** first (`ug-prod-onboard-xstream.*`, supplemental logging, XStream rules, connector regex). **TPCC** (HammerDB) requires the **same class of Oracle work** again — it is **not** included automatically when ORDERMGMT works. Kafka/Connect config is usually fine once **`table.include.list`** contains the **`TPCC\.(DISTRICT|…|ORDER_LINE)`** pattern and **`database.pdb.name`** is **`XSTRPDB`**.

**Oracle (required):**

1. Run **`oracle-database/fix-tpcc-xstream-oracle.sh`** with **`ORACLE_PWD`** for **`c##xstrmadmin`** and **`ORACLE_CONN`** = TNS alias to **PDB service** (e.g. `xstrpdb` / `DB0312_xstrpdb` — not a CDB-only service).  
2. Run **`verify-tpcc-cdc-prereqs.sql`** in **`XSTRPDB`** — expect supplemental log rows, **`GRANT SELECT`** to **`C##CFLTUSER`**, and **`DBA_XSTREAM_RULES`** for all nine **`TPCC`** tables.

**Connector (verify / sync):**

1. Live config must include TPCC:  
   `curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/config | jq -r '.["table.include.list"]' | grep -o TPCC || echo MISSING`  
2. Merge from template if needed: **`./docker/scripts/connector-ensure-tpcc-onboard.sh`** or copy regex from **`xstream-connector/oracle-xstream-rac-docker.json.example`**, then **`./docker/scripts/onboard-tables-deploy-on-vm.sh`** (or PUT + restart).  
3. **SMTs** in the example JSON only match **`ORDERMGMT.MTX_TRANSACTION_*`** — they do **not** strip **TPCC** records.

**Application:** HammerDB must use the **PDB** service in **`tnsnames.ora`** so workload hits **`XSTRPDB`**, not **`CDB$ROOT`** (`docs/HAMMERDB-RAC-LOAD.md`).

**If TPCC data existed before rules were added and you need it in Kafka:** **`snapshot.mode=initial`** plus **`CONFIRM=yes ./docker/scripts/connector-recreate-full-snapshot.sh`** (see **`docs/HAMMERDB-RAC-LOAD.md` §8.3**) — or rely on **`no_data`** and **new** DML only after Oracle is fixed.

---

## Only REGIONS Topic (Other Tables Not Created)

**Symptom:** Only `racdb.XSTRPDB.ORDERMGMT.REGIONS` topic exists; other tables have no topics.

**Fix:** Add `database.pdb.name` to connector config:
```json
"database.pdb.name": "XSTRPDB",
```

Use regex for `table.include.list`: `ORDERMGMT\\.(REGIONS|COUNTRIES|LOCATIONS|...)`

---

## Connection Reset on Deploy

**Symptom:** `curl -X POST ... http://localhost:8083/connectors` returns "Connection reset by peer".

**Causes:**
1. Connect not fully ready – wait 60+ seconds after cluster start
2. Oracle OCI driver missing – ensure `ojdbc8.jar` and `xstreams.jar` in connector plugin lib (connect-entrypoint.sh copies from Instant Client)
3. `libnsl.so.1` missing – Dockerfile creates symlink; rebuild Connect image if needed

---

## No Suitable Driver (jdbc:oracle:oci)

**Symptom:** "No suitable driver found for jdbc:oracle:oci"

**Fix:** Oracle JARs must be in connector plugin lib. The `connect-entrypoint.sh` copies `ojdbc8.jar` and `xstreams.jar` from mounted Instant Client. Verify:
```bash
docker exec connect ls /usr/share/confluent-hub-components/confluentinc-kafka-connect-oracle-xstream-cdc-source/lib/ | grep -E 'ojdbc|xstreams'
```

---

## libnsl.so.1 Cannot Open Shared Object

**Symptom:** `UnsatisfiedLinkError: libnsl.so.1: cannot open shared object file`

**Fix:** Rebuild Connect image – Dockerfile installs libaio and creates libnsl.so.1 symlink.

---

## Connect Timeout Creating Topics

**Symptom:** "Timeout expired while trying to create topic(s)" for `_connect-offsets`.

**Cause:** Connect uses replication factor 3 for internal topics; only 2 brokers may be up (e.g. kafka1 down).

**Fix:** `docker-compose.yml` uses `CONNECT_*_REPLICATION_FACTOR: 2` for compatibility. Ensure at least 2 brokers are healthy.

---

## Connection to Node 1/3 Could Not Be Established

**Symptom:** Warnings when running `kafka-topics` or `kafka-console-consumer` with `localhost:9094`.

**Cause:** From inside a container, `localhost` refers to the container itself. Brokers advertise `localhost:9092`, etc., which are unreachable from other containers.

**Fix:** Use internal bootstrap: `kafka1:29092,kafka2:29092,kafka3:29092`
```bash
docker exec kafka2 kafka-console-consumer \
  --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 \
  --topic racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS --from-beginning --max-messages 5
```

---

## XStream Service Name Changes

**Symptom:** ORA-12514 or connector fails after dropping/recreating outbound.

**Fix:** Get current service name:
```sql
SELECT network_name FROM gv$SERVICES WHERE NAME LIKE '%XOUT%' AND ROWNUM=1;
```
Update `database.service.name` in connector config. Escape `$` as `\\$`.

---

## Schema History Topic Missing

**Symptom:** "The db history topic is missing"

**Fix:**
1. Delete connector
2. Create with `snapshot.mode: recovery`
3. Wait 90s
4. Update to `snapshot.mode: initial`, restart

---

## Capture Process ABORTED

**Symptom:** "The capture process 'CONFLUENT_XOUT1' is in an 'ABORTED' status"

**Fix:** Stop and restart capture (run on Oracle as SYSDBA):
```sql
BEGIN DBMS_CAPTURE_ADM.STOP_CAPTURE(capture_name => 'CONFLUENT_XOUT1'); END;
/
-- Wait a few seconds
BEGIN DBMS_CAPTURE_ADM.START_CAPTURE(capture_name => 'CONFLUENT_XOUT1'); END;
/
```

---

## Connector in FAILED State

**Fix:** Restart connector:
```bash
curl -X POST http://localhost:8083/connectors/oracle-xstream-rac-connector/restart
```

Check logs: `docker logs connect --tail 100`

---

## Generate CDC Throughput for Grafana

**Goal:** Produce visible throughput in Grafana "Oracle XStream Connector Throughput" and "CDC Throughput" panels.

### Light load (~200 rows, 30 sec)
**Script:** `oracle-database/15-generate-cdc-throughput.sql`

### Heavy load (10,000+ rows, high throughput)
**Script:** `oracle-database/16-generate-heavy-cdc-load.sql` – inserts as fast as possible for sustained high connector throughput.

```bash
cd oracle-database
export ORDMGMT_PWD='YourP@ssw0rd123'   # if password contains @

# Default: 10,000 rows
./run-generate-heavy-cdc-load.sh

# Heavier: 50,000 rows
./run-generate-heavy-cdc-load.sh 50000
```

**Run (from host with Oracle client):**
```bash
sqlplus ordermgmt/"<password>"@//<rac-scan>:1521/<service> @oracle-database/15-generate-cdc-throughput.sql
```

**Example (OCI RAC) – use run script (handles TNS and password with @):**
```bash
cd oracle-database
export ORDMGMT_PWD='YourP@ssw0rd123'
./run-generate-cdc-throughput.sh      # light
./run-generate-heavy-cdc-load.sh      # heavy (10K rows)
./run-generate-heavy-cdc-load.sh 50000 # heavier (50K rows)
```

**If ORA-28000 (account locked):** Unlock as SYSDBA: `ALTER USER ordermgmt ACCOUNT UNLOCK;`

**Prerequisites:** Sample data loaded (`05-load-sample-data.sql`), connector RUNNING. Watch Grafana 10–30 seconds after the script completes.

---

## Grafana Connector Throughput Shows "No Data"

**Symptom:** Oracle XStream Connector Throughput panel is empty; Targets Up shows `kafka-connect: 0`.

**Cause:** Prometheus cannot scrape Kafka Connect's JMX exporter. Connector metrics come from Connect JMX.

**Verify Connect JMX:**
```bash
# From host - JMX exporter exposes HTTP metrics on 9994
curl -s http://localhost:9994/metrics | grep -E "kafka_connect|up"

# From inside Prometheus container
docker exec prometheus wget -qO- http://connect:9991/metrics | head -30
```

**If curl to 9994 fails:**
1. Check Connect logs for JMX agent errors: `docker logs connect 2>&1 | head -50`
2. Ensure Connect was started with monitoring: `docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d`
3. Verify JMX config mount: `docker exec connect ls -la /etc/jmx-exporter/`
4. Restart Connect: `docker restart connect`

**If Connect JMX works but connector metric is missing:** The connector must be RUNNING and actively streaming. Check: `curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq .`

---

## Snapshot Modes Reference

| Mode | Use |
|------|-----|
| `initial` | Full snapshot + streaming (first run) |
| `recovery` | Rebuild schema history when topic missing/corrupt |
| `no_data` | Streaming only; requires schema history from prior run |
