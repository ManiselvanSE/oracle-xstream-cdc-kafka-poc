# MTX high-volume load: how the scripts work, how scale is achieved, and how this relates to CDC latency

This document describes **exactly what is in this repository** for the HammerDB MTX load path, how row volume arises, and how that load relates to the **Kafka / XStream CDC path** (including the **~200 ms end-to-end latency profile** called out in `docs/performance-results.md`). It is written so a customer can reproduce the **mechanics** on their own environment; **absolute row counts and latency numbers will vary** with hardware, Oracle tuning, network, and Kafka sizing.

---

## 1. What “14M rows” means in this PoC

- The load generators in `oracle-database/` **do not contain a constant that targets exactly 14,019,801 rows**.
- Row totals are an **emergent outcome** of:
  - how many **virtual users (VUs)** HammerDB runs,
  - how long the run lasts (**time-bound** vs **iteration-bound**),
  - how fast Oracle accepts **one INSERT per VU per loop iteration** in `HDB_MTX_MODE=items_only`,
  - and whether the run was stopped early (manual stop, errors suppressed when `HDB_MTX_RAISEERROR=false`, resource limits, etc.).
- A field PoC documented **~14M rows** into `ORDERMGMT.MTX_TRANSACTION_ITEMS` with **48 concurrent DB sessions** and a **~22 minute** active window (see project performance write-ups). Treat that as a **reference outcome**, not a contractual SLA from the scripts.

**Rule for reproduction:** always validate with Oracle:

```sql
-- PDB / service for ORDERMGMT
SELECT COUNT(*) FROM ORDERMGMT.MTX_TRANSACTION_ITEMS;
```

---

## 2. Canonical scripts (this repo)

All paths below are relative to the repository root (the folder that contains `oracle-database/`).

| Role | File |
|------|------|
| **Environment (Oracle Instant Client + HammerDB PATH)** | `oracle-database/hammerdb-oracle-env.sh` |
| **30-minute-class sustained load (default 1800 s)** | `oracle-database/hammerdb-mtx-items-30min-heavy.sh` |
| **Higher redo / higher parallelism wrapper** | `oracle-database/hammerdb-mtx-items-high-redo.sh` |
| **“Production” single-table MTX run (iteration-based unless duration set)** | `oracle-database/hammerdb-mtx-run-production.sh` |
| **HammerDB CLI entry (VU creation, `vurun`)** | `oracle-database/hammerdb-mtx-transaction-items-run.tcl` |
| **Per-VU workload (INSERT loop)** | `oracle-database/hammerdb-mtx-custom-driver.tcl` |
| **INSERT text for `items_only`** | `oracle-database/hammerdb-mtx-items-only-insert.sql` |
| **Stop load** | `oracle-database/stop-hammerdb-load.sh` |

**Customer-facing command for the high-redo / 30-minute profile (matches `README.md` and `docs/hammerdb-setup.md`):**

```bash
cd oracle-database
source ./hammerdb-oracle-env.sh
export HDB_MTX_PASS='<ordermgmt_password>'
./hammerdb-mtx-items-high-redo.sh 2>&1 | tee mtx-high-redo.log
```

**What this actually executes:** `hammerdb-mtx-items-high-redo.sh` ends by running `hammerdb-mtx-items-30min-heavy.sh` (see “Execution chain” below).

---

## 3. Execution chain (call stack)

```text
hammerdb-mtx-items-high-redo.sh
  └─> hammerdb-mtx-items-30min-heavy.sh
        ├─> sources hammerdb-oracle-env.sh
        ├─> sets HDB_MTX_* environment variables (mode, duration, VUs, …)
        └─> exec hammerdbcli tcl auto hammerdb-mtx-transaction-items-run.tcl
              ├─> loads hammerdb-mtx-custom-driver.tcl as customscript
              └─> vuset / vucreate / vurun  (parallel workers)
```

### 3.1 What `hammerdb-mtx-items-30min-heavy.sh` configures

From the script (behavioral summary):

- **`HDB_MTX_MODE=items_only`** — each VU inserts only into `MTX_TRANSACTION_ITEMS` using `hammerdb-mtx-items-only-insert.sql` (not full TPROC-C).
- **`HDB_MTX_DURATION_SECONDS`** — default **1800** (30 minutes) unless you override. This activates the **time-bound** loop in the custom driver.
- **`HDB_MTX_TOTAL_ITERATIONS`** — set very high (`999999999`) so the **duration** stops the test, not the iteration cap.
- **`HDB_MTX_NO_TC=true` (default)** — skips HammerDB’s transaction counter that often hits `ORA-28000` with custom credentials; **load still runs in VUs**.
- **`HDB_MTX_RAISEERROR=false` (default)** — bind/execute failures can be **silent**; for debugging, set `HDB_MTX_RAISEERROR=true`.
- **Auto VUs (if `HDB_MTX_VUS` is not preset):**  
  `V = min(2 × nproc, HDB_MTX_VUS_MAX)` with default **`HDB_MTX_VUS_MAX=64`**.

### 3.2 What `hammerdb-mtx-items-high-redo.sh` adds

This script **only adjusts parallelism** (and keeps the same 30-minute driver):

- Default **`HDB_MTX_DURATION_SECONDS=1800`** (same 30-minute window unless overridden).
- Default **`HDB_MTX_VUS_MAX=96`** (higher cap than the plain 30-minute script).
- Auto VUs (if `HDB_MTX_VUS` is not preset):  
  `V = min(3 × nproc, HDB_MTX_VUS_MAX)`.

**Examples (auto VU math, no `HDB_MTX_VUS` override):**

| Host `nproc` | `hammerdb-mtx-items-30min-heavy.sh`  
`V = min(2×nproc, 64)` | `hammerdb-mtx-items-high-redo.sh`  
`V = min(3×nproc, 96)` |
|--------------|-------------------------------|------------------------------|
| 16 | 32 | **48** |
| 24 | **48** | 72 |

A PoC that reported **48 concurrent sessions** matches **automatic** selection when either:

- **`hammerdb-mtx-items-30min-heavy.sh` on a 24 vCPU** HammerDB host, or  
- **`hammerdb-mtx-items-high-redo.sh` on a 16 vCPU** HammerDB host.

If you must **match a specific session count** regardless of CPU count, set it explicitly:

```bash
export HDB_MTX_VUS=48
./hammerdb-mtx-items-high-redo.sh
```

---

## 4. How the TCL workload generates rows (`items_only`)

`hammerdb-mtx-transaction-items-run.tcl`:

- Sets HammerDB to Oracle + TPC-C module **only because HammerDB requires a benchmark module**; the **actual SQL** comes from the **custom driver**, not stock TPROC-C tables.
- Creates **`HDB_MTX_VUS`** parallel workers (or `vcpu` if unset — not used by the 30-minute shell path, which always exports `HDB_MTX_VUS`).
- Runs `vurun` so each VU executes `hammerdb-mtx-custom-driver.tcl`.

`hammerdb-mtx-custom-driver.tcl` (mode `items_only`):

- Opens one cursor for the prepared INSERT from `hammerdb-mtx-items-only-insert.sql`.
- If **`HDB_MTX_DURATION_SECONDS > 0`**, enters a **time-bound** `while` loop until `clock seconds` reaches `end_time`.
- Each loop iteration performs **one INSERT** with binds (`UNIQUE_SEQ_NUMBER`, `TRANSFER_ID`, …) designed to avoid collisions across VUs (`mtx_unique_seq50`, `mtx_transfer_id20`).
- **Throughput** ≈ **(successful inserts per second across all VUs)**. With `V` VUs and average `r` rows/sec per VU (not constant), total rows ≈ **Σ over time of (effective aggregate insert rate)**.

There is **no fixed “14M” target** in this loop—only “keep inserting until duration expires.”

---

## 5. How scaling works (load generator side)

Scaling levers **that are real in this repo**:

| Knob | Effect |
|------|--------|
| **`HDB_MTX_VUS`** | More parallel Oracle sessions ⇒ higher potential aggregate insert rate (and more redo). |
| **`HDB_MTX_DURATION_SECONDS`** | Longer sustained window ⇒ more total rows if Oracle keeps accepting load. |
| **`HDB_MTX_ITEMS` / SQL** | `items_only` targets one wide INSERT into `MTX_TRANSACTION_ITEMS` (high row volume path). |
| **`HDB_MTX_PAYLOAD_BYTES`** | Can influence redo size per row if `CDC_PAYLOAD` / bind `:plbd` is present in the SQL text. |
| **`HDB_MTX_RAISEERROR`** | When `false`, errors may be swallowed—always cross-check Oracle sessions and row counts. |

Scaling levers **outside** HammerDB but required for CDC at high throughput:

- Oracle redo capacity, CPU, I/O, RAC configuration.
- XStream capture / outbound server health.
- Kafka Connect batching and producer settings (see §7).

---

## 6. “30 minutes” vs “~22 minutes” in reports

The **default** duration for `hammerdb-mtx-items-30min-heavy.sh` is **1800 seconds (30 minutes)**.

If a historical report shows **~22 minutes**, that can still be consistent with:

- the load finishing early (for example, operator stop, wrapper behavior, or environment-specific HammerDB/Oracle behavior), or
- monitoring timestamps that reflect **post-run** observation windows (some field reports note that monitoring captured counts after bursts).

**Reproduction discipline:** use logs (`tee` to `mtx-high-redo.log`) and Oracle `V$SESSION` / AWR / your monitoring to establish the **true** start/stop window.

---

## 7. CDC latency (~200 ms) — not produced by HammerDB alone

`docs/performance-results.md` states an end-to-end CDC latency **profile** on the order of **~200 ms** under PoC conditions. That latency is a property of:

1. **Oracle → redo → XStream capture → outbound server**
2. **Kafka Connect Oracle XStream connector → Kafka producer → brokers**
3. **Consumer / monitoring observation point**

It is **not** a single setting inside `hammerdb-mtx-*.sh`.

### 7.1 Connector settings documented in this repo

`docs/performance-results.md` lists representative Kafka Connect / producer tuning (throughput vs latency trade-offs), including:

- `query.fetch.size=50000`
- `max.queue.size=262144`
- `max.batch.size=65536`
- `producer.override.batch.size=1048576`
- `producer.override.linger.ms=50`
- `producer.override.compression.type=lz4`

These appear in the example connector JSON at `xstream-connector/oracle-xstream-rac-docker.json.example` (adjust hostnames, credentials, and topic rules for your environment).

**Important:** larger batches and higher linger **improve throughput** but can **change end-to-end latency characteristics**. Your ~200 ms outcome depends on the full stack and where latency is measured (Grafana / Prometheus / consumer timestamps).

---

## 8. End-to-end reproduction checklist (order matters)

1. **Oracle**: schema present (`ORDERMGMT.MTX_TRANSACTION_ITEMS`), user/password, TNS reachable from the HammerDB host (`HDB_MTX_TNS`, default `RAC_XSTRPDB_POC` in scripts).
2. **XStream / supplemental logging / capture**: follow `docs/oracle-cdc-setup.md` and the numbered SQL scripts in `oracle-database/` referenced from `docs/performance-results.md`.
3. **Kafka + Connect**: start the stack (`start-all.sh` at repo root for the Docker PoC layout).
4. **Deploy connector** from `xstream-connector/oracle-xstream-rac-docker.json.example` (edited for your cluster).
5. **Run HammerDB load** using the commands in §2.
6. **Validate**:
   - Oracle row counts (§1).
   - Kafka topic growth / consumer lag (see `docs/validation-guide.md`).
   - Monitoring dashboards under `monitoring/` (see `monitoring/DASHBOARD_SETUP_GUIDE.md`).

---

## 9. Accuracy & versioning

- Script behavior is determined by the files named in §2; if you fork or edit locally, diff those files first.
- This guide is aligned with the repository layout where **`hammerdb-mtx-items-high-redo.sh` is a thin wrapper** that **`exec`s `hammerdb-mtx-items-30min-heavy.sh`** after computing VUs.

If anything in this guide diverges from the scripts, **the scripts win**—open an issue with the file/line reference.
