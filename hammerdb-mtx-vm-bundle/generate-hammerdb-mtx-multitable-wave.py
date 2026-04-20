#!/usr/bin/env python3
from __future__ import annotations

"""Emit hammerdb-mtx-multitable-wave.sql from ORDERMGMT DDL (ug-prod + MTX_TRANSACTION_ITEMS).
Run: python3 generate-hammerdb-mtx-multitable-wave.py > hammerdb-mtx-multitable-wave.sql
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DDL = (ROOT / "ug-prod-ordermgmt-drop-and-create.sql").read_text()
ITEMS = (ROOT / "12-create-mtx-transaction-items.sql").read_text()


def extract_table(name: str, src: str) -> list[tuple[str, str]]:
    pat = rf"CREATE TABLE ORDERMGMT\.{re.escape(name)} \(\s*(.*?)\s*\)\s*TABLESPACE"
    m = re.search(pat, src, re.DOTALL | re.IGNORECASE)
    if not m:
        raise ValueError(f"Table not found: {name}")
    cols = []
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line or line.startswith("--") or line.upper().startswith("CONSTRAINT"):
            continue
        parts = line.split()
        cols.append((parts[0], " ".join(parts[1:])))
    return cols


def varchar_expr(width: int) -> str:
    return f"SUBSTR('HDB'||SUBSTR(v_suf,1,{min(width, 500)}),1,{width})"


def number_expr(col_name: str, table: str, spec: str) -> str:
    # DBMS_UTILITY.GET_HASH_VALUE works in PL/SQL; ORA_HASH is not always visible in PL/SQL blocks.
    mix = f"DBMS_UTILITY.GET_HASH_VALUE('{table}.{col_name}', 1, 999999)"
    m = re.search(r"NUMBER\s*\(\s*(\d+)\s*(?:,\s*(\d+)\s*)?\)", spec, re.I)
    if not m:
        return f"MOD(n_id + {mix}, 999999)"
    prec, scale = int(m.group(1)), int(m.group(2) or 0)
    if scale > 0:
        return f"ROUND(MOD(n_id, 999999) / {10 ** (6 + scale)}, {scale})"
    cap = min(10**prec - 1, 10**15)
    return f"MOD(n_id + {mix}, {cap}) + 1"


def items_only_non_null_fallback(spec: str) -> str:
    """Non-null literal for items_only INSERT (no v_suf in statement)."""
    su = spec.upper()
    if "CLOB" in su or "NCLOB" in su:
        return "TO_CLOB(RPAD('X',4000,'X'))"
    if "BLOB" in su:
        return "UTL_RAW.CAST_TO_RAW(RPAD('HDB',3,'B'))"
    if re.search(r"\bFLOAT\b", su) or "BINARY_FLOAT" in su or "BINARY_DOUBLE" in su:
        return "42"
    if re.search(r"\bINTEGER\b", su) or re.search(r"\bSMALLINT\b", su):
        return "12345"
    return "SUBSTR('HDB-ITEMS',1,80)"


def gen_non_null_fallback(col_name: str, spec: str, table: str) -> str:
    """Synthetic value for column types not matched above (wave PL/SQL has v_suf, n_id)."""
    su = spec.upper()
    if "CLOB" in su or "NCLOB" in su:
        return "TO_CLOB(RPAD('X',4000,'X'))"
    if "BLOB" in su:
        return "UTL_RAW.CAST_TO_RAW(RPAD('HDB',3,'B'))"
    if re.search(r"\bLONG\s+RAW\b", su, re.I):
        return "UTL_RAW.CAST_TO_RAW('00')"
    if re.search(r"\bLONG\b", su, re.I) and "BINARY" not in su:
        return "SUBSTR('HDB'||v_suf,1,4000)"
    if re.search(r"\bRAW\s*\(", su, re.I):
        return "HEXTORAW('486442')"
    if re.search(r"\bFLOAT\b", su) or "BINARY_FLOAT" in su or "BINARY_DOUBLE" in su:
        return "MOD(n_id, 999999) + 1"
    if re.search(r"\bINTEGER\b", su) or re.search(r"\bSMALLINT\b", su):
        return number_expr(col_name, table, "NUMBER(10,0)")
    if re.search(r"\bNUMBER\b", su):
        return number_expr(col_name, table, spec)
    return varchar_expr(80)


def gen_value(col_name: str, spec: str, table: str) -> str:
    cl = col_name.upper()
    # Narrative / join keys
    if cl == "TRANSFER_ID":
        # Must match MTX_TRANSACTION_HEADER.TRANSFER_ID (VARCHAR2(20) PK) for FK children.
        return "SUBSTR('TRF'||v_suf,1,20)"
    if cl == "BATCH_ID":
        return "SUBSTR('BAT'||v_suf,1,20)"
    if cl == "WALLET_NUMBER":
        return "SUBSTR('WL'||v_suf,1,25)"
    if cl == "UNIQUE_SEQ_NUMBER":
        return "SUBSTR('SEQ-MTX-HDB-'||v_suf,1,50)"
    if table == "MTX_PARTY" and cl == "USER_ID":
        return "SUBSTR('UP'||v_suf,1,20)"
    if table == "MTX_PARTY_ACCESS" and cl == "USER_ID":
        return "SUBSTR('UP'||v_suf,1,20)"
    if table == "MTX_CHURN_USERS" and cl == "USER_ID":
        return "SUBSTR('UP'||v_suf,1,20)"
    if cl == "PARTY_ID" and table == "MTX_PARTY_BLACK_LIST":
        return "SUBSTR('UP'||v_suf,1,30)"
    if cl == "BLACK_LIST_TYPE_ID":
        return "SUBSTR('BL'||v_suf,1,10)"
    if table == "MTX_ADMIN_AUDIT_TRAIL" and cl == "SN":
        return "SUBSTR('ADM'||v_suf,1,38)"
    if table == "MTX_AUDIT_TRAIL" and cl == "SN":
        return "SUBSTR('TXN'||v_suf,1,38)"
    if table == "MTX_PARTY_BARRED_HIST" and cl == "SN":
        return "n_id"
    if cl in ("PAYER_MSISDN", "PAYEE_MSISDN"):
        return "SUBSTR('265'||v_suf,1,20)"
    if cl == "MSISDN":
        return "SUBSTR('265'||v_suf,1,15)"
    if table == "MTX_PARTY" and cl == "NETWORK_CODE":
        return "SUBSTR('01'||v_suf,1,2)"
    if table == "MTX_PARTY" and cl == "CATEGORY_CODE":
        return "SUBSTR('REG',1,10)"
    if table == "MTX_PARTY" and cl in ("PARENT_ID", "OWNER_ID"):
        return "SUBSTR('P001',1,20)"

    # Range / charge graph: single n_id + slab 1
    if table == "MTX_SERVICE_CHARGE" and cl == "SERVICE_CHARGE_ID":
        return "n_id"
    if table == "MTX_BNSART_RANGE_DETAILS" and cl == "BNSART_RANGE_ID":
        return "n_id"
    if table == "MTX_BNSART_RANGE" and cl == "BNSART_RANGE_ID":
        return "n_id"
    if table == "MTX_BNSART_RANGE" and cl == "SLAB_CODE":
        return "1"
    if table == "MTX_BNSART_RANGE_DETAILS" and cl == "SERVICE_CHARGE_ID":
        return "n_id"
    if table == "MTX_SERV_CHRG_RANGE_DETAILS" and cl == "SERVICE_CHARGE_RANGE_ID":
        return "n_id"
    if table == "MTX_SERV_CHRG_RANGE_DETAILS" and cl == "SERVICE_CHARGE_ID":
        return "n_id"
    if table == "MTX_SERVICE_CHARGE_RANGE" and cl == "SERVICE_CHARGE_RANGE_ID":
        return "n_id"
    if table == "MTX_SERVICE_CHARGE_RANGE" and cl == "SLAB_CODE":
        return "1"
    if table == "MTX_COMMISSION_RANGE_DETAILS" and cl == "COMMISSION_RANGE_ID":
        return "n_id"
    if table == "MTX_COMMISSION_RANGE_DETAILS" and cl == "SERVICE_CHARGE_ID":
        return "n_id"
    if table == "MTX_COMMISSION_RANGE" and cl == "COMMISSION_RANGE_ID":
        return "n_id"
    if table == "MTX_COMMISSION_RANGE" and cl == "SLAB_CODE":
        return "1"
    if table == "MTX_PARTY_ACCESS" and cl == "USER_PHONES_ID":
        return "n_id"
    if table == "MTX_CHURN_USERS" and cl == "SEQUENCE_ID":
        return "n_id"
    if table == "MTX_TRANSACTION_ITEMS" and cl == "PARTY_ID":
        return "SUBSTR('UP'||v_suf,1,20)"
    if table == "MTX_TRANSACTION_ITEMS" and cl == "SECOND_PARTY":
        return "SUBSTR('UP'||v_suf,1,20)"
    if table == "MTX_WALLET" and cl == "USER_ID":
        return "SUBSTR('UP'||v_suf,1,20)"

    s = spec
    if "TIMESTAMP" in s:
        return "SYSTIMESTAMP"
    if re.search(r"\bDATE\b", s) and "TIMESTAMP" not in s:
        return "SYSDATE"
    m = re.search(r"VARCHAR2\((\d+)(?:\s+CHAR)?\)", s, re.I)
    if m:
        return varchar_expr(int(m.group(1)))
    m = re.search(r"NVARCHAR2\((\d+)\)", s, re.I)
    if m:
        return varchar_expr(int(m.group(1)))
    m = re.search(r"CHAR\((\d+)\)", s, re.I)
    if m:
        w = int(m.group(1))
        return f"RPAD(SUBSTR('Y'||v_suf,1,{w}),{w},'Y')"
    if re.search(r"\bNUMBER\b", s, re.I):
        return number_expr(col_name, table, s)
    return gen_non_null_fallback(col_name, spec, table)


# Insert order: parents before children (TRANSFER_ID, BATCH_ID, PARTY/USER_ID FKs).
TABLES_ORDER = [
    "MTX_SERVICE_CHARGE",
    "MTX_BNSART_RANGE_DETAILS",
    "MTX_BNSART_RANGE",
    "MTX_SERV_CHRG_RANGE_DETAILS",
    "MTX_SERVICE_CHARGE_RANGE",
    "MTX_COMMISSION_RANGE_DETAILS",
    "MTX_COMMISSION_RANGE",
    "MTX_PARTY",
    "MTX_PARTY_ACCESS",
    "MTX_BATCHES",
    "MTX_TRANSACTION_HEADER",
    "MTX_TRANSACTION_HEADER_META",
    "MTX_WALLET",
    "MTX_WALLET_BALANCES",
    "MTX_AMBIGUOUS_TXN_DETAILS",
    "MTX_TRANSACTION_APPROVAL",
    "MTX_BATCH_PAYMENT",
    "MTX_TRANSACTION_ITEMS",
    "MTX_PARTY_BARRED_HIST",
    "MTX_PARTY_BLACK_LIST",
    "MTX_CHURN_USERS",
    "MTX_ADMIN_AUDIT_TRAIL",
    "MTX_AUDIT_TRAIL",
]


def number_literal_items(col_name: str, spec: str) -> str:
    """Fixed numbers for items_only (no n_id in scope)."""
    m = re.search(r"NUMBER\s*\(\s*(\d+)\s*(?:,\s*(\d+)\s*)?\)", spec, re.I)
    if not m:
        return "42"
    prec, scale = int(m.group(1)), int(m.group(2) or 0)
    if scale > 0:
        return f"ROUND(POWER(10, -{scale}), {scale})"
    cap = min(10**prec - 1, 999999)
    return str(min(12345, cap))


def items_only_values(cols: list[tuple[str, str]]) -> list[str]:
    """VALUES for items_only: bind vars for keys, literals elsewhere (no v_suf)."""
    outv = []
    for cname, spec in cols:
        cl = cname.upper()
        if cl == "TRANSFER_ID":
            outv.append(":trf")
        elif cl == "PARTY_ID":
            outv.append(":pty")
        elif cl == "ACCOUNT_ID":
            outv.append(":acc")
        elif cl == "SECOND_PARTY":
            outv.append(":sec")
        elif cl == "TXN_SEQUENCE_NUMBER":
            outv.append(":txnseq")
        elif cl == "UNIQUE_SEQ_NUMBER":
            outv.append(":seq")
        else:
            s = spec
            if "TIMESTAMP" in s:
                outv.append("SYSTIMESTAMP")
            elif re.search(r"\bDATE\b", s) and "TIMESTAMP" not in s:
                outv.append("SYSDATE")
            elif re.search(r"VARCHAR2|NVARCHAR2", s, re.I):
                m = re.search(r"\((\d+)\)", s)
                w = int(m.group(1)) if m else 10
                outv.append(f"SUBSTR('HDB-ITEMS',1,{w})")
            elif re.search(r"CHAR\(", s, re.I):
                m = re.search(r"CHAR\((\d+)\)", s, re.I)
                w = int(m.group(1)) if m else 1
                outv.append(f"RPAD('Y',{w},'Y')")
            elif re.search(r"\bNUMBER\b", s, re.I):
                outv.append(number_literal_items(cname, s))
            else:
                outv.append(items_only_non_null_fallback(spec))
    return outv


def main() -> None:
    out = []
    out.append(
        """-- Full-column INSERT wave: every column listed; synthetic non-null values per DDL type.
-- Source DDL: ug-prod-ordermgmt-drop-and-create.sql, 12-create-mtx-transaction-items.sql
-- Regenerate: python3 generate-hammerdb-mtx-multitable-wave.py > hammerdb-mtx-multitable-wave.sql
-- HDB_MTX_MODE=all_mtx (hammerdb-mtx-custom-driver.tcl). Bind :suf from Oratcl.
-- TABLE order: MTX_TRANSACTION_HEADER before rows referencing TRANSFER_ID; MTX_PARTY before PARTY_ID/USER_ID children.

DECLARE
  v_suf VARCHAR2(128) := :suf;
  n_id NUMBER;
BEGIN
  n_id := 1000000 + MOD(ABS(DBMS_UTILITY.GET_HASH_VALUE(v_suf, 1, 2147483646)), 999999);
"""
    )

    for tname in TABLES_ORDER:
        src = ITEMS if tname == "MTX_TRANSACTION_ITEMS" else DDL
        cols = extract_table(tname, src)
        cnames = ", ".join(c[0] for c in cols)
        vals = ", ".join(gen_value(c[0], c[1], tname) for c in cols)
        out.append(
            f"  BEGIN INSERT INTO ORDERMGMT.{tname} ({cnames}) VALUES ({vals}); EXCEPTION WHEN OTHERS THEN NULL; END;"
        )

    cols = extract_table("MTX_USER_BANK_SWEEP_DTLS", DDL)
    cnames = ", ".join(c[0] for c in cols)
    sel = []
    for cname, spec in cols:
        if cname == "USER_ID":
            sel.append("u.USER_ID")
        elif cname == "STATUS":
            sel.append("SUBSTR(RPAD(v_suf,5,'0'),1,5)")
        elif cname == "BANK_ACCOUNT_ID":
            sel.append("SUBSTR('ACC'||v_suf,1,60)")
        else:
            sel.append(gen_value(cname, spec, "MTX_USER_BANK_SWEEP_DTLS"))
    out.append(
        f"  BEGIN INSERT INTO ORDERMGMT.MTX_USER_BANK_SWEEP_DTLS ({cnames})\n"
        f"    SELECT {', '.join(sel)} FROM (SELECT USER_ID FROM ORDERMGMT.USERS WHERE ROWNUM = 1) u;\n"
        f"  EXCEPTION WHEN OTHERS THEN NULL; END;"
    )
    out.append("\n  COMMIT;\nEND;\n")
    print("\n".join(out))

    # items_only driver: single full-column INSERT with 6 binds
    icols = extract_table("MTX_TRANSACTION_ITEMS", ITEMS)
    cnames = ", ".join(c[0] for c in icols)
    ivals = ", ".join(items_only_values(icols))
    items_sql = f"""-- Generated: full-column INSERT for HDB_MTX_MODE=items_only (hammerdb-mtx-custom-driver.tcl)
INSERT INTO ORDERMGMT.MTX_TRANSACTION_ITEMS ({cnames})
VALUES ({ivals})
"""
    (ROOT / "hammerdb-mtx-items-only-insert.sql").write_text(items_sql)


if __name__ == "__main__":
    main()
