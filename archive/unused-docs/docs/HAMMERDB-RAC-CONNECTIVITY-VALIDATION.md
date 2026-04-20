# HammerDB VM → Oracle RAC: troubleshooting and validation guide

**Audience:** DBAs and performance engineers validating **Linux** load clients (HammerDB VM) against **Oracle RAC 19c+** before TPC-C runs.

**Order of checks:** Network (TCP) → Instant Client + env → **TNS** → **sqlplus** (authoritative DB login) → **HammerDB** (`librarycheck` + config TCL) → **RAC** (optional SQL on DB).  
If anything fails, **stop** and fix that layer before continuing.

**Related:** `docs/OCI-HAMMERDB-RAC-1521.md` (firewall / VIP redirect), `docs/HAMMERDB-ORACLE-RAC-TPCC-PRODUCTION-GUIDE.md` (full benchmark), `oracle-database/hammerdb-oracle-env.sh`.

**Automated check on the VM:** `bash oracle-database/diagnose-hammerdb-rac-connectivity.sh` — exercises DNS, TCP **1521** to SCAN/VIPs, **`tnsnames.ora`**, **`sqlplus`** probe, and HammerDB **`librarycheck`** via **`hammerdbcli tcl auto`** (non-interactive-safe). Install **`oracle-instantclient-tools`** on the client if you want **`tnsping`** in that script.

---

## 1. Network connectivity checks

### 1.1 Why SCAN alone is not enough (RAC)

The client often connects to **SCAN:1521** first; the listener may **redirect** to a **node VIP:1521**. If the firewall allows SCAN but **not** VIPs, you get **`ORA-12543: TNS:destination host unreachable`** after the redirect. See **`docs/OCI-HAMMERDB-RAC-1521.md`**.

### 1.2 Resolve SCAN and RAC endpoints

Collect from your DBA / OCI / `nslookup`:

- **SCAN hostname** (e.g. `racdb-scan.example.com`)
- **SCAN IP addresses** (often three)
- **Node VIPs** (per instance) — for firewall rules and optional `ping`

**DNS / SCAN:**

```bash
getent hosts racdb-scan.example.com
# or
nslookup racdb-scan.example.com
```

**Expected:** One or more **A records** (SCAN typically maps to **three** IPs).

### 1.3 `ping` (ICMP)

```bash
ping -c 3 racdb-scan.example.com
ping -c 3 10.0.0.29
```

**Interpretation:**

- **Success:** Hosts are reachable at L3 (if ICMP is allowed; many clouds block ICMP but allow TCP — **failure here does not always mean DB is blocked**).
- **Failure:** Note it, but still test **TCP 1521** (below).

### 1.4 Port **1521** — `bash` `/dev/tcp` (no extra packages)

```bash
HOST=racdb-scan.example.com
timeout 5 bash -c "echo >/dev/tcp/${HOST}/1521" && echo "TCP 1521 OK" || echo "TCP 1521 FAIL"
```

Repeat for **each SCAN IP** and **each node VIP** your DBA lists:

```bash
for ip in 10.0.0.29 10.0.0.91 10.0.0.238 10.0.0.104 10.0.0.105; do
  timeout 3 bash -c "echo >/dev/tcp/${ip}/1521" 2>/dev/null && echo "${ip}:1521 OK" || echo "${ip}:1521 FAIL"
done
```

**Expected:** **OK** to SCAN and to VIPs you will use. **FAIL** → security list / NSG / routing / wrong subnet.

### 1.5 `nc` (netcat) and `telnet`

If installed:

```bash
nc -vz racdb-scan.example.com 1521
# or
telnet racdb-scan.example.com 1521
```

**Expected:** `Connected` / `succeeded` / open port. **Ctrl+]** then `quit` for telnet.

### 1.6 Repo helper script

From the repo on the VM (or copy the script):

```bash
bash oracle-database/verify-hammerdb-rac-network.sh
```

Edit **`SCAN_IPS`** inside the script to match your environment.

---

## 2. Oracle client configuration

### 2.1 Verify Instant Client installation

```bash
rpm -qa | grep -i instantclient
ls -la /usr/lib/oracle/*/client64/lib/libclntsh.so
```

**Expected:** RPMs listed; **`libclntsh.so`** is a symlink to a versioned file.

### 2.2 Required environment variables

| Variable | Purpose |
|----------|---------|
| **`ORACLE_HOME`** | Instant Client home (e.g. `/usr/lib/oracle/19.29/client64`). |
| **`LD_LIBRARY_PATH`** | Must include `$ORACLE_HOME/lib`. |
| **`ORACLE_LIBRARY`** | Full path to **`libclntsh.so`** (HammerDB **Oratcl**). |
| **`TNS_ADMIN`** | Directory containing **`tnsnames.ora`**. |
| **`PATH`** | Includes HammerDB, e.g. `/opt/HammerDB-5.0`. |

**Source:**

```bash
source /path/to/oracle-xstream-cdc-poc/oracle-database/hammerdb-oracle-env.sh
```

**Sanity checks:**

```bash
echo "ORACLE_HOME=$ORACLE_HOME"
echo "TNS_ADMIN=$TNS_ADMIN"
ls -la "$ORACLE_LIBRARY"
ldd "$ORACLE_LIBRARY" | head -20
```

**Expected:** No **`not found`** for critical libs in `ldd` output.

### 2.3 Validate with **sqlplus**

```bash
sqlplus -V
```

**Expected:** SQL\*Plus version string referencing your client (e.g. 19.x).

---

## 3. TNS configuration validation

### 3.1 Sample `tnsnames.ora` (RAC + SCAN + `SERVICE_NAME`)

Place under **`$TNS_ADMIN`** (e.g. `$HOME/oracle/network/admin/tnsnames.ora`).

**Use `SERVICE_NAME`** for RAC services — **not** `SID` (unless you intentionally target a single instance).

```text
MYRAC_SVC =
  (DESCRIPTION =
    (LOAD_BALANCE = yes)
    (ADDRESS = (PROTOCOL = TCP)(HOST = racdb-scan.example.com)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = my.db.service.name)
    )
  )
```

Multi-address variant (optional): see **`oracle-database/hammerdb-tnsnames.rac.production.example`**.

### 3.2 `tnsping`

```bash
export TNS_ADMIN=$HOME/oracle/network/admin
tnsping MYRAC_SVC
```

**Expected success (example):**

```text
OK (20 msec)
```

**Typical failure:** **`TNS-03505: failed to resolve name`** → wrong alias, wrong **`TNS_ADMIN`**, or missing file.

### 3.3 Common mistakes

| Mistake | Symptom |
|---------|---------|
| **`SID=`** instead of **`SERVICE_NAME`** for a **service** | Wrong target / wrong instance / errors depending on policy. |
| **Alias typo** vs **`diset connection instance`** | **ORA-12154**. |
| **`TNS_ADMIN`** unset | **`$TNS_ADMIN`/`tnsnames.ora`** not found. |

---

## 4. Connection testing (SQL\*Plus)

### 4.1 TNS alias (recommended)

```bash
sqlplus -L system@MYRAC_SVC
```

Enter password when prompted (avoid putting password in shell history).

### 4.2 Easy Connect (bypasses `tnsnames.ora` — good cross-check)

```bash
sqlplus -L 'system@"//racdb-scan.example.com:1521/my.db.service.name"'
```

### 4.3 Expected success

```text
Connected to:
Oracle Database 19c Enterprise Edition Release ...
```

Then:

```sql
SELECT SYS_CONTEXT('USERENV','SERVICE_NAME') AS service_name FROM DUAL;
SELECT SYS_CONTEXT('USERENV','INSTANCE_NAME') AS instance_name FROM DUAL;
EXIT;
```

### 4.4 Expected failure examples

| Output | Meaning |
|--------|---------|
| **`ORA-12154: TNS:could not resolve the connect identifier`** | Bad alias / **`TNS_ADMIN`** / typo. |
| **`ORA-12514: TNS:listener does not currently know of service ...`** | Wrong **service name** or service not registered. |
| **`ORA-12541: TNS:no listener`** | Wrong host/port or listener down. |
| **`ORA-12543`** / **`TNS-12543`** | Network block to redirected address (often VIP). |

---

## 5. HammerDB connectivity

### 5.1 GUI

1. Start **`/opt/HammerDB-5.0/hammerdb`** (with display / X11 if remote).  
2. Choose **Oracle** + **TPC-C**.  
3. Set **connection** fields to match **`diset`** (system user, password, **instance** = TNS alias).  
4. Use **virtual user** / driver only **after** SQL\*Plus works.

### 5.2 CLI — load **Oratcl** (`librarycheck`)

HammerDB must load **`libclntsh.so`** via **`ORACLE_LIBRARY`** (see [HammerDB docs — client libraries](https://www.hammerdb.com/docs/ch01s10.html)).

**Interactive:**

```bash
source /path/to/hammerdb-oracle-env.sh
/opt/HammerDB-5.0/hammerdbcli
```

At the **`hammerdb>`** prompt:

```text
librarycheck
```

**Expected:**

```text
Checking database library for Oracle
Success ... loaded library Oratcl for Oracle
```

**Non-interactive / SSH / batch (required):** do **not** pipe commands into **`hammerdbcli`** without a TTY — it fails with **`stty: impossible in this context`**. Use **`tcl auto`** instead:

```bash
source /path/to/hammerdb-oracle-env.sh
/opt/HammerDB-5.0/hammerdbcli tcl auto /path/to/oracle-database/hammerdb-librarycheck.tcl
```

Or run **`oracle-database/hammerdb-cli-librarycheck.sh`** (same as above).

**Optional:** `script -q -c '...' /dev/null` can fake a TTY for interactive CLI; prefer **`tcl auto`**.

### 5.3 Minimal TCL — configuration + `print dict`

HammerDB establishes a full **OCI** session when you run **schema build** or the **driver** (`loadscript` / `vurun`). For **lightweight** checks, use:

1. **`librarycheck`** (client library)  
2. **`sqlplus`** (real database login) — **primary proof**  
3. Optional TCL: **`print dict`** after `dbset` / `diset` to confirm HammerDB sees the same parameters you expect.

**Script:** `oracle-database/hammerdb-connection-sanity.tcl`

```bash
hammerdbcli tcl auto /path/to/hammerdb-connection-sanity.tcl 2>&1 | tee hammerdb_sanity.log
```

### 5.4 Where errors appear

| Output | Where |
|--------|--------|
| **Oratcl / libclntsh** | **`librarycheck`** stdout/stderr. |
| **TNS / ORA** | **`sqlplus`**, HammerDB **`buildschema`** / **`vurun`** / TCL stderr. |
| **Redirect** | Capture with **`2>&1 \| tee file.log`**. |

---

## 6. RAC-specific validation

Run in **SQL\*Plus** (or SQL*Plus as **`TPCC`** after schema exists) **connected via the same service** you use for HammerDB.

### 6.1 Instance you landed on

```sql
SELECT instance_name, host_name FROM v$instance;
```

Repeat **multiple connections** (new SQL\*Plus sessions): with **SCAN + service** and **load balancing**, you may see **different `instance_name`** values over time — indicates **multi-instance** use (not a guarantee of even distribution).

### 6.2 Service name

```sql
SELECT SYS_CONTEXT('USERENV','SERVICE_NAME') FROM DUAL;
```

**Expected:** Your **RAC service** name (not a bare **SID** unless that is how you connect).

### 6.3 **`gv$session`** (requires privileges; run as DBA or grant `SELECT` on **`gv$`**

```sql
SELECT inst_id, event, COUNT(*) samples
FROM   gv$session
WHERE  username = 'TPCC'
GROUP BY inst_id, event
ORDER BY inst_id, samples DESC;
```

During a load test, **multiple `inst_id`** with **`TPCC`** sessions indicates **sessions on more than one node** (validate while load is running).

---

## 7. Troubleshooting matrix

### 7.1 TNS / Oracle errors

| Error | Typical fix |
|-------|-------------|
| **ORA-12154** | Fix **`TNS_ADMIN`**, **`tnsnames.ora`**, alias spelling; match **`diset connection instance`**. |
| **ORA-12514** | Wrong **`SERVICE_NAME`**; check **`lsnrctl services`** on DB side / **`srvctl config service`**. |
| **ORA-12541** | Listener not reachable on host:port; firewall; wrong IP. |
| **ORA-12543** / **TNS-12543** | Open **TCP 1521** from client to **SCAN and VIPs**; see **`OCI-HAMMERDB-RAC-1521.md`**. |

### 7.2 Firewall

- Confirm **source** = HammerDB VM **private IP** (not a typo).  
- **Ingress** on **DB subnet** NSG + security list **and** any hop (peering, DRG).  
- Re-test **`/dev/tcp`** to **SCAN** and **each VIP**.

### 7.3 Listener / service

- On server: **`lsnrctl status`**, **`srvctl status database`**, **`srvctl status service`**.  
- Service **not running** or **not registered** → **ORA-12514**.

### 7.4 DNS / SCAN

- **`nslookup`** / **`getent hosts`** must resolve SCAN to expected IPs.  
- **Stale DNS:** flush cache or retry; align with **GNS** / **DNS** in Exadata/OCI as designed.

### 7.5 Real environment note (what “failed” often means)

If **`tcp`** to **SCAN/VIP:1521** fails and **`sqlplus`** returns **`ORA-12543`**, the blocker is **network policy** (OCI security list / NSG / routing), not TNS text. **HammerDB** can still report **Oratcl Success** because that only loads **`libclntsh.so`** locally. **Fix:** allow **TCP 1521** from the HammerDB host to the **DB subnet** (SCAN + VIPs), e.g. source **`10.0.0.173/32`** → **`docs/OCI-HAMMERDB-RAC-1521.md`**.

---

## 8. Final checklist (before load tests)

| # | Check | Pass criteria |
|---|--------|----------------|
| 1 | **TCP 1521** to SCAN + VIPs | `/dev/tcp` or `nc` **OK** |
| 2 | **`tnsping ALIAS`** | **OK (msec)** |
| 3 | **`sqlplus user@ALIAS`** | **Connected**; **`SERVICE_NAME`** correct |
| 4 | **Env** | **`ORACLE_HOME`**, **`LD_LIBRARY_PATH`**, **`ORACLE_LIBRARY`**, **`TNS_ADMIN`** set |
| 5 | **`librarycheck`** | **Success ... Oratcl** |
| 6 | **HammerDB TCL** (optional) | **`print dict`** shows expected **instance** / password placeholders resolved |
| 7 | **RAC** (optional) | **`gv$session`** shows **multiple `inst_id`** under load |

When **1–5** pass, the HammerDB VM is **properly positioned** to run **buildschema** and **workload** scripts. **6–7** are **strong** confirmation for RAC.

---

## 9. One-page command sequence (copy-paste)

```bash
# 1) Env
source /path/to/oracle-database/hammerdb-oracle-env.sh
export TNS_ADMIN=$HOME/oracle/network/admin

# 2) TCP (edit hosts/IPs)
timeout 3 bash -c 'echo >/dev/tcp/racdb-scan.example.com/1521' && echo OK || echo FAIL

# 3) TNS + SQL
tnsping MYRAC_SVC
sqlplus -L system@MYRAC_SVC

# 4) HammerDB Oratcl (use tcl auto — piping to hammerdbcli breaks without a TTY)
/opt/HammerDB-5.0/hammerdbcli tcl auto /path/to/oracle-database/hammerdb-librarycheck.tcl

# 5) Optional: sanity TCL
/opt/HammerDB-5.0/hammerdbcli tcl auto /path/to/hammerdb-connection-sanity.tcl 2>&1 | tee hammerdb_sanity.log
```

---

*Document version: aligned with HammerDB 5.x CLI and Oracle Instant Client 19c on Linux.*
