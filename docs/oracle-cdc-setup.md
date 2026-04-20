# Oracle CDC Setup (XStream)

## What CDC does

CDC captures committed database changes and streams them without full table scans.

## Oracle XStream setup sequence

Run in order (as documented in `oracle-database/`):

1. `01-create-sample-schema.sql`
2. `02-enable-xstream.sql`
3. `03-supplemental-logging.sql`
4. `04-create-xstream-users.sql`
5. `05-load-sample-data.sql`
6. `06-create-outbound-ordermgmt.sql`

## Start / check XStream

```bash
sqlplus -L sys/<pwd>@//<host>:1521/<service> as sysdba @oracle-database/09-check-and-start-xstream.sql
```

## Verify outbound and capture status

```bash
export ORACLE_SYSDBA_CONN='sys/<pwd>@//<host>:1521/<service> AS SYSDBA'
./oracle-database/run-08-verify-xstream-outbound.sh
```

## Stop XStream safely

```sql
BEGIN
  DBMS_CAPTURE_ADM.STOP_CAPTURE(capture_name => 'CONFLUENT_XOUT1');
  DBMS_APPLY_ADM.STOP_APPLY(apply_name => 'XOUT');
END;
/
```

## Teardown (only when required)

```bash
sqlplus -L c##xstrmadmin/<pwd>@//<host>:1521/<service> as sysdba @oracle-database/10-teardown-xstream-outbound.sql
```
