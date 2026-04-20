# HammerDB → Oracle RAC: connect and run load tests

This ties **HammerDB** on the load client (e.g. **hammerdb** VM) to your **Oracle RAC** service used elsewhere in this PoC.

For a **full production-style guide** (Instant Client, TNS **`LOAD_BALANCE`/`FAILOVER`**, commented TCL, **`gv$`** monitoring, troubleshooting, metrics), see **`HAMMERDB-ORACLE-RAC-TPCC-PRODUCTION-GUIDE.md`**.

For **step-by-step connectivity validation** (ping/`nc`, **`tnsping`**, **`sqlplus`**, **`librarycheck`**, checklist), see **`HAMMERDB-RAC-CONNECTIVITY-VALIDATION.md`**.

**Multitenant (PDB):** In **`tnsnames.ora`**, **`SERVICE_NAME`** must be the **PDB service** (e.g. **`XSTRPDB.<vcn>.oraclevcn.com`**), not only the **database/CDB** service name. Otherwise **`sqlplus`** and HammerDB attach to **`CDB$ROOT`**, and **`CREATE USER tpcc`** fails with **`ORA-65096`**. Confirm with **`SELECT SYS_CONTEXT('USERENV','CON_NAME') FROM DUAL;`** → should show **`XSTRPDB`** (or your PDB), not **`CDB$ROOT`**. The repo example **`hammerdb-tnsnames.rac.example`** uses the PoC PDB service.

**HammerDB TPM high but `racdb.XSTRPDB.TPCC.*` Kafka offsets stay `0`:** This is **not** fixed by Kafka topic creation. DML must be captured by **XStream** for **`TPCC`** (supplemental logging, **`GRANT SELECT`** to **`C##CFLTUSER`**, **outbound rules** per table). Run **`oracle-database/fix-tpcc-xstream-oracle.sh`** (with **`c##xstrmadmin`** / **`ORACLE_PWD`**) and **`verify-tpcc-cdc-prereqs.sql`**. On the **Connect VM**, **`./docker/scripts/diagnose-tpcc-vs-ordermgmt-kafka.sh`** compares ORDERMGMT vs TPCC offsets — if ORDERMGMT grows and TPCC does not, Oracle TPCC capture is missing.

**Password profile:** Default **`tpcc` / `tpcc`** often fails **`ORA-28003`**. Set **`diset tpcc tpcc_pass`** in build and run TCL to match your verifier.

**HammerDB + special characters:** HammerDB issues **`CREATE USER ... IDENTIFIED BY`** with an **unquoted** password (no **`PROFILE`** clause) → **`TPCC`** gets **`DEFAULT`** profile. **`!`** / some symbols break SQL → **`ORA-00922`**. Oracle allows **`$`** in passwords; repo example **`HammerTpcc9912$$`** adds two **`$`** so strict verifiers often pass. If **`TPCC`** already exists, **`DROP USER tpcc CASCADE`** before build, or HammerDB hits **`ORA-01920`**. Optional: DBA profile **`hammerdb_tpcc`** with **`PASSWORD_VERIFY_FUNCTION NULL`** (see **`hammerdb-dba-password-profile.sql`**).

---

## 1. Prerequisites (must all be true)

| Check | What to verify |
|--------|----------------|
| **Network** | From the HammerDB host, TCP **1521** reaches **SCAN** and **RAC VIPs** (listener redirect). See `docs/OCI-HAMMERDB-RAC-1521.md`. |
| **SQL\*Plus** | Same host can connect with the **same service name** you will put in **TNS** (test before HammerDB). |
| **Oracle Instant Client** | Installed (e.g. 19.x RPM); `libclntsh.so` present under `$ORACLE_HOME/lib`. |
| **HammerDB Oracle driver** | HammerDB loads **Oratcl** via **`ORACLE_LIBRARY`** (see [HammerDB Oracle client](https://www.hammerdb.com/docs4.12/ch01s10.html#_oracle_client)). |

---

## 2. Environment variables (every shell that runs HammerDB)

Source the helper (adjust paths if your Instant Client version differs):

```bash
source ~/oracle-xstream-cdc-poc/oracle-database/hammerdb-oracle-env.sh
```

Or set manually:

| Variable | Example (Instant Client 19.29) |
|----------|--------------------------------|
| `ORACLE_HOME` | `/usr/lib/oracle/19.29/client64` |
| `LD_LIBRARY_PATH` | `$ORACLE_HOME/lib` |
| `ORACLE_LIBRARY` | `$ORACLE_HOME/lib/libclntsh.so` |
| `TNS_ADMIN` | `$HOME/oracle/network/admin` |
| `PATH` | `/opt/HammerDB-5.0:$PATH` |
| `TMP` | `/tmp` (run sample writes `$TMP/ora_tprocc`; set if unset) |

Verify Oracle client library:

```bash
ls -la "$ORACLE_HOME/lib/libclntsh.so"
```

---

## 3. TNS name for RAC (recommended)

HammerDB’s **`diset connection instance`** value is the **Oracle net service name** — usually a **TNS alias** resolved via **`tnsnames.ora`** (same pattern as `sqlplus user/pass@ALIAS`).

1. Copy the example and edit **HOST**, **PORT**, **SERVICE_NAME** to match your RAC (use **SCAN** host and your **DB service name**):

   ```bash
   mkdir -p ~/oracle/network/admin
   cp oracle-xstream-cdc-poc/oracle-database/hammerdb-tnsnames.rac.example \
      ~/oracle/network/admin/tnsnames.ora
   # Edit tnsnames.ora
   ```

2. Test with SQL\*Plus (same user/password you will give HammerDB):

   ```bash
   export TNS_ADMIN=$HOME/oracle/network/admin
   sqlplus system@RAC_XSTRPDB_POC   # or your alias / credentials
   ```

PoC-style **SCAN** and **service** (adjust if yours differ):

- **SCAN host:** `racdb-scan.sub01061249390.xstrmconnectdb2.oraclevcn.com`
- **Service name:** `DB0312_r8n_phx.sub01061249390.xstrmconnectdb2.oraclevcn.com`

---

## 4. Database user for TPROC-C (HammerDB default)

Default scripts use **`SYSTEM`** / **`manager`**. In production you should:

- Use a dedicated user with privileges to **create users/tablespaces** for the TPC-C schema, **or**
- Pre-create the **`tpcc`** user and tablespace per HammerDB docs, and align **`tpcc_user`** / **`tpcc_pass`** in `oracle.xml` or `diset`.

If **`SYSTEM`** is locked, unlock it or switch **`system_user`** / **`system_password`** in your TCL script to a suitable DBA-capable account.

---

## 5. CLI: configure and run (TPROC-C)

HammerDB is driven with **TCL** and **`diset`** (dictionary set). Upstream examples live in the HammerDB install tree:

- `scripts/tcl/oracle/tprocc/ora_tprocc_buildschema.tcl`
- `scripts/tcl/oracle/tprocc/ora_tprocc_run.tcl`

Typical flow:

1. `dbset db ora` and `dbset bm TPC-C`
2. `diset connection system_user` / `system_password` / **`instance`** = your **TNS alias** (e.g. `RAC_XSTRPDB_POC`)
3. **`buildschema`** (once)
4. **`loadscript`**, then virtual users: **`vuset`**, **`vucreate`**, **`tcstart`**, **`vurun`**, **`vudestroy`**, **`tcstop`** (see upstream `ora_tprocc_run.tcl`)

**Non-interactive** mode (no TTY):

```bash
source ~/oracle-xstream-cdc-poc/oracle-database/hammerdb-oracle-env.sh
hammerdbcli tcl auto /path/to/your-script.tcl
```

Copy and edit the repo samples (RAC-oriented):

- `oracle-database/hammerdb-tprocc-buildschema-sample.tcl`
- `oracle-database/hammerdb-tprocc-run-sample.tcl`

Replace **`CHANGE_ME`** placeholders and passwords. The run sample writes job id to **`$TMP/ora_tprocc`** like the stock script.

---

## 6. GUI (optional)

With X11 or desktop:

```bash
/opt/HammerDB-5.0/hammerdb
```

Select **Oracle**, **TPROC-C**, set **connection** to your TNS alias, then build schema and run the driver.

---

## 7. Troubleshooting

| Symptom | What to check |
|---------|----------------|
| `ORA-12543` / unreachable | OCI rules: **SCAN + VIP**, source = HammerDB IP. Not only SCAN. |
| Oratcl / `libclntsh` errors | `ORACLE_LIBRARY`, `LD_LIBRARY_PATH`, `ORACLE_HOME`. |
| `ORA-12154` TNS could not resolve | `TNS_ADMIN`, `tnsnames.ora`, alias spelling vs `diset connection instance`. |
| Auth errors | User/password; **`SYSTEM`** unlocked or alternate admin user. |

---

## 8. TPC-C data in Oracle but **no Kafka messages** (CDC)

### Why every TPCC topic shows end offset `0`

| Cause | What to do |
|--------|------------|
| **`snapshot.mode=no_data`** (default) | Kafka only gets **changes that happen after** streaming is configured — **not** rows that already existed. Offsets stay `0` until the **first** CDC event per topic. |
| **No DML yet** | Run `run-tpcc-cdc-smoke-test.sh` or `run-tpcc-cdc-sample-inserts.sh` as **`TPCC`** on a host with `sqlplus` to the PDB. |
| **Oracle XStream not capturing TPCC** | Supplemental log, **`GRANT SELECT`** to `C##CFLTUSER`, and **outbound rules** for all nine tables — `fix-tpcc-xstream-oracle.sh` + `verify-tpcc-cdc-prereqs.sql`. |
| **Need existing rows in Kafka without new DML** | **`snapshot.mode=initial`** — if Connect logs show **`Snapshot SKIPPED`**, offsets already say “snapshot done”; you must **`connector-recreate-full-snapshot.sh`** (see **§8.3**). |

**On the Connect VM** — diagnose + optional backfill attempt:

```bash
./docker/scripts/remediate-tpcc-zero-offsets.sh
APPLY_INITIAL=yes ./docker/scripts/remediate-tpcc-zero-offsets.sh
```

Having rows in `TPCC.*` does **not** automatically fill Kafka topics. You need **all** of the following:

**Stop an active HammerDB load** (before changing XStream rules, if you want a clean cutover):

```bash
cd oracle-xstream-cdc-poc/oracle-database && ./stop-hammerdb-load.sh
```

**Connection strings for `sqlplus`:** use the **same PDB service** as HammerDB. Set `TNS_ADMIN` to your `tnsnames.ora` directory and use the **TNS alias** (default in scripts: `RAC_XSTRPDB_POC`). **Do not** use `//localhost:1521/XSTRPDB` from a remote host — that only works on the database server itself.

**Password:** `ORACLE_PWD` for `hammerdb-tpcc-onboard-xstream.sh` / `fix-tpcc-xstream-oracle.sh` must be **`c##xstrmadmin`** (XStream admin). It is **not** the same as `c##cfltuser` (Kafka connector) or `SYSTEM` / `tpcc`. Copy `oracle-database/xstream-admin.env.example` to `xstream-admin.env`, set `ORACLE_PWD`, and `source` it before running those scripts.

**Bash gotcha:** the default user must be written as `: "${ORACLE_USER:="c##xstrmadmin"}"` (quoted). If unquoted (`:=c##xstrmadmin`), bash treats `#` as a comment and the user becomes `c`, causing `ORA-01017`.

**Remote `sqlplus … as sysdba`:** if `c##xstrmadmin/password@tns as sysdba` fails while the same password works without `as sysdba`, grant `SYSDBA` to `c##xstrmadmin` as SYS (`GRANT SYSDBA TO c##xstrmadmin CONTAINER=ALL;`) so the account is in the password file. Oracle may also refuse to reuse an old password (`ORA-28007`); pick a new strong password that satisfies `PASSWORD_VERIFY_FUNCTION`.

**All-in-one Oracle fix** (after exporting `ORACLE_PWD` for `c##xstrmadmin`):

```bash
source oracle-database/hammerdb-oracle-env.sh
export ORACLE_PWD='<c##xstrmadmin password>'
cd oracle-database && ./fix-tpcc-xstream-oracle.sh
```

| Step | What |
|------|------|
| 1 | **Supplemental logging + GRANT SELECT** — run `oracle-database/hammerdb-tpcc-onboard-xstream.sql` (SYSDBA in PDB `XSTRPDB`). |
| 2 | **XStream capture/outbound rules** — run `oracle-database/hammerdb-tpcc-onboard-xstream.sh` (calls `11-add-table-to-cdc.sql` per table). Watch for ORA errors (script no longer hides failures silently). |
| 3 | **Connector** — `table.include.list` must include `TPCC\.(DISTRICT|…|ORDER_LINE)`; sync from `xstream-connector/oracle-xstream-rac-docker.json.example` or run `docker/scripts/connector-ensure-tpcc-onboard.sh` **on the Connect VM**. Validate: `docker/scripts/validate-tpcc-cdc-pipeline.sh`. |
| 4 | **Streaming only (default in repo)** — Connector uses **`snapshot.mode=no_data`**: **no** initial snapshot of existing rows; only **new** changes after capture/connect are streamed to Kafka. To see traffic, run HammerDB (or other DML) **after** Oracle XStream rules and the connector are in place. To backfill historical rows use **`snapshot.mode=initial`**: `./docker/scripts/connector-apply-initial-snapshot.sh` or full recreate (**§8.3**). To force **`no_data`** again: `./docker/scripts/connector-apply-streaming-only.sh`. |

**Verify Oracle side:**

```bash
sqlplus sys/...@//SCAN:1521/SERVICE as sysdba @oracle-database/verify-tpcc-cdc-prereqs.sql
```

You should see supplemental log rows, `SELECT` grants to `C##CFLTUSER`, and **DBA_XSTREAM_RULES** rows for `TPCC` tables.

### 8.1 Imports / bulk load but **no** Kafka messages

| Situation | Why topics stay empty |
|-----------|------------------------|
| **`snapshot.mode=no_data`** (default) | Existing rows from import are **not** emitted. Only **changes after** the connector is streaming appear in Kafka (unless you switch to `snapshot.mode=initial` and re-snapshot). |
| **Import before supplemental log + XStream rules** | Historical rows loaded earlier are not replayed. Fix Oracle CDC prereqs, then run **new** DML (below). |
| **`impdp` / direct-path SQL\*Loader** | Depending on options, redo can differ from conventional inserts. After onboarding TPCC to XStream, run the **smoke test** to confirm CDC with controlled DML. |
| **Connector / `table.include.list`** | If `TPCC` tables were not in the connector when you expected, imports still do not retroactively appear under `no_data`. |

### 8.2 Smoke-test DML (touches all 9 `TPCC` tables)

After XStream rules, grants, connector **RUNNING**, and `TPCC` in `table.include.list`, run **`oracle-database/tpcc-cdc-smoke-test.sql`** as the **`TPCC`** user (same password as HammerDB). It issues a small **UPDATE** on each table (and a **delete+insert** on `NEW_ORDER`, which is key-only) so each table produces **fresh redo** for XStream.

```bash
cd oracle-xstream-cdc-poc/oracle-database
export TPCC_PASSWORD='<TPCC user password>'
source ./hammerdb-oracle-env.sh
./run-tpcc-cdc-smoke-test.sh
```

On the Kafka Connect VM, within about one to two minutes:

```bash
./docker/scripts/validate-tpcc-cdc-pipeline.sh
# or: kafka-get-offsets per topic (see docs/STATUS-CHECK.md)
```

If **`ORA-00904` (invalid column)** appears, your HammerDB build may use slightly different column names — compare with `DESC TPCC.ORDERS` etc. and adjust `tpcc-cdc-smoke-test.sql` locally.

**Sample INSERTs (streaming mode):** `oracle-database/tpcc-cdc-sample-inserts.sql` adds a **new warehouse** (`W_ID = MAX+1`) and related rows in FK order (district, customer, new item, stock, order, new_order, order_line, history). Run:

```bash
cd oracle-xstream-cdc-poc/oracle-database
export TPCC_PASSWORD='<TPCC user password>'
source ./hammerdb-oracle-env.sh
./run-tpcc-cdc-sample-inserts.sh
```

On the **Kafka Connect VM** (after ~1–2 minutes for XStream + Connect lag):

```bash
cd ~/oracle-xstream-cdc-poc
./docker/scripts/check-tpcc-kafka-offsets.sh
```

Expect **non-zero** end offsets for topics that received CDC events (often all nine). To consume a sample message: `docker exec -e KAFKA_OPTS= kafka1 kafka-console-consumer ...` (see `docs/STATUS-CHECK.md` §2.4).

### 8.3 Backfill imported rows to Kafka (`snapshot.mode=initial`)

**If `docker logs connect` shows `SnapshotResult [status=SKIPPED]`** after you set `snapshot.mode=initial`: the connector’s **offset** already marks a snapshot as **completed** (often from an earlier run **before** `TPCC` was in `table.include.list`). A REST **PUT** does **not** clear that — the snapshot is skipped and TPCC topics stay at offset `0`.

**Fix:** delete and recreate the connector so offsets reset, with **`"snapshot.mode": "initial"`** in the JSON you POST:

```bash
# 1) Edit your deployed JSON (e.g. xstream-connector/oracle-xstream-rac-docker.json)
#    Ensure "snapshot.mode": "initial" and TPCC is in table.include.list.
# 2) On Connect VM:
CONFIRM=yes ./docker/scripts/connector-recreate-full-snapshot.sh
```

Use this when **`no_data`** was correct for streaming-only tests but you now need **existing** `TPCC` (and other included) rows **emitted** to topics — for example after a bulk import.

**Step A — try without deleting the connector** (on the Connect VM):

```bash
cd ~/oracle-xstream-cdc-poc
./docker/scripts/connector-apply-initial-snapshot.sh
```

This **PUT**s `snapshot.mode=initial` and **restarts** the connector. If Connect offsets were already committed while the connector was in `no_data`, **you may still see no backfill**; then use Step B.

**Step B — full re-snapshot (clears connector state; slow; all tables in `table.include.list`)**

1. Edit your deployed connector JSON (e.g. `xstream-connector/oracle-xstream-rac-docker.json`) so **`"snapshot.mode": "initial"`** (not `no_data`).
2. Run:

```bash
CONFIRM=yes ./docker/scripts/connector-recreate-full-snapshot.sh
```

This **DELETE**s the connector and **POST**s from the JSON file, so Connect offsets reset and an initial snapshot can run for every included table. **`connector-recreate-full-snapshot.sh`** warns if the JSON still has `no_data`.

**When stable again**, return to streaming-only if you want:

```bash
./docker/scripts/connector-apply-streaming-only.sh
```

---

## 9. References

- [HammerDB — Verifying database client libraries (Oracle)](https://www.hammerdb.com/docs4.12/ch01s10.html#_oracle_client)
- [HammerDB — TPROC-C workload](https://www.hammerdb.com/docs4.12/ch04.html)
- Sample scripts: `oracle-database/hammerdb-*.tcl` in this repo
