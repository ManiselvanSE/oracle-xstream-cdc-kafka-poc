# System Flow: Oracle CDC + HammerDB Load Testing

## End-to-end flow

```text
HammerDB -> Oracle OLTP Transactions -> Oracle Redo Logs -> XStream CDC -> Kafka Connect -> Kafka Topics -> Consumers
```

## Simple architecture

```text
+-----------+    +-------------+    +--------------+    +--------------+    +-------------+
| HammerDB  | -> | Oracle RAC  | -> | XStream CDC  | -> | Kafka Connect| -> | Kafka Topics|
+-----------+    +-------------+    +--------------+    +--------------+    +-------------+
                                                                          |
                                                                          v
                                                                  +---------------+
                                                                  | Consumers +   |
                                                                  | Monitoring    |
                                                                  +---------------+
```

## Step-by-step

1. HammerDB creates high OLTP traffic on Oracle tables.
2. Oracle writes committed changes to redo logs.
3. XStream reads redo and converts changes to CDC events.
4. Kafka Connect reads the XStream stream and publishes to Kafka topics.
5. Consumers read and process CDC events.
6. Monitoring tracks throughput, lag, and end-to-end latency.
