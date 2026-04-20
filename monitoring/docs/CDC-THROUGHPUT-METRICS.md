# Oracle XStream CDC Connector – Throughput Metrics

This guide explains how to monitor **how much throughput the Oracle XStream CDC connector processes** from the Oracle RAC database into Kafka.

---

## Overview

Throughput can be measured at two levels:

| Level | What it measures | Requires |
|-------|------------------|----------|
| **Connector** | Records polled from Oracle and written to Kafka per second | JMX Exporter on Kafka Connect |
| **Topic** | Messages written to CDC topics (racdb.*) per second | JMX Exporter on Kafka brokers |

---

## Option 1: Connector-Level Throughput (JMX on Connect)

When JMX Exporter is enabled on Kafka Connect, use these Prometheus queries:

### Records written to Kafka per second (connector throughput)

```promql
kafka_connect_source_task_metrics_source_record_write_rate{connector="oracle-xstream-rac-connector"}
```

### Records polled from Oracle per second

```promql
kafka_connect_source_task_metrics_source_record_poll_rate{connector="oracle-xstream-rac-connector"}
```

### Total records written (counter)

```promql
rate(kafka_connect_source_task_metrics_source_record_write_total{connector="oracle-xstream-rac-connector"}[5m])
```

### Total records polled (counter)

```promql
rate(kafka_connect_source_task_metrics_source_record_poll_total{connector="oracle-xstream-rac-connector"}[5m])
```

**In Grafana Explore:** Paste any query above, select Prometheus, click **Run query**.

---

## Option 2: Topic-Level Throughput (JMX on Kafka Brokers)

When JMX Exporter is enabled on Kafka brokers, filter by CDC topics:

### Messages per second into all CDC topics

```promql
sum(rate(kafka_server_brokertopicmetrics_messagesin_total{topic=~"racdb.*"}[5m]))
```

### Messages per second per CDC topic

```promql
rate(kafka_server_brokertopicmetrics_messagesin_total{topic=~"racdb.*"}[5m])
```

### Bytes per second into CDC topics

```promql
sum(rate(kafka_server_brokertopicmetrics_bytesin_total{topic=~"racdb.*"}[5m]))
```

**Note:** Topic names may include PDB prefix, e.g. `racdb.XSTRPDB.ORDERMGMT.MTX_TRANSACTION_ITEMS`. Use `racdb.*` to match all CDC topics.

---

## Option 3: Without JMX (Kafka Exporter Only)

Kafka Exporter does **not** expose per-topic messages/sec or connector throughput. You can still monitor:

- **Consumer lag:** `kafka_consumergroup_lag` – how far behind consumers are
- **Topic partitions:** `kafka_topic_partitions{topic=~"racdb.*"}` – partition count per CDC topic

To get **throughput**, you must enable JMX exporters (see [monitoring/README.md](../README.md)).

---

## Enabling JMX Exporters for Throughput

1. **Start the stack with monitoring:**
   ```bash
   ./docker/scripts/start-docker-cluster-with-monitoring.sh
   ```
   Or:
   ```bash
   docker compose -f docker/docker-compose.yml -f docker/docker-compose.monitoring.yml up -d
   ```

2. **Verify Prometheus targets:** http://&lt;vm-ip&gt;:9090/targets  
   - `kafka-broker` (3) and `kafka-connect` should be **UP**.

3. **Run the queries** in Prometheus or Grafana Explore.

---

## Grafana dashboards (repo)

Imported JSON dashboards include template variables:

- **`broker_job`**, **`connect_job`** — Prometheus scrape `job` labels (defaults: `kafka-broker`, `kafka-connect`). Change if your Prometheus uses different names.
- **`mtx_topic`** — Regex for CDC Kafka topic names. Default **MTX_TRANSACTION_ITEMS only** (`.*ORDERMGMT\.MTX_TRANSACTION_ITEMS`) for single-table pipeline tests; switch to **All ORDERMGMT.MTX\*** to include every MTX topic.

Recording rules: `cdc:kafka_broker_mtx_transaction_items_messagesin_per_second:sum5m` (items-only broker rate) in `prometheus/recording/cdc-golden.yml`.

## Grafana Dashboard Panel

Add a panel to your dashboard:

- **Title:** Oracle XStream CDC Throughput
- **Query:** `sum(rate(kafka_server_brokertopicmetrics_messagesin_total{topic=~"racdb.*"}[5m]))`
- **Unit:** short (messages/sec) or `bytes/sec` for bytes
- **Visualization:** Time series

For connector-level metrics:

- **Query:** `kafka_connect_source_task_metrics_source_record_write_rate{connector="oracle-xstream-rac-connector"}`
- **Unit:** short (records/sec)

---

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| No data for connector metrics | JMX not enabled on Connect | Base `docker-compose.yml` enables Connect JMX; rebuild/recreate containers after pulling changes |
| No data for topic metrics | JMX not enabled on Kafka | Base `docker-compose.yml` enables broker JMX; rebuild/recreate containers |
| Metric names differ | Kafka/Connect version | Run `{__name__=~"kafka_connect.*"}` in Prometheus to list available metrics |
| Empty for racdb.* | No CDC topics yet | Insert data in Oracle, wait for connector to stream |
