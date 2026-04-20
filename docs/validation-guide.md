# Validation Guide

## 1) Oracle load validation

Check redo and session activity during HammerDB run:

```sql
@oracle-database/hammerdb-redo-and-size-report.sql
@oracle-database/hammerdb-rac-monitoring.sql
```

## 2) CDC capture validation

```bash
export ORACLE_SYSDBA_CONN='sys/<pwd>@//<host>:1521/<service> AS SYSDBA'
./oracle-database/run-08-verify-xstream-outbound.sh
```

Expected: outbound, capture, and apply in enabled/running state.

## 3) Kafka flow validation

```bash
./docker/scripts/verify-cdc-stack.sh
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq .
```

Expected: connector and task are `RUNNING`, topic offsets are increasing.

## 4) Throughput validation

- Use Prometheus/Grafana metrics:
  - broker messages in/sec
  - broker bytes in/sec
  - connect source write rate

## 5) Latency validation

- Track connector lag metric and end-to-end timestamp delta (source commit vs consumer receive).
- Target profile: around ~200 ms during peak.

## 6) End-to-end consistency check

1. Write known test records.
2. Confirm they appear in Kafka topic.
3. Validate key fields match source row values.
