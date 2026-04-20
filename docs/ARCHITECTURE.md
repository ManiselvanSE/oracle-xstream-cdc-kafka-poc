# Oracle RAC on OCI → Kafka XStream CDC Pipeline – Architecture

**Cloud provider:** Oracle Cloud Infrastructure (OCI). All infrastructure in this guide runs on OCI unless explicitly stated.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│  ORACLE CLOUD INFRASTRUCTURE (OCI)                                                           │
│                                                                                              │
│  ┌─────────────────────────────────────┐    ┌─────────────────────────────────────────────┐ │
│  │  OCI DB System (Managed)             │    │  OCI Compute VM (Connector Host)            │ │
│  │  ─────────────────────────────       │    │  ───────────────────────────────           │ │
│  │  • Oracle RAC 19c/21c               │    │  • Oracle Linux 9 / RHEL 9                 │ │
│  │  • XStream Out configured           │ LCR│  • Docker + Docker Compose                  │ │
│  │  • Supplemental logging enabled      │───►│  • Kafka Connect (Oracle XStream CDC)      │ │
│  │  • SCAN listener: racdb-scan...      │1521│  • 3-Broker Apache Kafka (KRaft)            │ │
│  │  • ORDERMGMT schema                  │    │  • Schema Registry                          │ │
│  └─────────────────────────────────────┘    │  • [Optional] Grafana, Prometheus           │ │
│              │                               └─────────────────────────────────────────────┘ │
│              │ sqlplus                                 │                                      │
│              ▼                                         │ racdb.ORDERMGMT.* topics             │
│  ┌─────────────────────────────────────┐              ▼                                      │
│  │  Oracle host (SQL*Plus, load scripts)│    ┌─────────────────────────────────────────────┐ │
│  │  • run-generate-heavy-cdc-load.sh   │    │  Kafka Topics                               │ │
│  │  • unlock-ordermgmt.sh             │    │  • racdb.ORDERMGMT.<TABLE>                   │ │
│  └─────────────────────────────────────┘    │  • Downstream consumers                      │ │
│                                              └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

Data flow: Oracle DML → Redo Logs → XStream Out (LCR) → Kafka Connect → Kafka Topics (JSON)
```

### Editable Diagram Description (Lucidchart / Draw.io)

Use this structure when recreating in Lucidchart or Draw.io:

| Component | Type | Location | Notes |
|-----------|------|----------|-------|
| **Oracle RAC** | OCI DB System | VCN, private subnet | Managed; XStream Out configured |
| **Connector VM** | OCI Compute | VCN, same or peered subnet | Docker host |
| **VCN** | Virtual Cloud Network | OCI | Single VCN or multiple with peering |
| **Subnet (private)** | Subnet | VCN | DB + VM in same VCN for low latency |
| **Security List** | Ingress/Egress | Subnet | Ports: 22 (SSH), 1521 (Oracle), 9092 (Kafka) |
| **Kafka** | Container | Connector VM | 3 brokers, KRaft |
| **Kafka Connect** | Container | Connector VM | Oracle XStream CDC Source connector |
| **Schema Registry** | Container | Connector VM | Optional |
| **Grafana / Prometheus** | Container | Connector VM | Optional monitoring |
| **Target consumers** | External / same VM | — | Consume from `racdb.*` topics |

---

## Environment Overview

| Item | Value |
|------|-------|
| **Cloud provider** | Oracle Cloud Infrastructure (OCI) |
| **Region** | e.g. `ap-mumbai-1`, `us-phoenix-1` (set per deployment) |
| **Connector VM shape** | VM.Standard.E4.Flex (4 OCPUs, 16 GB) or VM.Standard2.4 |
| **VM OS** | Oracle Linux 9 (recommended) or RHEL 9 |
| **Oracle RAC** | OCI DB System (Exadata or Standard), 19c or 21c |
| **Networking** | VCN with private subnet; security lists for 22, 1521, 9092 |
| **Kafka** | Apache Kafka 3.x (Confluent Platform 7.9) |

---

## Network Components

```
VCN (10.0.0.0/16)
├── Private Subnet (10.0.1.0/24)
│   ├── Oracle RAC nodes (SCAN: racdb-scan.<vcn>.oraclevcn.com)
│   └── Connector VM (private IP)
│
Security List (Ingress)
├── 22/tcp   – SSH
├── 1521/tcp – Oracle (from Connector VM subnet)
├── 9092/tcp – Kafka (from same subnet or consumer subnets)
├── 8083/tcp – Kafka Connect REST
└── 3000/tcp – Grafana (optional)
```

---

## Prerequisites Checklist

- [ ] OCI tenancy with compute and database access
- [ ] Oracle RAC 19c/21c on OCI DB System, ARCHIVELOG enabled
- [ ] XStream enabled in RAC (`enable_goldengate_replication=TRUE`)
- [ ] Connector VM with Docker, Oracle Instant Client
- [ ] Network path: Connector VM → RAC SCAN (1521)
- [ ] Confluent Oracle XStream CDC connector (license / trial)
