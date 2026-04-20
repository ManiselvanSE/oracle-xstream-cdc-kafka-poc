# Onboard MTX_TRANSACTION_ITEMS to CDC Pipeline

After creating the table with `12-create-mtx-transaction-items.sql`, run these steps to add it to the CDC pipeline.

## Step 1: Create table (already done by 12)

```bash
sqlplus sys/<pwd>@//racdb-scan...:1521/DB0312_r8n_phx... as sysdba @12-create-mtx-transaction-items.sql
```

## Step 2: Add to XStream outbound

```bash
sqlplus c##xstrmadmin/<pwd>@//racdb-scan...:1521/DB0312_r8n_phx... as sysdba @11-add-table-to-cdc.sql "ORDERMGMT.MTX_TRANSACTION_ITEMS"
```

## Step 3: Update connector and restart (on VM)

```bash
cd /home/opc/oracle-xstream-cdc-poc

curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/config | \
  jq '. + {"table.include.list": "ORDERMGMT\\.(REGIONS|COUNTRIES|LOCATIONS|WAREHOUSES|EMPLOYEES|PRODUCT_CATEGORIES|PRODUCTS|CUSTOMERS|CONTACTS|ORDERS|ORDER_ITEMS|INVENTORIES|NOTES|MTX_TRANSACTION_ITEMS)"}' | \
  jq 'del(.name)' | \
  curl -s -X PUT -H "Content-Type: application/json" -d @- \
  http://localhost:8083/connectors/oracle-xstream-rac-connector/config

curl -X POST "http://localhost:8083/connectors/oracle-xstream-rac-connector/restart?includeTasks=true"

curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status
```

## Step 4: Verify topic

```bash
/opt/confluent/confluent/bin/kafka-topics --bootstrap-server localhost:9092 --list | grep MTX_TRANSACTION
```

Expected: `racdb.XSTRPDB.ORDERMGMT.MTX_TRANSACTION_ITEMS`
