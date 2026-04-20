# Docker: 3-Broker Kafka Cluster

Docker-based setup with **3 Kafka brokers** (KRaft), Schema Registry, and Kafka Connect with Oracle XStream CDC connector.

## Prerequisites

- Docker and Docker Compose
- Oracle Instant Client on host (for XStream connector native libs)
- Connector config with database credentials

## Quick Start

```bash
# 1. From project root
cp docker/.env.example docker/.env
# Edit docker/.env: set ORACLE_INSTANTCLIENT_PATH

# 2. Copy and edit connector config
cp xstream-connector/oracle-xstream-rac-docker.json.example xstream-connector/oracle-xstream-rac-docker.json
# Edit oracle-xstream-rac-docker.json: database.password, database.service.name, database.hostname

# 3. Start cluster
./docker/scripts/start-docker-cluster.sh

# 4. Pre-create topics
./docker/scripts/precreate-topics.sh

# 5. Deploy connector
./docker/scripts/deploy-connector.sh
```

## Ports

| Service | Port | URL |
|---------|------|-----|
| Kafka broker 1 | 9092 | localhost:9092 |
| Kafka broker 2 | 9094 | localhost:9094 |
| Kafka broker 3 | 9095 | localhost:9095 |
| Schema Registry | 8081 | http://localhost:8081 |
| Connect | 8083 | http://localhost:8083 |

## Scripts

| Script | Purpose |
|--------|---------|
| `start-docker-cluster.sh` | Start all containers |
| `stop-docker-cluster.sh` | Stop all containers |
| `precreate-topics.sh` | Create CDC topics with replication factor 3 |
| `deploy-connector.sh` | Deploy Oracle XStream connector via REST |
| `complete-migration-on-vm.sh` | Deploy connector (run on VM after cluster is up) |
| `increase-rf-to-3.sh` | Increase CDC topic replication factor to 3 |
| `install-docker.sh` | Install Docker on Oracle Linux 9 (`sudo ./docker/scripts/install-docker.sh`) |

## Migration

See [MIGRATION.md](MIGRATION.md) for migrating from the single-broker bare metal setup.

## Data Volumes

- `kafka1-data`, `kafka2-data`, `kafka3-data` – Kafka log data
- Data persists across `docker compose down`
- Remove with: `docker compose -f docker/docker-compose.yml down -v`
