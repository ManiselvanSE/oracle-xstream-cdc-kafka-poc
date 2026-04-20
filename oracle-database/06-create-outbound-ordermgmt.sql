-- =============================================================================
-- Oracle XStream CDC - Step 6: Create Outbound Server for ORDERMGMT schema
-- Based on: https://github.com/ora0600/confluent-new-cdc-connector
-- Run as XStream admin (c##xstrmadmin) - connect to CDB
-- =============================================================================

-- Connect as: sqlplus c##xstrmadmin/<password>@//<rac-host>:1521/<db-service> as sysdba

DECLARE
  tables  DBMS_UTILITY.UNCL_ARRAY;
  schemas DBMS_UTILITY.UNCL_ARRAY;
BEGIN
  tables(1)  := 'ORDERMGMT.REGIONS';
  tables(2)  := 'ORDERMGMT.COUNTRIES';
  tables(3)  := 'ORDERMGMT.LOCATIONS';
  tables(4)  := 'ORDERMGMT.WAREHOUSES';
  tables(5)  := 'ORDERMGMT.EMPLOYEES';
  tables(6)  := 'ORDERMGMT.PRODUCT_CATEGORIES';
  tables(7)  := 'ORDERMGMT.PRODUCTS';
  tables(8)  := 'ORDERMGMT.CUSTOMERS';
  tables(9)  := 'ORDERMGMT.CONTACTS';
  tables(10) := 'ORDERMGMT.ORDERS';
  tables(11) := 'ORDERMGMT.ORDER_ITEMS';
  tables(12) := 'ORDERMGMT.INVENTORIES';
  tables(13) := 'ORDERMGMT.NOTES';
  tables(14) := 'ORDERMGMT.MTX_TRANSACTION_ITEMS';
  tables(15) := NULL;
  schemas(1) := 'ORDERMGMT';

  DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
    capture_name          => 'confluent_xout1',
    server_name            => 'xout',
    source_container_name  => 'XSTRPDB',
    table_names            => tables,
    schema_names           => schemas,
    comment                => 'Confluent XStream CDC Connector');

  -- Checkpoint retention
  DBMS_CAPTURE_ADM.ALTER_CAPTURE(
    capture_name              => 'confluent_xout1',
    checkpoint_retention_time => 7);

  -- Stream pool (use 256 for XE, 1024 for EE)
  DBMS_XSTREAM_ADM.SET_PARAMETER(
    streams_type => 'capture',
    streams_name => 'confluent_xout1',
    parameter    => 'max_sga_size',
    value        => '1024');

  DBMS_XSTREAM_ADM.SET_PARAMETER(
    streams_type => 'apply',
    streams_name => 'xout',
    parameter    => 'max_sga_size',
    value        => '1024');
END;
/

-- Set connect user (run as DBA) - common user per Confluent CDB prereqs
BEGIN
  DBMS_XSTREAM_ADM.ALTER_OUTBOUND(
    server_name  => 'xout',
    connect_user => 'c##cfltuser');
END;
/

-- RAC: ensure capture runs on same instance as queue (per Confluent RAC prereqs)
BEGIN
  DBMS_CAPTURE_ADM.SET_PARAMETER(
    capture_name => 'confluent_xout1',
    parameter    => 'use_rac_service',
    value        => 'Y');
END;
/

-- Verify
SELECT SERVER_NAME, CONNECT_USER, CAPTURE_NAME FROM ALL_XSTREAM_OUTBOUND;
