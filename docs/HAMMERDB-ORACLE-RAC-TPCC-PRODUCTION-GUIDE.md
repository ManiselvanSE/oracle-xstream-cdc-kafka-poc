# HammerDB + Oracle RAC 19c+ — Production TPC-C Benchmarking Guide

This document is written for **Oracle performance engineers** running **HammerDB** against **Oracle RAC** using the **CLI** (`hammerdbcli`). It covers environment setup, **TNS** for RAC/SCAN, schema build, load generation, RAC best practices, monitoring, troubleshooting, and metrics.

**Assumptions:** Load driver on **Linux**, database **Oracle RAC 19c or later**, **HammerDB 4.x/5.x** with Oracle workload support.

---

## Table of contents

1. [Environment setup](#1-environment-setup)  
2. [Oracle RAC connectivity](#2-oracle-rac-connectivity)  
3. [HammerDB configuration](#3-hammerdb-configuration)  
4. [Schema build (TPC-C)](#4-schema-build-tpc-c)  
5. [Load generation](#5-load-generation)  
6. [RAC-specific best practices](#6-rac-specific-best-practices)  
7. [Monitoring and validation](#7-monitoring-and-validation)  
8. [Troubleshooting](#8-troubleshooting)  
9. [Output and metrics](#9-output-and-metrics)  

Related repo files:

| File | Purpose |
|------|---------|
| `oracle-database/hammerdb-oracle-env.sh` | Client env (`ORACLE_*`, `TNS_ADMIN`, `PATH`) |
| `oracle-database/hammerdb-tnsnames.rac.production.example` | RAC TNS templates (SCAN + multi-address) |
| `oracle-database/hammerdb-tprocc-buildschema-production.tcl` | TPC-C schema build (**TPCC** user / tables) |
| `oracle-database/hammerdb-tprocc-run-production.tcl` | **ORDERMGMT.MTX\*** load only (sources MTX runner; **not** TPROC-C / TPCC) |
| `oracle-database/hammerdb-mtx-run-production.sh` | Recommended entry point for MTX CDC load (same as row above) |
| `oracle-database/hammerdb-rac-monitoring.sql` | `gv$*` sample queries |
| `docs/HAMMERDB-RAC-CONNECTIVITY-VALIDATION.md` | Pre-flight checks: network, TNS, **sqlplus**, **`librarycheck`** |
| `oracle-database/hammerdb-connection-sanity.tcl` | Minimal HammerDB **`print dict`** sanity script |
| `oracle-database/hammerdb-cli-librarycheck.sh` | Non-interactive **`librarycheck`** |

---

## 1. Environment setup

### 1.1 Oracle Instant Client (Linux)

Use **RPM** packages from Oracle (match your OS: RHEL/OL 8/9, x86_64). Typical packages:

- `oracle-instantclient19.*-basic-*.rpm` (or `basiclite`)
- `oracle-instantclient19.*-sqlplus-*.rpm` (optional but recommended for tests)
- `oracle-instantclient19.*-tools-*.rpm` (includes `tnsping` if available for your version)

**Example (OL/RHEL 9, adjust version URLs):**

```bash
sudo mkdir -p /opt/oracle/pkg
cd /opt/oracle/pkg
# Download from https://www.oracle.com/database/technologies/instant-client/linux-x86-64-downloads.html
sudo dnf install -y oracle-instantclient19.*-basic-*.rpm \
                     oracle-instantclient19.*-sqlplus-*.rpm \
                     oracle-instantclient19.*-tools-*.rpm
```

After install, **`ORACLE_HOME`** is usually:

```text
/usr/lib/oracle/19.<minor>/client64
```

Confirm:

```bash
rpm -qa | grep -i instantclient
ls -la /usr/lib/oracle/*/client64/lib/libclntsh.so
```

**Why Basic vs Basic Lite:** Basic includes more NLS/data; Basic Lite is smaller. For benchmarking, **Basic** is typical.

### 1.2 Required environment variables

HammerDB’s Oracle driver loads **`libclntsh.so`** via **`ORACLE_LIBRARY`** (Instant Client has no full server `$ORACLE_HOME` layout).

| Variable | Purpose |
|----------|---------|
| **`ORACLE_HOME`** | Root of Instant Client install (e.g. `/usr/lib/oracle/19.29/client64`). |
| **`LD_LIBRARY_PATH`** | Must include `$ORACLE_HOME/lib` so `libclntsh.so` resolves. |
| **`ORACLE_LIBRARY`** | **Full path** to `libclntsh.so` — HammerDB/Oratcl uses this explicitly. |
| **`TNS_ADMIN`** | Directory containing **`tnsnames.ora`** (and optionally **`sqlnet.ora`**). |
| **`PATH`** | Include HammerDB binaries, e.g. `/opt/HammerDB-5.0`. |
| **`TMP` / `TEMP`** | Some TCL run scripts write job metadata under `$TMP`. |

**Source the repo helper** (edit `ORACLE_HOME` if your minor version differs):

```bash
source /path/to/oracle-xstream-cdc-poc/oracle-database/hammerdb-oracle-env.sh
```

**Manual equivalent:**

```bash
export ORACLE_HOME=/usr/lib/oracle/19.29/client64
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH
export ORACLE_LIBRARY=$ORACLE_HOME/lib/libclntsh.so
export TNS_ADMIN=$HOME/oracle/network/admin
export PATH=/opt/HammerDB-5.0:$PATH
export TMP=${TMP:-/tmp}
```

Verify:

```bash
ls -la "$ORACLE_LIBRARY"
ldd "$ORACLE_LIBRARY" | head
```

### 1.3 HammerDB installation and setup

**Install (example: RPM for EL9):**

```bash
cd /tmp
curl -fsSL -O https://github.com/TPC-Council/HammerDB/releases/download/v5.0/hammerdb-5.0-1.el9.x86_64.rpm
sudo dnf install -y ./hammerdb-5.0-1.el9.x86_64.rpm
```

Locations:

| Component | Path |
|-----------|------|
| CLI | `/opt/HammerDB-5.0/hammerdbcli` |
| GUI | `/opt/HammerDB-5.0/hammerdb` |
| Upstream TCL examples | `/opt/HammerDB-5.0/scripts/tcl/oracle/tprocc/` |

```bash
hammerdbcli -v
```

**Non-interactive runs** (no TTY):

```bash
hammerdbcli tcl auto /path/to/script.tcl
```

See also: `docs/HAMMERDB-INSTALL.md`.

---

## 2. Oracle RAC connectivity

### 2.1 SCAN vs node (VIP) connections

| Concept | Role |
|---------|------|
| **SCAN** (Single Client Access Name) | DNS name resolving to **typically three** SCAN VIPs. Listeners on SCAN receive connection requests; the cluster **redirects** the client to a **local listener** on a **node VIP** for the chosen instance. |
| **Node VIP** | Per-node address; after redirect, the client often connects to **host:1521** on a VIP (not necessarily SCAN). |
| **Firewall / NSG** | Must allow **1521** from the load host to **SCAN endpoints and all RAC node VIPs** used by listeners, or you see **`ORA-12543`** / **TNS-12543** after redirect. |

**Implication for HammerDB:** The **TNS** string uses **`SERVICE_NAME`** (and optionally **LOAD_BALANCE**). The client does not “pick a node” manually; **Oracle Net + SCAN + service** decide instance placement. **Do not** use **`SID=`** for a RAC service workload unless you intentionally target one instance (not recommended for distributed load testing).

### 2.2 `tnsnames.ora` — production-style RAC entries

Use **`SERVICE_NAME`**, not **`SID`**, for service-based RAC workloads.

Copy and edit: `oracle-database/hammerdb-tnsnames.rac.production.example`.

**Pattern A — SCAN only (common, recommended):**

Single **ADDRESS** with **SCAN hostname**; **`LOAD_BALANCE`** at description level; **`CONNECT_DATA`** uses **`SERVICE_NAME`**.

**Pattern B — Multiple addresses (SCAN VIPs or node VIPs):**

Use **`ADDRESS_LIST`** with **`LOAD_BALANCE = on`** and **`FAILOVER = on`** so Net Services tries addresses in a balanced/failover-friendly way. You can list **three SCAN IPs** (if static) or **node VIPs** — coordinate with your DBA for the official list.

Example skeleton (replace hosts, ports, service name):

```text
RAC_TPCH_SERVICE =
  (DESCRIPTION =
    (LOAD_BALANCE = yes)
    (ADDRESS_LIST =
      (LOAD_BALANCE = on)
      (FAILOVER = on)
      (ADDRESS = (PROTOCOL = TCP)(HOST = rac-scan.example.com)(PORT = 1521))
      (ADDRESS = (PROTOCOL = TCP)(HOST = node1-vip.example.com)(PORT = 1521))
      (ADDRESS = (PROTOCOL = TCP)(HOST = node2-vip.example.com)(PORT = 1521))
    )
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = your.cdb.or.pdb.service.name)
    )
  )
```

**Notes:**

- **`LOAD_BALANCE = yes`** (description) / **`LOAD_BALANCE = on`** (list): spreads new connections across **addresses** in the list. With a **single SCAN host** resolving to multiple IPs, a **single ADDRESS** line is often enough; multi-address lists help when listing explicit VIPs.
- **`FAILOVER = on`**: Helps connection-time failover across **ADDRESS** entries when a target is unreachable (details depend on topology; work with Net/DBA for MAA setups).
- **Service-level load balancing** (preferred for “which instance”): Configure the **database service** with **`-rlbgoal SERVICE_TIME`** (or **`THROUGHPUT`**) and **`-clbgoal SHORT`** as appropriate (`srvctl modify service ...`). That affects **which instance** serves **new** sessions for that service — complementary to client-side TNS load balancing.

Place files:

```bash
mkdir -p $HOME/oracle/network/admin
# cp hammerdb-tnsnames.rac.production.example $HOME/oracle/network/admin/tnsnames.ora
export TNS_ADMIN=$HOME/oracle/network/admin
```

Optional **`sqlnet.ora`** (example):

```text
# sqlnet.ora
SQLNET.AUTHENTICATION_SERVICES = (NONE)
NAMES.DIRECTORY_PATH = (TNSNAMES, EZCONNECT)
```

### 2.3 Test connectivity: `tnsping` and `sqlplus`

```bash
export TNS_ADMIN=$HOME/oracle/network/admin
tnsping RAC_TPCH_SERVICE
```

Expect **`OK`** and latency in milliseconds.

```bash
sqlplus -L system@RAC_TPCH_SERVICE
-- Or: sqlplus -L 'system@"RAC_TPCH_SERVICE"'
```

If **`sqlplus` fails, HammerDB will fail** — fix TNS/network first.

---

## 3. HammerDB configuration

### 3.1 Selecting Oracle and TPC-C

**GUI:** Start `hammerdb` → **Benchmark** → **TPC-C** → **Oracle** (wording may vary slightly by version).

**CLI/TCL:**

```tcl
dbset db ora          # Oracle database target
dbset bm TPC-C        # Benchmark = TPC-C (TPROC-C workload)
```

### 3.2 Connection parameters (`diset connection ...`)

| Parameter | Meaning |
|-----------|---------|
| **`system_user`** | Privileged user used to **create/drop** TPC-C schema objects (default docs often use **`SYSTEM`**). **Not** `SYS AS SYSDBA` in typical HammerDB flows — use **`SYSTEM`** or another user with **adequate quotas/privileges**. |
| **`system_password`** | Password for **`system_user`**. |
| **`instance`** | **Oracle Net service name** — the **`tnsnames.ora` alias** (e.g. `RAC_TPCH_SERVICE`). This is **not** the DB unique name; it must match **`sqlplus user@alias`**. |

```tcl
diset connection system_user SYSTEM
diset connection system_password <secure_password>
diset connection instance RAC_TPCH_SERVICE
```

### 3.3 TPC-C / workload parameters (overview)

| Group | Examples | Meaning |
|-------|------------|---------|
| **Scale** | `count_ware`, `num_vu` | **Warehouses** (data volume) and **virtual users** used during **schema build** (parallelism). |
| **TP/CC user** | `tpcc_user`, `tpcc_pass` | Application schema owner HammerDB creates (`tpcc` by default). |
| **Tablespaces** | `tpcc_def_tab`, `tpcc_def_temp`, `tpcc_ol_tab` | Default **permanent/temp** tablespace names for data/indexes (must exist or be creatable per your script/version). |
| **RAC / size** | `partition`, `hash_clusters` | Often enabled for **large** warehouse counts (see HammerDB docs). |

Exact **`diset`** names match your HammerDB version; use **`print dict`** in CLI or check **`config/oracle.xml`**.

---

## 4. Schema build (TPC-C)

### 4.1 GUI steps (summary)

1. Load Oracle + TPC-C as above.  
2. Set **connection** (user/password/**instance** = TNS alias).  
3. Set **warehouses** and **virtual users** for build.  
4. Ensure **tablespace** targets exist if you do not use defaults (DBA may create **`USERS`**, **`TEMP`**, large **TPC** tablespace on **ASM**).  
5. Run **Build / Schema** and wait for completion (can take long for large warehouse counts).

### 4.2 TCL script (schema build)

Use the repo script **`hammerdb-tprocc-buildschema-production.tcl`** — it mirrors upstream **`ora_tprocc_buildschema.tcl`** with comments.

**Warehouses — scaling strategy:**

- **More warehouses** → more data, longer build, larger storage.  
- Rule of thumb: start small (**4–16** warehouses) to validate end-to-end; scale to target **dataset** size.  
- **`num_vu`**: Parallel build threads; often aligned with **CPU cores** on the **load client** (not unlimited — too many VUs can overwhelm a single client or DB if small).

**Tablespaces (optional, DBA):**

Create dedicated tablespaces on shared storage (e.g. **`+DATA`**) before large builds:

```sql
CREATE BIGFILE TABLESPACE TPCCTAB DATAFILE '+DATA' SIZE 100G AUTOEXTEND ON NEXT 1G MAXSIZE UNLIMITED;
```

Then map HammerDB **`tpcc_*_tab`** settings to those names **if** your version exposes them (confirm with `print dict`).

### 4.3 RAC / parallel build considerations

- **Parallel build** is **client-driven** (`num_vu`), not “RAC parallel DML” by default — heavy DDL can stress **one node** depending on where sessions land.  
- Use a **uniform service** with **load balancing** so multiple build sessions can spread (validate with **`gv$session`**).  
- For very large builds, coordinate with DBA on **redo**, **archive**, and **UNDO** sizing.

---

## 5. Load generation

### 5.1 Production script in this repo (ORDERMGMT.MTX* only — no TPCC)

For **XStream CDC** load testing, **`hammerdb-tprocc-run-production.tcl`** does **not** run the TPC-C / TPROC-C workload against the **TPCC** schema. It **`source`s `hammerdb-mtx-transaction-items-run.tcl`**, which uses **`hammerdb-mtx-custom-driver.tcl`** to insert only into **ORDERMGMT** tables whose names start with **MTX** (see `hammerdb-mtx-multitable-wave.sql`).

Use **`./hammerdb-mtx-run-production.sh`** (or `hammerdbcli tcl auto hammerdb-tprocc-run-production.tcl`) with **`HDB_MTX_PASS`** set. Do **not** expect TPM/NOPM from the TPC-C timed driver here.

### 5.2 Classic TPC-C TPROC-C run (TPCC schema)

To run the standard **HammerDB TPROC-C** workload (**TPCC.WAREHOUSE**, **TPCC.STOCK**, …), use **`hammerdb-tprocc-run-sample.tcl`** as a template, or the upstream **`ora_tprocc_run.tcl`** from the HammerDB install. That path requires **`hammerdb-tprocc-buildschema-production.tcl`** (or equivalent) to create the **TPCC** user and tables.

**Typical TPROC-C timed driver parameters** (for a **real** TPROC-C `.tcl`, not the MTX alias above):

| `diset` | Typical meaning |
|---------|-----------------|
| **`rampup`** | Seconds to ramp to full load before measurement. |
| **`duration`** | Measured run length (seconds) for **timed** driver. |
| **`ora_driver`** | Use **`timed`** for steady-state TPM-style runs. |

### 5.3 Virtual users and ramp-up

```tcl
vuset vu vcpu    # One VU per logical CPU on load generator (adjust: vu 32, etc.)
```

Tune **`rampup`** so caches warm and RAC stabilizes before relying on **`duration`** numbers.

---

## 6. RAC-specific best practices

### 6.1 Distributing load across nodes

1. **Connect using a **cluster-managed service** `SERVICE_NAME`** (not **`SID`**) so connections can land on multiple instances per service policy.  
2. **Server-side**: `srvctl` service attributes (**`-rlbgoal`**, **`-clbgoal`**, **`CARDINALITY`**) — work with DBA.  
3. **Client-side**: **`LOAD_BALANCE`** in **`tnsnames.ora`** spreads across listed addresses.  
4. **Validate** with **`gv$session`** during the test (see §7).

### 6.2 Services and load balancing

- **Application services** in RAC are the **correct** abstraction for workload isolation and **instance affinity** / **load balancing**.  
- A **single-instance SID-style** connection bypasses multi-instance balancing for that connection string.

### 6.3 Virtual users vs RAC nodes

- **VUs** are **client-side threads** — not 1:1 with RAC nodes.  
- **More VUs** increase concurrency until CPU on **client** or **database** saturates.  
- Start with **`vuset vu vcpu`** or a fixed **`vu`** (e.g. 2× node count) and increase until **response time** or **CPU** caps.

### 6.4 Common mistakes

| Mistake | Effect |
|---------|--------|
| **`SID=`** instead of **`SERVICE_NAME`** | May pin to one instance or break RAC expectations. |
| **Firewall only to SCAN** | **ORA-12543** after redirect to VIP. |
| **Huge warehouses on first run** | Long failures; always **pilot small**. |
| **Ignoring redo/undo** | **`ORA-30036`**, log writer waits under load. |

---

## 7. Monitoring and validation

Run on **any** RAC node (or PDB container) as a user with **`SELECT_CATALOG_ROLE`** (or **`GV$`**) privileges.

Script: **`oracle-database/hammerdb-rac-monitoring.sql`**.

### 7.1 `gv$session` — who is connected where

```sql
-- Sessions by instance for your TPC-C user
SELECT inst_id, username, status, COUNT(*) cnt
FROM   gv$session
WHERE  username = 'TPCC'
GROUP BY inst_id, username, status
ORDER BY inst_id;
```

**Interpretation:** Non-zero counts on **multiple `inst_id`** values indicate **multi-instance** work (for connection-heavy workloads; single long-running queries may still concentrate).

### 7.2 `gv$active_session_history` — activity over time (if licensed)

```sql
SELECT inst_id, event, COUNT(*) samples
FROM   gv$active_session_history
WHERE  sample_time > SYSDATE - (10/1440)
  AND  user_id = (SELECT user_id FROM dba_users WHERE username = 'TPCC')
GROUP BY inst_id, event
ORDER BY samples DESC;
```

**Note:** **ASH** requires **Diagnostic Pack** license on production; on lab systems confirm policy.

### 7.3 `gv$sql` / `gv$sqlarea` — SQL footprint

```sql
SELECT inst_id, sql_id, substr(sql_text,1,80) txt, executions, elapsed_time
FROM   gv$sql
WHERE  sql_text LIKE '%TPCC%' OR sql_text LIKE '%NEWORD%'
ORDER BY elapsed_time DESC
FETCH FIRST 20 ROWS ONLY;
```

Use to confirm **TPC-C statement mix** and **which instances** executed work.

---

## 8. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|----------------|-----|
| **ORA-12154** | No TNS alias / wrong **`TNS_ADMIN`** | Export **`TNS_ADMIN`**, verify **`tnsnames.ora`** name matches **`diset connection instance`**. |
| **ORA-12514** | Wrong **service** / listener | **`SERVICE_NAME`** must match **`srvctl config service`**. |
| **ORA-12543** / **TNS-12543** | Blocked path to VIP after SCAN redirect | Open **1521** to **SCAN + node VIPs** from client. |
| **`libclntsh` / Oratcl errors** | Bad Instant Client path | **`ORACLE_LIBRARY`**, **`LD_LIBRARY_PATH`**. |
| **Load on one node only** | **SID** connect string, or **service** affinity | Use **`SERVICE_NAME`**, review **`srvctl`** service attributes. |
| **HammerDB auth failure** | Wrong **`system_user`** / locked **SYSTEM** | Unlock or use privileged alternate per policy. |

---

## 9. Output and metrics

### 9.1 TPM and HammerDB metrics

- HammerDB reports **TPM** (transactions per minute) and **NOPM** (new orders per minute) in the **console output** and **timing** windows after **`vurun`** completes (exact labels depend on version).  
- **Timed** driver (`ora_driver timed`) with **`duration`** defines the **measurement window** after **ramp-up**.

### 9.2 Logs

- CLI output is **stdout/stderr** — redirect:

```bash
hammerdbcli tcl auto run.tcl 2>&1 | tee hammerdb_run_$(date +%Y%m%d_%H%M%S).log
```

- Some scripts write **job id** to **`$TMP/ora_tprocc`** (upstream pattern).  
- Optional: HammerDB **GUI** or **ws** may offer additional logging — see installed version docs.

### 9.3 Interpreting results

- **Higher TPM/NOPM** with stable **response time** and **acceptable DB CPU** → good throughput.  
- **High waits** in **`gv$session`/`ASH`** (e.g. **log file sync**, **buffer busy**) → storage/redo tuning, not “more VUs”.  
- Compare **before/after** with **same warehouse count** and **duration** for fair A/B tests.

---

## Quick start checklist

1. Install **Instant Client** + set **`ORACLE_*`** + **`ORACLE_LIBRARY`**.  
2. Install **HammerDB**, add **`PATH`**.  
3. Deploy **`tnsnames.ora`** (**`SERVICE_NAME`**, **`LOAD_BALANCE`**, **`FAILOVER`** as needed).  
4. **`tnsping`** + **`sqlplus`** succeed.  
5. **TPC-C / TPCC benchmark only:** run **`hammerdb-tprocc-buildschema-production.tcl`**, then a TPROC-C script such as **`hammerdb-tprocc-run-sample.tcl`**.  
6. **ORDERMGMT.MTX* CDC load (no TPCC):** run **`./hammerdb-mtx-run-production.sh`** with **`HDB_MTX_PASS`** (or **`hammerdbcli tcl auto hammerdb-tprocc-run-production.tcl`** — same MTX workload).  
7. Validate **`gv$session`** distribution; tune **service** and **VU** count.

---

## References

- [HammerDB documentation — Oracle / TPROC-C](https://www.hammerdb.com/docs/)  
- Oracle **Net Services** reference: **SCAN**, **`tnsnames.ora`**, **`LOAD_BALANCE`**, **`FAILOVER`**  
- Upstream TCL: `/opt/HammerDB-5.0/scripts/tcl/oracle/tprocc/`
