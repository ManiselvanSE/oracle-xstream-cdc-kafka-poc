# Oracle Database Scripts

SQL scripts for configuring Oracle RAC for XStream CDC. Run **in order** (01 → 14).

| # | Script | Purpose |
|---|--------|---------|
| 01 | `01-create-sample-schema.sql` | ORDERMGMT schema and tables |
| 02 | `02-enable-xstream.sql` | Enable XStream replication |
| 03 | `03-supplemental-logging.sql` | Supplemental logging for CDC |
| 04 | `04-create-xstream-users.sql` | XStream admin and connect users |
| 05 | `05-load-sample-data.sql` | Sample data for ORDERMGMT |
| 06 | `06-create-outbound-ordermgmt.sql` | XStream Out outbound server |
| 07 | `07-produce-orders-procedure.sql` | Test data generation |
| 08 | `08-verify-xstream-outbound.sql` | Verify outbound configuration |
| 09 | `09-check-and-start-xstream.sql` | Check/start capture and apply |
| 10 | `10-teardown-xstream-outbound.sql` | Drop outbound (teardown) |
| 11 | `11-add-table-to-cdc.sql` | Add new table to existing CDC |
| 12–14 | MTX_TRANSACTION_ITEMS | Table creation and onboarding |

Connect as SYSDBA for most scripts. See [../docs/EXECUTION-GUIDE.md](../docs/EXECUTION-GUIDE.md) for detailed commands.
