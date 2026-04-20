-- =============================================================================
-- Oracle XStream CDC - Create MTX_TRANSACTION_ITEMS table in ORDERMGMT schema
-- Run as SYSDBA: @12-create-mtx-transaction-items.sql
-- After this: run supplemental logging, grant, add to XStream, update connector
-- =============================================================================

ALTER SESSION SET CONTAINER = XSTRPDB;

CREATE TABLE ORDERMGMT.MTX_TRANSACTION_ITEMS (
  TRANSFER_ID                    VARCHAR2(20)    NOT NULL,
  PARTY_ID                       VARCHAR2(20)    NOT NULL,
  USER_TYPE                      VARCHAR2(10)    NOT NULL,
  ENTRY_TYPE                     VARCHAR2(5)     NOT NULL,
  ACCOUNT_ID                     VARCHAR2(60)    NOT NULL,
  ACCESS_TYPE                    VARCHAR2(10),
  PARTY_ACCESS_ID                VARCHAR2(255),
  CATEGORY_CODE                  VARCHAR2(20),
  GRPH_DOMAIN_CODE               VARCHAR2(20),
  ACCOUNT_TYPE                   VARCHAR2(20),
  REQUESTED_VALUE                NUMBER(19,0),
  APPROVED_VALUE                 NUMBER(19,0),
  UNIT_PRICE                     NUMBER(19,0),
  PREVIOUS_BALANCE               NUMBER(19,0),
  POST_BALANCE                   NUMBER(19,0),
  TRANSFER_PROFILE_DETAILS_ID    VARCHAR2(20),
  PREVIOUS_CASH                  NUMBER(19,0),
  POST_CASH                      NUMBER(19,0),
  TRANSFER_VALUE                 NUMBER(19,0),
  ATTR_1_NAME                    VARCHAR2(255),
  ATTR_1_VALUE                   VARCHAR2(255),
  ATTR_2_NAME                    VARCHAR2(255),
  ATTR_2_VALUE                   VARCHAR2(255),
  ATTR_3_NAME                    VARCHAR2(255),
  ATTR_3_VALUE                   VARCHAR2(255),
  TRANSFER_DATE                  DATE            NOT NULL,
  TRANSACTION_TYPE               VARCHAR2(6)    NOT NULL,
  SECOND_PARTY                   VARCHAR2(20)    NOT NULL,
  FIRST_PTY_PAYMENT_METHOD_DESC  VARCHAR2(20),
  SECOND_PTY_PAYMENT_METHOD_DESC VARCHAR2(20),
  SECOND_PARTY_ACCOUNT_ID        VARCHAR2(60),
  SECOND_PARTY_ACCOUNT_TYPE      VARCHAR2(20),
  SECOND_PARTY_CATEGORY_CODE     VARCHAR2(20),
  TRANSFER_ON                    TIMESTAMP(6),
  PROVIDER_ID                    NUMBER(3,0)     NOT NULL,
  TRANSFER_STATUS                VARCHAR2(3),
  PAYMENT_METHOD_TYPE            VARCHAR2(20),
  SERVICE_TYPE                   VARCHAR2(20),
  TRANSFER_SUBTYPE               VARCHAR2(20),
  REFERENCE_NUMBER               VARCHAR2(50),
  WALLET_NUMBER                  VARCHAR2(25),
  PREF_LANGUAGE                  VARCHAR2(5),
  TXN_SEQUENCE_NUMBER            NUMBER(10,0)   NOT NULL,
  PAYMENT_TYPE_ID                NUMBER(2,0)    NOT NULL,
  BANK_ID                        VARCHAR2(20),
  SECOND_PARTY_PROVIDER_ID       NUMBER(3,0)    NOT NULL,
  COMMISSION_SLAB_CODE           NUMBER(2,0),
  PSEUDO_USER_ID                 VARCHAR2(20),
  UNREG_USER_ID                  VARCHAR2(20),
  UNIQUE_SEQ_NUMBER              VARCHAR2(50)    NOT NULL,
  SECOND_UNREG_USER_ID           VARCHAR2(20),
  SECOND_PSEUDO_USER_ID          VARCHAR2(20),
  BANK_DOMAIN                    VARCHAR2(20),
  GRADE_CODE                     VARCHAR2(64 CHAR),
  GRADE_ID                       NUMBER(20,0),
  USER_NAME                      VARCHAR2(80),
  LAST_NAME                      VARCHAR2(80),
  FIC                            VARCHAR2(50),
  FROZEN_AMOUNT                  VARCHAR2(50),
  CONSTRAINT MTX_TXN_ITEMS_PK PRIMARY KEY (UNIQUE_SEQ_NUMBER)
)
TABLESPACE ordermgmt_tbs
PARTITION BY RANGE (TRANSFER_DATE) INTERVAL (NUMTODSINTERVAL(1,'DAY'))
(
  PARTITION MTX_TRANSACTION_ITEMS_20120401 VALUES LESS THAN (TO_DATE('2012-04-01','YYYY-MM-DD'))
)
ENABLE ROW MOVEMENT;

-- Supplemental logging (required for CDC)
ALTER TABLE ORDERMGMT.MTX_TRANSACTION_ITEMS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- Grant SELECT to connector user
GRANT SELECT ON ORDERMGMT.MTX_TRANSACTION_ITEMS TO c##cfltuser;

PROMPT Table MTX_TRANSACTION_ITEMS created. Run 11-add-table-to-cdc.sql and update connector.
