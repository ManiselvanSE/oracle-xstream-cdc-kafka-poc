# Demo Script: End-to-End CDC Flow (MTX_TRANSACTION_ITEMS)

A step-by-step script for live demonstrations showing data flow from **Oracle** → **XStream** → **Kafka** → **Consumer**.

**Prerequisites:** Oracle RAC configured with XStream, Docker cluster running, connector deployed.

---

## Step 1: Verify the Source Table

**What to say:** *"We'll start by verifying our source table in Oracle."*

### 1a. View table structure

```sql
-- Connect as ordermgmt (from VM or host with SQL*Plus)
-- sqlplus ordermgmt/<password>@//racdb-scan...:1521/XSTRPDB... 

DESC ORDERMGMT.MTX_TRANSACTION_ITEMS;
```

**Expected:** List of columns (UNIQUE_SEQ_NUMBER, TRANSFER_ID, PARTY_ID, etc.)

### 1b. Query table before insert (baseline)

```sql
SQL> select count(*) from ORDERMGMT.MTX_TRANSACTION_ITEMS;

  COUNT(*)
----------
         6

SQL> 

SELECT UNIQUE_SEQ_NUMBER, TRANSFER_ID, PARTY_ID, REQUESTED_VALUE, APPROVED_VALUE, TRANSFER_STATUS
FROM ORDERMGMT.MTX_TRANSACTION_ITEMS
ORDER BY TRANSFER_DATE DESC
FETCH FIRST 5 ROWS ONLY;
```

**Expected:** Current row count and latest rows. Note the count for comparison after insert.

---

## Step 2: Insert a Test Record

**What to say:** *"Now we'll insert a test record. This simulates a real transaction."*

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

**Alternative – use script:** `@oracle-database/14-insert-mtx-transaction-items.sql`

---

## Step 3: Verify Oracle Change

**What to say:** *"Let's confirm the record exists in Oracle."*

```sql
SELECT UNIQUE_SEQ_NUMBER, TRANSFER_ID, PARTY_ID, REQUESTED_VALUE, APPROVED_VALUE, TRANSFER_STATUS, USER_NAME
FROM ORDERMGMT.MTX_TRANSACTION_ITEMS
WHERE TRANSFER_ID = 'TRF-DEMO-001';
```

**Expected:** One row with TRANSFER_ID='TRF-DEMO-001', REQUESTED_VALUE=1500, USER_NAME='DemoPresenter'

---

## Step 4: Connector / XStream Processing

**What to say:** *"Behind the scenes, Oracle XStream captures the change from the redo log and the Kafka connector receives it. Let's verify the connector is running."*

### How it works (brief explanation)

1. **Oracle redo log** – The INSERT is written to redo.
2. **XStream Capture** (`CONFLUENT_XOUT1`) – Reads redo, produces Logical Change Records (LCRs).
3. **XStream Connector** – Subscribes to XStream Out, receives LCRs, converts to Debezium JSON, produces to Kafka.

### Check connector status

```bash
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq .
```

**Expected output:**
```json
{
  "name": "oracle-xstream-rac-connector",
  "connector": { "state": "RUNNING" },
  "tasks": [{ "id": 0, "state": "RUNNING" }]
}
```

### Optional: Check Connect logs for streaming activity

```bash
tail -20 /tmp/connect-standalone.log | grep -E 'MTX_TRANSACTION|records sent|streaming'
```

---

## Step 5: Kafka Topic Verification

**What to say:** *"Now let's verify the Kafka topic and consume the CDC event."*

### 5a. List CDC topics

```bash
docker exec kafka2 kafka-topics --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 --list | grep -E 'MTX|racdb'
```

**Expected:** Topics like `racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS` or `racdb.XSTRPDB.ORDERMGMT.MTX_TRANSACTION_ITEMS`

### 5b. Consume messages from MTX_TRANSACTION_ITEMS topic

```bash
docker exec kafka2 kafka-console-consumer \
  --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 \
  --topic racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS \
  --from-beginning \
  --max-messages 5
```

**If topic uses XSTRPDB prefix:**
```bash
docker exec kafka2 kafka-console-consumer \
  --bootstrap-server kafka1:29092,kafka2:29092,kafka3:29092 \
  --topic racdb.XSTRPDB.ORDERMGMT.MTX_TRANSACTION_ITEMS \
  --from-beginning \
  --max-messages 5
```

---

## Step 6: Kafka Consumer Output

**What to say:** *"Here's the CDC message in Kafka – it matches our Oracle insert."*

### Sample output (Debezium JSON for the inserted record)

```json
{
  "before": null,
  "after": {
    "TRANSFER_ID": "TRF-DEMO-001",
    "PARTY_ID": "P100",
    "USER_TYPE": "REG",
    "ENTRY_TYPE": "DR",
    "ACCOUNT_ID": "ACC-WALLET-001",
    "REQUESTED_VALUE": 1500,
    "APPROVED_VALUE": 1500,
    "TRANSFER_STATUS": "COM",
    "USER_NAME": "DemoPresenter",
    "UNIQUE_SEQ_NUMBER": "SEQ-DEMO-20250317143022"
  },
  "source": {
    "version": "1.3.2",
    "connector": "Oracle XStream CDC",
    "name": "racdb",
    "ts_ms": 1710700000000,
    "snapshot": "false",
    "db": "XSTRPDB",
    "schema": "ORDERMGMT",
    "table": "MTX_TRANSACTION_ITEMS"
  },
  "op": "c",
  "ts_ms": 1710700001234
}
```

**Key fields:**
- `before`: null (INSERT has no previous state)
- `after`: New row data (matches Oracle)
- `source.table`: MTX_TRANSACTION_ITEMS
- `op`: `c` = create (INSERT)

---

## Step 7: Full Flow Explanation

**What to say:** *"Here's the complete pipeline we just demonstrated."*

```
Oracle Table (MTX_TRANSACTION_ITEMS)
     │
     │  INSERT → Redo log
     ▼
Oracle XStream Capture (CONFLUENT_XOUT1)
     │
     │  LCR (Logical Change Record)
     ▼
XStream Kafka Connector
     │
     │  Debezium JSON → Kafka produce
     ▼
Kafka Topic (racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS)
     │
     │  kafka-console-consumer
     ▼
Kafka Consumer Output (JSON)
```

| Step | Component | What Happens |
|------|-----------|--------------|
| 1 | Oracle | INSERT into MTX_TRANSACTION_ITEMS |
| 2 | XStream Capture | Reads redo, produces LCR |
| 3 | XStream Connector | Receives LCR, converts to Debezium JSON |
| 4 | Kafka | Event published to topic |
| 5 | Consumer | Reads message from topic |

---

## Step 8: Optional Monitoring

**What to say:** *"For ongoing monitoring, here are useful URLs and commands."*

### Connector status

```bash
curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq .
```

### Kafka Connect REST API

| URL | Purpose |
|-----|---------|
| http://localhost:8083/connectors | List connectors |
| http://localhost:8083/connectors/oracle-xstream-rac-connector/status | Connector status |

### Schema Registry (if used)

```bash
curl -s http://localhost:8081/subjects | jq .
```

### Grafana / Prometheus (if monitoring is installed)

| Service | URL |
|---------|-----|
| Grafana | http://localhost:3000 |
| Prometheus | http://localhost:9090 |

Use SSH port forwarding if accessing from a remote VM:
```bash
ssh -i key.pem -L 3000:localhost:3000 -L 8083:localhost:8083 -L 9090:localhost:9090 opc@<vm-ip>
```

---

## Quick Reference Card

| Action | Command |
|--------|---------|
| Oracle: count rows | `SELECT COUNT(*) FROM ORDERMGMT.MTX_TRANSACTION_ITEMS;` |
| Oracle: insert | Run INSERT above, then `COMMIT;` |
| Connector status | `curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status \| jq .` |
| List topics | `kafka-topics --bootstrap-server localhost:9092 --list \| grep racdb` |
| Consume CDC | `kafka-console-consumer --bootstrap-server localhost:9092 --topic racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS --partition 0 --offset 0 --max-messages 5` |

---

## Troubleshooting During Demo

| Issue | Quick fix |
|-------|-----------|
| No messages in Kafka | Wait 10–30 seconds after INSERT; XStream has slight delay |
| Topic not found | Try `racdb.XSTRPDB.ORDERMGMT.MTX_TRANSACTION_ITEMS` |
| Connector not RUNNING | `curl -X POST http://localhost:8083/connectors/oracle-xstream-rac-connector/restart` |
| Oracle connection refused | Check Security List allows 1521 from VM |

---

## Appendix: Sample Kafka Consumer Output

Actual output from `kafka-console-consumer` for `racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS`:

```
[opc@connector-vm oracle-xstream-cdc-poc]$ /opt/confluent/confluent/bin/kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS \
  --partition 0 --offset 0 \
  --max-messages 5
{"before":null,"after":{"TRANSFER_ID":"TRF001","PARTY_ID":"P001","USER_TYPE":"REG","ENTRY_TYPE":"DR","ACCOUNT_ID":"ACC001","ACCESS_TYPE":null,"PARTY_ACCESS_ID":null,"CATEGORY_CODE":null,"GRPH_DOMAIN_CODE":null,"ACCOUNT_TYPE":null,"REQUESTED_VALUE":"A+g=","APPROVED_VALUE":"A+g=","UNIT_PRICE":null,"PREVIOUS_BALANCE":null,"POST_BALANCE":null,"TRANSFER_PROFILE_DETAILS_ID":null,"PREVIOUS_CASH":null,"POST_CASH":null,"TRANSFER_VALUE":null,"ATTR_1_NAME":null,"ATTR_1_VALUE":null,"ATTR_2_NAME":null,"ATTR_2_VALUE":null,"ATTR_3_NAME":null,"ATTR_3_VALUE":null,"TRANSFER_DATE":1773641419000,"TRANSACTION_TYPE":"TRANS","SECOND_PARTY":"P002","FIRST_PTY_PAYMENT_METHOD_DESC":null,"SECOND_PTY_PAYMENT_METHOD_DESC":null,"SECOND_PARTY_ACCOUNT_ID":null,"SECOND_PARTY_ACCOUNT_TYPE":null,"SECOND_PARTY_CATEGORY_CODE":null,"TRANSFER_ON":null,"PROVIDER_ID":1,"TRANSFER_STATUS":"COM","PAYMENT_METHOD_TYPE":null,"SERVICE_TYPE":null,"TRANSFER_SUBTYPE":null,"REFERENCE_NUMBER":null,"WALLET_NUMBER":null,"PREF_LANGUAGE":null,"TXN_SEQUENCE_NUMBER":1001,"PAYMENT_TYPE_ID":1,"BANK_ID":null,"SECOND_PARTY_PROVIDER_ID":1,"COMMISSION_SLAB_CODE":null,"PSEUDO_USER_ID":null,"UNREG_USER_ID":null,"UNIQUE_SEQ_NUMBER":"SEQ-MTX-001","SECOND_UNREG_USER_ID":null,"SECOND_PSEUDO_USER_ID":null,"BANK_DOMAIN":null,"GRADE_CODE":null,"GRADE_ID":null,"USER_NAME":null,"LAST_NAME":null,"FIC":null,"FROZEN_AMOUNT":null},"source":{"version":"1.3.2","connector":"Oracle XStream CDC","name":"racdb","ts_ms":1773675117000,"snapshot":"first_in_data_collection","db":"XSTRPDB","sequence":null,"ts_us":1773675117000000,"ts_ns":1773675117000000000,"schema":"ORDERMGMT","table":"MTX_TRANSACTION_ITEMS","txId":null,"scn":"4139496","lcr_position":null,"user_name":null,"row_id":null},"transaction":null,"op":"r","ts_ms":1773675123799,"ts_us":1773675123799327,"ts_ns":1773675123799327051}
{"before":null,"after":{"TRANSFER_ID":"TRF002","PARTY_ID":"P002","USER_TYPE":"REG","ENTRY_TYPE":"CR","ACCOUNT_ID":"ACC002","ACCESS_TYPE":null,"PARTY_ACCESS_ID":null,"CATEGORY_CODE":null,"GRPH_DOMAIN_CODE":null,"ACCOUNT_TYPE":null,"REQUESTED_VALUE":"AfQ=","APPROVED_VALUE":"AfQ=","UNIT_PRICE":null,"PREVIOUS_BALANCE":null,"POST_BALANCE":null,"TRANSFER_PROFILE_DETAILS_ID":null,"PREVIOUS_CASH":null,"POST_CASH":null,"TRANSFER_VALUE":null,"ATTR_1_NAME":null,"ATTR_1_VALUE":null,"ATTR_2_NAME":null,"ATTR_2_VALUE":null,"ATTR_3_NAME":null,"ATTR_3_VALUE":null,"TRANSFER_DATE":1773641428000,"TRANSACTION_TYPE":"TRANS","SECOND_PARTY":"P001","FIRST_PTY_PAYMENT_METHOD_DESC":null,"SECOND_PTY_PAYMENT_METHOD_DESC":null,"SECOND_PARTY_ACCOUNT_ID":null,"SECOND_PARTY_ACCOUNT_TYPE":null,"SECOND_PARTY_CATEGORY_CODE":null,"TRANSFER_ON":null,"PROVIDER_ID":1,"TRANSFER_STATUS":"COM","PAYMENT_METHOD_TYPE":null,"SERVICE_TYPE":null,"TRANSFER_SUBTYPE":null,"REFERENCE_NUMBER":null,"WALLET_NUMBER":null,"PREF_LANGUAGE":null,"TXN_SEQUENCE_NUMBER":1002,"PAYMENT_TYPE_ID":1,"BANK_ID":null,"SECOND_PARTY_PROVIDER_ID":1,"COMMISSION_SLAB_CODE":null,"PSEUDO_USER_ID":null,"UNREG_USER_ID":null,"UNIQUE_SEQ_NUMBER":"SEQ-MTX-002","SECOND_UNREG_USER_ID":null,"SECOND_PSEUDO_USER_ID":null,"BANK_DOMAIN":null,"GRADE_CODE":null,"GRADE_ID":null,"USER_NAME":null,"LAST_NAME":null,"FIC":null,"FROZEN_AMOUNT":null},"source":{"version":"1.3.2","connector":"Oracle XStream CDC","name":"racdb","ts_ms":1773675117000,"snapshot":"true","db":"XSTRPDB","sequence":null,"ts_us":1773675117000000,"ts_ns":1773675117000000000,"schema":"ORDERMGMT","table":"MTX_TRANSACTION_ITEMS","txId":null,"scn":"4139496","lcr_position":null,"user_name":null,"row_id":null},"transaction":null,"op":"r","ts_ms":1773675123799,"ts_us":1773675123799674,"ts_ns":1773675123799674311}
{"before":null,"after":{"TRANSFER_ID":"TRF003","PARTY_ID":"P003","USER_TYPE":"REG","ENTRY_TYPE":"DR","ACCOUNT_ID":"ACC003","ACCESS_TYPE":null,"PARTY_ACCESS_ID":null,"CATEGORY_CODE":null,"GRPH_DOMAIN_CODE":null,"ACCOUNT_TYPE":null,"REQUESTED_VALUE":"APo=","APPROVED_VALUE":"APo=","UNIT_PRICE":null,"PREVIOUS_BALANCE":null,"POST_BALANCE":null,"TRANSFER_PROFILE_DETAILS_ID":null,"PREVIOUS_CASH":null,"POST_CASH":null,"TRANSFER_VALUE":null,"ATTR_1_NAME":null,"ATTR_1_VALUE":null,"ATTR_2_NAME":null,"ATTR_2_VALUE":null,"ATTR_3_NAME":null,"ATTR_3_VALUE":null,"TRANSFER_DATE":1773641436000,"TRANSACTION_TYPE":"TRANS","SECOND_PARTY":"P001","FIRST_PTY_PAYMENT_METHOD_DESC":null,"SECOND_PTY_PAYMENT_METHOD_DESC":null,"SECOND_PARTY_ACCOUNT_ID":null,"SECOND_PARTY_ACCOUNT_TYPE":null,"SECOND_PARTY_CATEGORY_CODE":null,"TRANSFER_ON":null,"PROVIDER_ID":1,"TRANSFER_STATUS":"PEN","PAYMENT_METHOD_TYPE":null,"SERVICE_TYPE":null,"TRANSFER_SUBTYPE":null,"REFERENCE_NUMBER":null,"WALLET_NUMBER":null,"PREF_LANGUAGE":null,"TXN_SEQUENCE_NUMBER":1003,"PAYMENT_TYPE_ID":1,"BANK_ID":null,"SECOND_PARTY_PROVIDER_ID":1,"COMMISSION_SLAB_CODE":null,"PSEUDO_USER_ID":null,"UNREG_USER_ID":null,"UNIQUE_SEQ_NUMBER":"SEQ-MTX-003","SECOND_UNREG_USER_ID":null,"SECOND_PSEUDO_USER_ID":null,"BANK_DOMAIN":null,"GRADE_CODE":null,"GRADE_ID":null,"USER_NAME":"TestUser","LAST_NAME":null,"FIC":null,"FROZEN_AMOUNT":null},"source":{"version":"1.3.2","connector":"Oracle XStream CDC","name":"racdb","ts_ms":1773675117000,"snapshot":"true","db":"XSTRPDB","sequence":null,"ts_us":1773675117000000,"ts_ns":1773675117000000000,"schema":"ORDERMGMT","table":"MTX_TRANSACTION_ITEMS","txId":null,"scn":"4139496","lcr_position":null,"user_name":null,"row_id":null},"transaction":null,"op":"r","ts_ms":1773675123799,"ts_us":1773675123799907,"ts_ns":1773675123799907256}
{"before":null,"after":{"TRANSFER_ID":"TRF001","PARTY_ID":"P001","USER_TYPE":"REG","ENTRY_TYPE":"DR","ACCOUNT_ID":"ACC001","ACCESS_TYPE":null,"PARTY_ACCESS_ID":null,"CATEGORY_CODE":null,"GRPH_DOMAIN_CODE":null,"ACCOUNT_TYPE":null,"REQUESTED_VALUE":"A+g=","APPROVED_VALUE":"A+g=","UNIT_PRICE":null,"PREVIOUS_BALANCE":null,"POST_BALANCE":null,"TRANSFER_PROFILE_DETAILS_ID":null,"PREVIOUS_CASH":null,"POST_CASH":null,"TRANSFER_VALUE":null,"ATTR_1_NAME":null,"ATTR_1_VALUE":null,"ATTR_2_NAME":null,"ATTR_2_VALUE":null,"ATTR_3_NAME":null,"ATTR_3_VALUE":null,"TRANSFER_DATE":1773671816000,"TRANSACTION_TYPE":"TRANS","SECOND_PARTY":"P002","FIRST_PTY_PAYMENT_METHOD_DESC":null,"SECOND_PTY_PAYMENT_METHOD_DESC":null,"SECOND_PARTY_ACCOUNT_ID":null,"SECOND_PARTY_ACCOUNT_TYPE":null,"SECOND_PARTY_CATEGORY_CODE":null,"TRANSFER_ON":null,"PROVIDER_ID":1,"TRANSFER_STATUS":"COM","PAYMENT_METHOD_TYPE":null,"SERVICE_TYPE":null,"TRANSFER_SUBTYPE":null,"REFERENCE_NUMBER":null,"WALLET_NUMBER":null,"PREF_LANGUAGE":null,"TXN_SEQUENCE_NUMBER":1001,"PAYMENT_TYPE_ID":1,"BANK_ID":null,"SECOND_PARTY_PROVIDER_ID":1,"COMMISSION_SLAB_CODE":null,"PSEUDO_USER_ID":null,"UNREG_USER_ID":null,"UNIQUE_SEQ_NUMBER":"SEQ-MTX-001-20260316143656","SECOND_UNREG_USER_ID":null,"SECOND_PSEUDO_USER_ID":null,"BANK_DOMAIN":null,"GRADE_CODE":null,"GRADE_ID":null,"USER_NAME":null,"LAST_NAME":null,"FIC":null,"FROZEN_AMOUNT":null},"source":{"version":"1.3.2","connector":"Oracle XStream CDC","name":"racdb","ts_ms":1773675117000,"snapshot":"true","db":"XSTRPDB","sequence":null,"ts_us":1773675117000000,"ts_ns":1773675117000000000,"schema":"ORDERMGMT","table":"MTX_TRANSACTION_ITEMS","txId":null,"scn":"4139496","lcr_position":null,"user_name":null,"row_id":null},"transaction":null,"op":"r","ts_ms":1773675123802,"ts_us":1773675123802348,"ts_ns":1773675123802348942}
{"before":null,"after":{"TRANSFER_ID":"TRF002","PARTY_ID":"P002","USER_TYPE":"REG","ENTRY_TYPE":"CR","ACCOUNT_ID":"ACC002","ACCESS_TYPE":null,"PARTY_ACCESS_ID":null,"CATEGORY_CODE":null,"GRPH_DOMAIN_CODE":null,"ACCOUNT_TYPE":null,"REQUESTED_VALUE":"AfQ=","APPROVED_VALUE":"AfQ=","UNIT_PRICE":null,"PREVIOUS_BALANCE":null,"POST_BALANCE":null,"TRANSFER_PROFILE_DETAILS_ID":null,"PREVIOUS_CASH":null,"POST_CASH":null,"TRANSFER_VALUE":null,"ATTR_1_NAME":null,"ATTR_1_VALUE":null,"ATTR_2_NAME":null,"ATTR_2_VALUE":null,"ATTR_3_NAME":null,"ATTR_3_VALUE":null,"TRANSFER_DATE":1773671816000,"TRANSACTION_TYPE":"TRANS","SECOND_PARTY":"P001","FIRST_PTY_PAYMENT_METHOD_DESC":null,"SECOND_PTY_PAYMENT_METHOD_DESC":null,"SECOND_PARTY_ACCOUNT_ID":null,"SECOND_PARTY_ACCOUNT_TYPE":null,"SECOND_PARTY_CATEGORY_CODE":null,"TRANSFER_ON":null,"PROVIDER_ID":1,"TRANSFER_STATUS":"COM","PAYMENT_METHOD_TYPE":null,"SERVICE_TYPE":null,"TRANSFER_SUBTYPE":null,"REFERENCE_NUMBER":null,"WALLET_NUMBER":null,"PREF_LANGUAGE":null,"TXN_SEQUENCE_NUMBER":1002,"PAYMENT_TYPE_ID":1,"BANK_ID":null,"SECOND_PARTY_PROVIDER_ID":1,"COMMISSION_SLAB_CODE":null,"PSEUDO_USER_ID":null,"UNREG_USER_ID":null,"UNIQUE_SEQ_NUMBER":"SEQ-MTX-002-20260316143656","SECOND_UNREG_USER_ID":null,"SECOND_PSEUDO_USER_ID":null,"BANK_DOMAIN":null,"GRADE_CODE":null,"GRADE_ID":null,"USER_NAME":null,"LAST_NAME":null,"FIC":null,"FROZEN_AMOUNT":null},"source":{"version":"1.3.2","connector":"Oracle XStream CDC","name":"racdb","ts_ms":1773675117000,"snapshot":"true","db":"XSTRPDB","sequence":null,"ts_us":1773675117000000,"ts_ns":1773675117000000000,"schema":"ORDERMGMT","table":"MTX_TRANSACTION_ITEMS","txId":null,"scn":"4139496","lcr_position":null,"user_name":null,"row_id":null},"transaction":null,"op":"r","ts_ms":1773675123802,"ts_us":1773675123802637,"ts_ns":1773675123802637563}
Processed a total of 5 messages
[opc@connector-vm oracle-xstream-cdc-poc]$
```
