# Why Connector VM reaches RAC but HammerDB does not

This document matches your OCI layout from the console screenshots and explains **why** **`sqlplus`** / HammerDB from **hammerdb-client** fails with **`ORA-12543`** / **No route to host**, while **mani-xstrm-vm** (Xstream connector) works.

---

## What your screenshots show

| Resource | VCN | Subnet | Private IP |
|----------|-----|--------|------------|
| **RAC DB System** (`Mani_RACDB`) | **`xstrm-connect-db2`** | **`public subnet-xstrm-connect-db2`** (client subnet) | SCAN: **10.0.0.29**, **.91**, **.238** |
| **Connector VM** (`mani-xstrm-vm`) | **`xstrm-connect-db2`** | **`public subnet-xstrm-connect-db2`** | **10.0.0.162** |
| **HammerDB VM** (`hammerdb-client`) | **`vcn-xstr`** | **`oracle_pub_xstr`** | **10.0.0.173** |

**Connector and RAC live in the same Virtual Cloud Network (VCN) and the same client subnet.**  
**HammerDB lives in a different VCN** (`vcn-xstr`), not in `xstrm-connect-db2`.

---

## Layman explanation

- Think of a **RAC database** as a service running in **Building A** (`xstrm-connect-db2`).
- The **Connector VM** is a laptop **in the same building**, on the **same internal network** as the database. It can walk down the hall and knock on **port 1521** — **allowed** by the building’s firewall (**security list** `racdbsl`).
- The **HammerDB VM** is in **Building B** (`vcn-xstr`). There is **no hallway** between Building A and Building B unless you build one (**VCN peering** + **routes**) or you **move** the laptop into Building A.

So: **Security rules on the DB subnet** (e.g. allow `10.0.0.0/24` → **1521**) only help **after** traffic **arrives** at that subnet. From HammerDB, traffic **never gets there** in a usable way if **`vcn-xstr`** has **no route** to **`xstrm-connect-db2`**. That shows up as **“destination host unreachable”** / **“No route to host”** — **before** Oracle username/password even matters.

**Why both IPs look like `10.0.0.x`:**  
Private IPs can look similar, but in OCI **each VCN is its own network**. **`10.0.0.173`** in **`vcn-xstr`** is **not** “next door” to **`10.0.0.29`** in **`xstrm-connect-db2`** unless you explicitly connect the two networks.

---

## Technical summary

| Check | Connector (`10.0.0.162`) | HammerDB (`10.0.0.173`) |
|--------|--------------------------|-------------------------|
| Same VCN as RAC? | **Yes** (`xstrm-connect-db2`) | **No** (`vcn-xstr`) |
| Same subnet as DB client subnet? | **Yes** | **No** |
| Needs cross-VCN path? | **No** | **Yes** (or move VM) |

The **`racdbsl`** ingress (**`10.0.0.0/24` → TCP 1521**) is correct **on the DB side** for sources that can **reach** that subnet. It does **not** by itself create a path from **`vcn-xstr`** to **`xstrm-connect-db2`**.

---

## Fix options (choose one)

### Option A — Recommended: move HammerDB into `xstrm-connect-db2`

**Step-by-step (new instance, custom image, checklist):** see **`docs/OCI-HAMMERDB-MOVE-TO-DB-VCN.md`**.

Summary:

1. Create or pick a **subnet** in **`xstrm-connect-db2`** (can be **private**; load generation does not require a public IP if you SSH via bastion/OCI Bastion).
2. **Create a new instance** in that VCN/subnet (OCI does not move a VNIC to another VCN — use **new instance** or **custom image** from the old VM).
3. Ensure the **subnet’s security list** allows **ingress TCP 1521** from the HammerDB private IP or its subnet CIDR (your **`racdbsl`** rule may already allow **`10.0.0.0/24`** if the new IP stays in range — confirm after move).
4. Re-run **`diagnose-hammerdb-rac-connectivity.sh`** from the new VM.

**Why this works:** Same pattern as the Connector VM — **one VCN**, **routed path** to SCAN/VIPs without cross-VCN complexity.

### Option B — Keep HammerDB in `vcn-xstr`: Local Peering Gateways (LPG)

1. Confirm **`vcn-xstr`** and **`xstrm-connect-db2`** use **non-overlapping** CIDRs (required for peering). If both use **`10.0.0.0/24`**, you **cannot** use classic LPG peering — **Option A** or **re-address** one VCN.
2. In each VCN: **Networking** → **Local Peering Gateways** → create LPG, accept connection.
3. Add **route rules**: in **`vcn-xstr`**, route **`xstrm-connect-db2`** CIDR (or SCAN/VIP prefixes) to the **LPG**; in **`xstrm-connect-db2`**, route **`vcn-xstr`** CIDR back.
4. On **DB subnet security list** (`racdbsl`): allow **ingress** TCP **1521** from **`vcn-xstr`**’s subnet CIDR (e.g. **`10.0.0.173/32`** or the whole HammerDB subnet), not only **`10.0.0.0/24`** if that range only exists inside the DB VCN.
5. Optional: **egress** from HammerDB subnet to DB CIDR on **1521**.

**Why this is harder:** Requires non-overlapping CIDRs, two-way routes, and matching security rules on **both** sides.

### Option C — Dynamic Routing Gateway (DRG) / hub-spoke

Use if you already use **DRG** for connectivity between VCNs. Same idea as B: **routes** + **security lists** must allow **`vcn-xstr` → xstrm-connect-db2:1521**.

---

## After any fix — verify

From the HammerDB VM:

```bash
timeout 4 bash -c 'echo >/dev/tcp/10.0.0.29/1521' && echo OK || echo FAIL
sqlplus -L system@RAC_XSTRPDB_POC   # or your TNS alias
```

---

## Related docs

- `docs/OCI-HAMMERDB-RAC-1521.md` — **SCAN + VIP** and **security list / NSG** on the **DB** side.
- `oracle-database/diagnose-hammerdb-rac-connectivity.sh` — automated checks from the VM.
