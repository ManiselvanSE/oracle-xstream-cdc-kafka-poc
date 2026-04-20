# Migration: Single Broker → 3-Broker Docker Cluster

This guide covers migrating to the 3-broker Docker-based cluster.

---

## Overview

| Aspect | Before | After (Docker) |
|--------|--------|----------------|
| Brokers | 1 | 3 |
| Replication factor | 1 | 3 |
| Schema Registry | localhost:8081 | localhost:8081 |
| Connect | Standalone | Distributed |
| Data | `data/kafka/` | Docker volumes |

---

## Fresh Start

1. **Install Docker** (if not already)
   ```bash
   sudo ./docker/scripts/install-docker.sh
   ```

2. **Prepare connector config**
   ```bash
   cp xstream-connector/oracle-xstream-rac-docker.json.example xstream-connector/oracle-xstream-rac-docker.json
   # Edit: database.password, database.service.name, database.hostname
   ```

3. **Set Oracle Instant Client path**
   ```bash
   cp docker/.env.example docker/.env
   # Edit: ORACLE_INSTANTCLIENT_PATH=/opt/oracle/instantclient/instantclient_19_30
   ```

4. **Start Docker cluster**
   ```bash
   ./docker/scripts/start-docker-cluster.sh
   ```

5. **Pre-create topics**
   ```bash
   ./docker/scripts/precreate-topics.sh
   ```

6. **Deploy connector**
   ```bash
   ./docker/scripts/complete-migration-on-vm.sh
   ```

7. **Verify**
   ```bash
   curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq .
   ```

---

## Configuration Mapping

| Config | Docker |
|--------|--------|
| Bootstrap (from host) | localhost:9092, localhost:9094, localhost:9095 |
| Connector bootstrap | kafka1:29092,kafka2:29092,kafka3:29092 |
| Topic replication | 3 |
| Connector deploy | REST API (complete-migration-on-vm.sh) |

---

## Data Preservation

- **Docker volumes** persist across `docker compose down`. To remove: `docker compose down -v`.
- **Connect offsets** are stored in Kafka topic `_connect-offsets`.
