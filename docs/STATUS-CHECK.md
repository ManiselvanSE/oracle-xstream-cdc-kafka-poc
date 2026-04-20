# Step-by-Step Status Check Guide

How to verify the Oracle XStream CDC pipeline and all components (Kafka, Connect, Prometheus, Grafana).

---

## Check Status from Your Mac

**`curl localhost:8083` returns nothing from Mac** because Kafka Connect runs on the OCI VM, not locally.

**Use either:**

```bash
# Option 1: One command (SSH to VM and run checks)
./status <vm-ip>
# Example: ./status 74.225.27.158

# Option 2: With custom SSH key
SSH_KEY=/path/to/key.pem ./status 74.225.27.158

# Option 3: Create .status-config once (copy from .status-config.example)
# Set VM_IP and SSH_KEY, then: ./status
```

### Scripts missing on the VM (`No such file or directory`)

New files (e.g. `docker/scripts/check-tpcc-kafka-offsets.sh`, `oracle-database/run-tpcc-cdc-sample-inserts.sh`) exist only where you **updated the repo**. On each host (**Connect VM**, **HammerDB host**, etc.) run **`git pull`** inside `~/oracle-xstream-cdc-poc`, or **rsync** / **scp** the project from your laptop:

```bash
# From your Mac (adjust host and path to repo)
rsync -avz --delete ~/path/to/oracle-xstream-cdc-poc/ opc@<connect-vm-ip>:~/oracle-xstream-cdc-poc/
```

If `validate-tpcc-cdc-pipeline.sh` still prints only **one** TPCC topic in section 4, the VM copy is **older** than the version that loops all nine topics — pull/sync again.

---

## Bring Everything Up (One Command)

If the stack is down, run this **on the OCI VM**:

```bash
cd ~/oracle-xstream-cdc-poc
./docker/scripts/bring-up.sh
```

This will: stop any existing containers, start Kafka + Connect + Schema Registry + Prometheus + Grafana, pre-create topics, and deploy/restart the connector.

---

## Quick Reference

| Component | Check | URL / Command |
|-----------|-------|---------------|
| **Connector** | Status & tasks | `curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status \| jq .` |
| **Kafka** | Brokers reachable | `kafka-broker-api-versions --bootstrap-server localhost:9092 \| head -3` |
| **Kafka Connect** | REST API | `curl -s http://localhost:8083/` |
| **Schema Registry** | REST API | `curl -s http://localhost:8081/` |
| **Prometheus** | Targets & UI | http://localhost:9090/targets |
| **Grafana** | Dashboards | http://localhost:3000 |
| **Kafka Exporter** | Metrics | `curl -s http://localhost:9308/metrics \| head -20` |

---

## 1. Connector Status

### 1.1 Get Connector Status

```bash
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq .
```

**Expected (healthy):**
```json
{
  "name": "oracle-xstream-rac-connector",
  "connector": { "state": "RUNNING", "worker_id": "connect:8083" },
  "tasks": [{ "id": 0, "state": "RUNNING", "worker_id": "connect:8083" }]
}
```

**Checks:**
- `connector.state` = `RUNNING`
- `tasks[].state` = `RUNNING`

**If FAILED:** Inspect `trace` in the response or Connect logs:
```bash
# Docker
docker logs connect --tail 100

# Standalone
tail -100 /path/to/connect.log
```

### 1.2 Restart Connector (if needed)

```bash
curl -X POST http://localhost:8083/connectors/oracle-xstream-rac-connector/restart
```

### 1.3 List All Connectors

```bash
curl -s http://localhost:8083/connectors
```

Expected: `["oracle-xstream-rac-connector"]`

### 1.4 Get Connector Config

```bash
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/config | jq .
```

---

## 2. Kafka Status

### 2.0 Docker: `KAFKA_OPTS` and Kafka CLI tools

Broker containers set `KAFKA_OPTS` with the JMX Prometheus javaagent. If you `docker exec` and run JVM-based tools (`kafka-topics`, `kafka-console-consumer`, `kafka-get-offsets`, etc.) **without** clearing that env, the tool’s JVM loads the same agent and tries to bind the metrics port (e.g. **9990**) again → `java.net.BindException: Address already in use` and a stack trace through `io.prometheus.jmx`.

**Offsets (Kafka 3.7+ / Confluent 7.9):** `kafka.tools.GetOffsetShell` was removed. Use `kafka-get-offsets` instead, for example:

```bash
docker exec -e KAFKA_OPTS= kafka1 kafka-get-offsets \
  --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 \
  --topic racdb.XSTRPDB.TPCC.DISTRICT --time -1
```

**Fix:** pass an empty `KAFKA_OPTS` for CLI-only commands:

```bash
docker exec -e KAFKA_OPTS= kafka2 kafka-topics --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 ...
```

### 2.1 Broker Reachability

```bash
# Docker
docker exec -e KAFKA_OPTS= kafka1 kafka-broker-api-versions --bootstrap-server localhost:9092 | head -5

# Standalone
/opt/confluent/confluent/bin/kafka-broker-api-versions --bootstrap-server localhost:9092 | head -5
```

**Expected:** Broker ID and API versions listed. No "Connection refused".

### 2.2 List CDC Topics

```bash
# Docker (3-broker)
docker exec -e KAFKA_OPTS= kafka2 kafka-topics --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 --list | grep racdb

# Docker (single broker)
docker exec -e KAFKA_OPTS= kafka1 kafka-topics --bootstrap-server kafka1:29092 --list | grep racdb

# Standalone
kafka-topics --bootstrap-server localhost:9092 --list | grep racdb
```

Expected: Topics like `racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS`, `racdb.ORDERMGMT.MBK_BANK_DETAILS`, etc.

### 2.3 Onboard New Tables (Auto Topics + Connector)

After running `ug-prod-ordermgmt-drop-and-create.sql` and `ug-prod-onboard-xstream.sh` on the DB, run **on the VM**:

```bash
./docker/scripts/onboard-tables-deploy-on-vm.sh
```

This pre-creates topics, syncs `table.include.list`, and restarts the connector. Then populate tables for CDC:

```bash
cd oracle-database && ./run-generate-ug-prod-cdc-load.sh
```

### 2.4 Verify Messages in a Topic

```bash
# Docker
docker exec -e KAFKA_OPTS= kafka1 kafka-console-consumer --bootstrap-server kafka1:29092 \
  --topic racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS --partition 0 --offset 0 --max-messages 3 --timeout-ms 5000

# Standalone
kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS --partition 0 --offset 0 --max-messages 3 --timeout-ms 5000
```

---

## 3. Kafka Connect Status

### 3.1 Connect REST API

```bash
curl -s http://localhost:8083/
```

**Expected:**
```json
{
  "version": "7.9.0-ce",
  "commit": "...",
  "kafka_cluster_id": "..."
}
```

If this fails, do **not** deploy the connector until Connect is ready.

### 3.2 List Connect Workers

```bash
curl -s http://localhost:8083/connector-plugins | jq '.[].class' | grep -i oracle
```

Expected: `"io.confluent.connect.oracle.xstream.cdc.OracleXStreamSourceConnector"`

---

## 4. Schema Registry Status

```bash
curl -s http://localhost:8081/
```

**Expected:** JSON with `schema_registry` key.

---

## 5. Prometheus Status

### 5.1 Access Prometheus UI

1. Open **http://localhost:9090** (or `http://<vm-ip>:9090` from a remote host).
2. Use **Status → Targets** to see all scrape targets.

### 5.2 Check Targets via API

```bash
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

**Expected:** `health: "up"` for:
- `prometheus`
- `kafka-broker` (3 instances)
- `kafka-connect`
- `schema-registry`
- `kafka-exporter`

### 5.3 Sample PromQL Queries (in Prometheus → Graph)

| Query | Purpose |
|-------|---------|
| `up{job="kafka-broker"}` | Kafka broker scrape health |
| `up{job="kafka-connect"}` | Connect scrape health |
| `sum(rate(kafka_server_brokertopicmetrics_messagesin_total{topic=~"racdb.*"}[5m]))` | CDC throughput (messages/sec) |
| `kafka_consumergroup_lag{job="kafka-exporter"}` | Consumer lag |

---

## 6. Grafana Status

### 6.1 Access Grafana

1. Open **http://localhost:3000** (or `http://<vm-ip>:3000`).
2. Login: **admin** / **admin** (change on first login).

### 6.2 Verify Datasource

1. Go to **Connections** (or **Configuration**) → **Data sources**.
2. Ensure **Prometheus** is configured with URL `http://prometheus:9090` (Docker) or `http://localhost:9090` (standalone).
3. Click **Save & test** — should show "Data source is working".

### 6.3 Open the CDC Dashboard

1. Go to **Dashboards**.
2. Open **"Oracle XStream CDC - Kafka Overview"** (or import from `monitoring/grafana/dashboards/kafka-overview.json` if not provisioned).

### 6.4 Key Panels to Check

| Panel | What to look for |
|-------|------------------|
| **Targets Up** | All bars at 1 (up) |
| **Oracle XStream CDC Throughput** | Non-zero when DML is happening |
| **Consumer Group Lag** | Should be low or zero for healthy consumers |
| **JVM Heap Memory** | Should not be near 100% |
| **CPU Usage** | Spikes during snapshot, steady during streaming |

### 6.5 Remote Access via SSH Port Forwarding

From your local machine:

```bash
ssh -i key.pem -L 3000:localhost:3000 -L 8083:localhost:8083 -L 9090:localhost:9090 opc@<vm-ip>
```

Then open:
- http://localhost:3000 (Grafana)
- http://localhost:9090 (Prometheus)
- http://localhost:8083/connectors (Connect)

---

## 7. Kafka Exporter Status

Kafka Exporter exposes topic and consumer-group metrics for Prometheus.

```bash
# Topic partitions
curl -s http://localhost:9308/metrics | grep kafka_topic_partitions

# Consumer group lag
curl -s http://localhost:9308/metrics | grep kafka_consumergroup_lag
```

**Expected:** Metrics in Prometheus exposition format.

---

## 8. Docker Container Status (if using Docker)

### 8.1 List All Containers

```bash
docker ps --format '{{.Names}}: {{.Status}}' | grep -E 'kafka|connect|schema|prometheus|grafana|exporter'
```

**Expected:** All relevant containers in "Up" state.

### 8.2 Check Specific Service Logs

```bash
# Connector / Connect logs
docker logs connect --tail 50

# Kafka broker
docker logs kafka1 --tail 30

# Prometheus
docker logs prometheus --tail 20

# Grafana
docker logs grafana --tail 20
```

---

## 9. Complete Status Check Script (Docker)

Run from project root:

```bash
#!/bin/bash
echo "=== Connector Status ==="
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq '.connector.state, .tasks[].state'

echo ""
echo "=== Kafka ==="
docker exec -e KAFKA_OPTS= kafka1 kafka-broker-api-versions --bootstrap-server localhost:9092 2>/dev/null | head -1 || echo "Kafka not reachable"

echo ""
echo "=== Connect ==="
curl -s http://localhost:8083/ | jq -r '.version // "Connect not reachable"'

echo ""
echo "=== Prometheus Targets ==="
curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets[] | "\(.labels.job): \(.health)"' 2>/dev/null || echo "Prometheus not reachable"

echo ""
echo "=== URLs ==="
echo "Grafana:    http://localhost:3000"
echo "Prometheus: http://localhost:9090"
echo "Connect:    http://localhost:8083"
```

---

## 10. Troubleshooting Summary

| Issue | Where to check |
|-------|----------------|
| Connector FAILED | `curl .../status`, `docker logs connect` |
| Connect not ready | Wait 60–120s after cluster start; check `curl http://localhost:8083/` |
| No metrics in Grafana | Prometheus targets (http://localhost:9090/targets), Grafana datasource |
| Prometheus targets DOWN | JMX exporter ports (9990, 9991, 9992), Kafka Exporter 9308 |
| No CDC messages | Oracle XStream Out, connector config (`database.service.name`, `database.hostname`), DML committed |

---

## Related Docs

- [EXECUTION-GUIDE.md](EXECUTION-GUIDE.md) – Part 4: Validation
- [monitoring/docs/GRAFANA-DASHBOARD-README.md](../monitoring/docs/GRAFANA-DASHBOARD-README.md) – Grafana setup and panels
- [monitoring/README.md](../monitoring/README.md) – Monitoring stack overview
- [troubleshooting/TROUBLESHOOTING.md](../troubleshooting/TROUBLESHOOTING.md) – Common errors and fixes
