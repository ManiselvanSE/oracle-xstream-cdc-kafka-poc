# Allow HammerDB client → RAC listener (TCP 1521)

**If the HammerDB VM is in a different VCN than the RAC DB** (e.g. **`vcn-xstr`** vs **`xstrm-connect-db2`**), security lists alone are not enough — see **`docs/OCI-HAMMERDB-WHY-CONNECTOR-WORKS.md`** (why the Xstream Connector VM works and HammerDB does not).

`ORA-12543: TNS:destination host unreachable` from **hammerdb-client** means a TCP session to **some** Oracle listener address is blocked **before** Oracle authentication.

This is **not** fixed by installing SQL*Plus on the VM. You must allow the **HammerDB private IP** on the **database side** (security list and/or NSG).

## RAC redirect (why SCAN-only rules are not enough)

After the client connects to **SCAN** (`10.0.0.29`, etc.), the **listener often redirects** the session to a **node VIP** (for example `10.0.0.104:1521`). The client then opens a **second** TCP connection to that VIP. If your security list allows only SCAN IPs but **not** VIPs, you still get **ORA-12543**.

**Fix:** Allow **TCP 1521** from **HammerDB** (`10.0.0.173/32`) to the **entire DB private CIDR** that holds SCAN, VIPs, and nodes (for example **`10.0.0.0/16`** scoped to the DB subnet / compartment policy), **or** add **each VIP** from **OCI → DB System → Nodes** to ingress rules.

**SSH tunnels** through another host do **not** avoid VIP redirect; the client still tries to reach VIPs directly unless the network is open.

## Values to use

| Item | Example (your env) |
|------|---------------------|
| HammerDB private IP | `10.0.0.173` |
| Port | `1521` |
| Protocol | TCP (IP protocol 6) |

**Do not** use `10.0.1.173` unless that is really the VM’s address.

## Where to add the rule (both may be required)

1. **Subnet security list** attached to the **subnet where the DB System / RAC listeners** are (often **not** the same as `oracle_pub_xstr` if DB lives in another subnet or VCN).
2. **Network Security Groups (NSG)** attached to the **DB System** or **DB nodes** — add the same ingress there if the DB uses NSGs.

The **Default Security List for `vcn-xstr`** only affects subnets that **use** that list. If RAC is in **`xstrm-connect-db2`** (or another VCN), add the rule on that VCN’s DB subnet / NSG, and ensure **VCN peering / routing** allows traffic from `10.0.0.173`.

## Console (fastest)

1. OCI → **Networking** → **Virtual Cloud Networks** → open the VCN where **RAC / Base Database** is attached.
2. **Subnets** → open the subnet used by **Client** or **DB** for the DB System (see DB System → **Network**).
3. Click the **Security list** → **Add Ingress Rules**:
   - **Source CIDR:** `10.0.0.173/32`
   - **IP Protocol:** TCP
   - **Destination Port Range:** `1521`
   - Description: `HammerDB client to RAC listener`
4. If the DB System shows **Network Security Groups**, open each NSG → **Add Rule** (same as above).

## Verify from HammerDB (must pass before SQL*Plus)

```bash
timeout 3 bash -c 'echo >/dev/tcp/10.0.0.29/1521' && echo OK || echo FAIL
```

Repeat for other SCAN IPs (`10.0.0.91`, `10.0.0.238`) if needed. When you see **OK**, try:

```bash
sqlplus 'sys/<password>@//racdb-scan.<your-domain>.oraclevcn.com:1521/<service>' AS SYSDBA
```

## OCI CLI (advanced)

Fetch the security list OCID from the DB subnet, then **merge** a new ingress rule with existing rules (do not replace the whole list without reading current rules first). Example pattern:

```bash
SL_OCID="<db-subnet-security-list-ocid>"
oci network security-list get --security-list-id "$SL_OCID" --query data > /tmp/sl.json
# Edit /tmp/sl.json: append to "ingressSecurityRules" then:
oci network security-list update --security-list-id "$SL_OCID" --from-json file:///tmp/sl-updated.json
```

Use the console if unsure; a bad CLI update can remove other rules.

---

## Detailed OCI Console steps (HammerDB → RAC on TCP 1521)

Follow these when **`ORA-12543`** / **`tcp` to `*:1521` FAIL** from the HammerDB VM. You need permission to edit **VCN security lists**, **NSGs**, and to view **DB System → Network**.

### A. Confirm the source (HammerDB VM)

1. OCI → **Compute** → **Instances** → open the **HammerDB** (or load client) instance.
2. Under **Primary VNIC** → **IPv4 addresses**, note the **Private IP** (example: **`10.0.0.173`**). This is the **Source CIDR** you will use as **`10.0.0.173/32`**.
3. Note the **Subnet** name and **VCN** (e.g. `vcn-xstr` / `hammerdb` subnet). You need the **DB side** to accept traffic **from** this IP — the rule is added on the **database** subnet/NSG, not only on the HammerDB subnet.

### B. Find where the RAC / DB System is attached

1. OCI → **Oracle Database** → **Oracle Base Database** or **Exadata** / **VM cluster** (whichever hosts RAC) → open your **DB System**.
2. Open **Network** (or **Resources** → **Network**).
3. Write down:
   - **VCN** name
   - **Subnet** used by the DB (client or **DB** subnet per architecture)
   - **Network Security Groups** listed (if any)

If HammerDB and RAC are in the **same VCN** and **routing is default**, you only need **ingress on the DB subnet/NSG** from **`10.0.0.173/32`**.

If they are in **different VCNs**, you also need **VCN local peering (LPG)** or **DRG** with **route rules** so **`10.0.0.173`** can reach the DB subnet CIDR. If **`ping`/TCP fails** even after security lists, involve **networking** to verify **peering + route tables**.

### C. Add an ingress rule on the DB subnet Security List

1. OCI → **Networking** → **Virtual Cloud Networks** → select the **VCN where the DB System lives** (from step B).
2. Left menu → **Subnets** → open the **subnet** your DB System uses for **client/listener** access (the one that owns the SCAN/listener endpoints in your design).
3. In the subnet details, find **Security Lists** (often one primary list, sometimes multiple).
4. Click the **Security List** name → **Add Ingress Rules**.
5. Add **one** rule with:

| Field | Value |
|--------|--------|
| **Stateless** | No (leave unchecked — use **stateful** default so return traffic works). |
| **Source CIDR** | **`10.0.0.173/32`** (your HammerDB **private** IP from step A). |
| **IP Protocol** | **TCP** |
| **Source Port Range** | **All** (or leave default; for ingress the important part is destination port). |
| **Destination Port Range** | **1521** |
| **Description** | `HammerDB VM to Oracle listener` |

6. **Save** the rule.

**Why `/32`:** Only that VM is allowed as source; tighten or widen per your security policy (e.g. load-generator subnet CIDR if you prefer).

### D. Add the same rule on every NSG attached to the DB System

Many DB Systems use **NSGs** in addition to subnet security lists. If **either** blocks traffic, connection fails.

1. OCI → your **DB System** → **Network** section → click each **Network Security Group** link.
2. **Network Security Group details** → **Add Rules** → **Ingress Rule**.
3. Use the **same** values as the table in step C (Source **`10.0.0.173/32`**, TCP, destination **1521**).
4. Repeat for **each** NSG attached to the **DB nodes** or **DB System** if multiple.

### E. Why you may need more than “SCAN IP” rules

RAC **SCAN** gets the first connection; the listener may **redirect** to a **node VIP** on another IP in the same (or related) subnet. An ingress rule that only allows the three SCAN IPs but **not** the **VIP** subnet can still produce **`ORA-12543`**. Using **source `10.0.0.173/32` + destination port `1521`** on the **DB subnet / NSG** that fronts those listeners typically fixes **SCAN + VIP** as long as those addresses are reached through that security context.

If VIPs sit on a **different subnet** with a **different** security list, add the **same** ingress rule there too (or use a **broader** DB CIDR your org allows).

### F. Egress on the HammerDB side (usually not the issue)

Default subnet security lists allow **egress to 0.0.0.0/0**. If your HammerDB subnet uses a **locked-down** custom list with **no egress**, add **egress** allowing **TCP** to the **DB subnet CIDR** on port **1521** (or egress to **`0.0.0.0/0`** for TCP if policy allows). **Listener reachability failures** are usually **ingress on DB**, but symmetric rules matter in strict environments.

### G. Verify after changes (on the HammerDB VM)

Wait **~30–60 seconds** for rules to apply, then:

```bash
# Replace with your SCAN IPs from nslookup / getent
for ip in 10.0.0.29 10.0.0.91 10.0.0.238; do
  timeout 3 bash -c "echo >/dev/tcp/${ip}/1521" && echo "${ip}: OK" || echo "${ip}: FAIL"
done
```

Then:

```bash
sqlplus -L system@YOUR_TNS_ALIAS
```

### H. Checklist (OCI)

- [ ] **Source IP** in rules is the HammerDB **private** IP (**`/32`**), not a typo (**`10.0.1.173`** vs **`10.0.0.173`**).
- [ ] Rules added on **DB** VCN **subnet security list(s)** that apply to listener endpoints.
- [ ] Same rules on **all NSGs** tied to the DB System / nodes.
- [ ] If cross-VCN: **peering** + **route tables** allow HammerDB subnet → DB subnet.
- [ ] **TCP 1521** tests **OK** before relying on **`sqlplus`**.

### I. If it still fails

1. Confirm **DB System** is **RUNNING** and **listener** is up (DBA: `lsnrctl status` on node if allowed).
2. Confirm **no** conflicting **NACL** (if using advanced networking outside OCI defaults).
3. Re-check **Service** name in **`sqlplus`** — **`ORA-12514`** is different from **`ORA-12543`** (network vs service registration).
