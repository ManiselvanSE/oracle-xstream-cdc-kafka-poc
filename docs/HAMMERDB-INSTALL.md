# HammerDB installation (Oracle Linux 9, OCI client VM)

This documents installing **HammerDB 5.0** on the load-driver host (e.g. **hammerdb** / `141.148.128.58`) using the **official RHEL 9 / OL 9 RPM** from GitHub.

**Prerequisites (already done for RAC testing):**

- Oracle **Instant Client** + **SQL\*Plus** (see `oracle-database/hammerdb-client-oracle-setup.sh`).
- OCI **security rules** so this host can reach **RAC listeners** on **TCP 1521** (SCAN + VIPs). See `docs/OCI-HAMMERDB-RAC-1521.md`.

---

## 1. Download the EL9 RPM

Official release (check [HammerDB releases](https://github.com/TPC-Council/HammerDB/releases) for the latest **v5.x** and **el9** asset):

```bash
cd /tmp
curl -fsSL -O https://github.com/TPC-Council/HammerDB/releases/download/v5.0/hammerdb-5.0-1.el9.x86_64.rpm
```

---

## 2. Install

```bash
sudo dnf install -y ./hammerdb-5.0-1.el9.x86_64.rpm
```

`dnf` pulls in **X11 / Tk**-related dependencies (GUI). For **CLI-only** automation you still use **`hammerdbcli`**; a desktop is optional (X11 forwarding or local console if you use the **`hammerdb`** GUI).

---

## 3. Install location and PATH

Binaries are under:

| Path | Purpose |
|------|---------|
| `/opt/HammerDB-5.0/hammerdb` | GUI (Tcl/Tk) |
| `/opt/HammerDB-5.0/hammerdbcli` | **CLI** (automation) |
| `/opt/HammerDB-5.0/hammerdbws` | Web service (optional) |

Add to `~/.bashrc` (as **opc**):

```bash
export PATH="/opt/HammerDB-5.0:${PATH}"
```

Then:

```bash
source ~/.bashrc
hammerdbcli -v
```

Expected:

```text
HammerDB CLI v5.0
```

---

## 4. Oracle driver in HammerDB

HammerDB uses Oracle through **OCI**. Ensure **Instant Client** is on **`LD_LIBRARY_PATH`** (the `hammerdb-client-oracle-setup.sh` flow sets `ORACLE_HOME` and `LD_LIBRARY_PATH`). If the Oracle library is not found, point `LD_LIBRARY_PATH` at `/usr/lib/oracle/19.29/client64/lib` (or your installed version).

---

## 5. Next steps (workload)

1. In HammerDB, choose **Oracle** (see [HammerDB Oracle](https://www.hammerdb.com/docs4.12/ch04.html#ch04lvl1sec1)).
2. Configure **connection** (host, port **1521**, service name / PDB) to match **`sqlplus`**.
3. Build schema and run **TPC-C** / **TPROC-C** per your test plan.

For **RAC** (TNS, `ORACLE_LIBRARY`, CLI scripts), see **`docs/HAMMERDB-RAC-LOAD.md`**.

---

## 6. Version installed on PoC VM (2026-03-25)

| Item | Value |
|------|--------|
| OS | Oracle Linux Server 9.7 |
| HammerDB | **5.0-1.el9** (`hammerdb-5.0-1.el9.x86_64.rpm`) |
| Install path | `/opt/HammerDB-5.0` |

---

## 7. Uninstall (optional)

```bash
sudo dnf remove -y hammerdb
```

(Remove unused X11 packages only if nothing else needs them.)
