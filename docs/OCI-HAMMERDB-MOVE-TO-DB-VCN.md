# Move HammerDB into the RAC DB VCN (`xstrm-connect-db2`)

OCI **does not** let you attach an existing instance’s primary VNIC to a **different** VCN. You **recreate** the workload in the target VCN using one of the paths below.

**Target (from your layout):** VCN **`xstrm-connect-db2`**, typically the same **client subnet** as RAC: **`public subnet-xstrm-connect-db2`** (or a **new private subnet** in that VCN if you prefer no public IP).

---

## Step-by-step: Recreate the VM in `xstrm-connect-db2` (OCI Console)

Follow these in order. Region should match your RAC (e.g. **US West Phoenix**).

### Part 1 — Confirm subnet and firewall (5–10 min)

1. Sign in to **OCI Console** → **☰ Menu** → **Networking** → **Virtual Cloud Networks**.
2. Click the VCN named **`xstrm-connect-db2`**.
3. In the left menu under **Resources**, click **Subnets**.
4. Click **`public subnet-xstrm-connect-db2`** (same subnet as your working Connector VM).
5. Note the **Subnet OCID** (optional) and **Security List** link(s) attached to this subnet.
6. Open the **Security List** (e.g. **`racdbsl`** or the list shown on the subnet).
7. Under **Ingress Rules**, confirm:
   - **TCP 22** from where you SSH from (your IP, Bastion, or **`0.0.0.0/0`** for lab only).
   - **TCP 1521** from **HammerDB / client** sources (e.g. **`10.0.0.0/24`** to RAC listeners — your existing rule may already apply once the new VM gets an IP in this subnet).
8. If **SSH (22)** is missing for your admin path, add an **Ingress rule** before testing the new VM.

### Part 2 — Create a new compute instance in that VCN

1. **☰ Menu** → **Compute** → **Instances**.
2. Click **Create instance**.
3. **Name:** e.g. `hammerdb-client-db2` (any name you like).
4. **Compartment:** Same as your other VMs (e.g. `mani_cflt` / project compartment).
5. **Placement:**
   - **Availability domain:** Choose one that **lists** the subnet you will use (if the UI filters subnets by AD, pick the AD that contains **`public subnet-xstrm-connect-db2`**).
6. **Image and shape:**
   - Click **Change image** → **OS images** → pick **Oracle Linux** (e.g. **9** to match your HammerDB RPM) or the same major version as your old VM.
   - Click **Change shape** → select **VM.Standard.E5.Flex** (or same shape as old HammerDB) → set **OCPUs** / **memory** as needed.
7. **Networking:**
   - **Primary VNIC** → **Specify a VCN** (do not use “Create new virtual cloud network”).
   - **Virtual cloud network:** `xstrm-connect-db2`.
   - **Subnet:** `public subnet-xstrm-connect-db2`.
   - **Public IPv4 address:** **Assign public IPv4 address** if you SSH from the Internet **without** Bastion; otherwise **Ephemeral** or **None** and use **OCI Bastion** / private access.
   - **Network security groups:** Leave **None** unless your org uses NSGs for this subnet.
8. **Add SSH keys:**
   - **Generate a key pair for me** (download the private key once), **or**
   - **Upload public key** / **Paste public key** — use the **same** key you use for `opc` on other VMs so your existing `ssh -i ... opc@...` works.
9. **Boot volume:** Optional — increase size if you had a large disk on the old VM.
10. Click **Create** (bottom of page).
11. Wait until **State** = **Running** and **Provisioning** = complete (instance detail page).

### Part 3 — Get connection details

1. Open the **new instance** → **Instance access** (or **Primary VNIC**).
2. Copy:
   - **Public IP** (if assigned) for `ssh opc@IP`,
   - **Private IP** (e.g. `10.0.0.x`) for documentation and firewall rules.
3. From your laptop:

   ```bash
   ssh -i /path/to/your.key opc@<PUBLIC_IP>
   ```

   If **no public IP**, use **OCI Bastion** or a **jump host** in the same VCN to SSH to the **private IP**.

### Part 4 — Install HammerDB stack on the new VM (same as before)

On the new host (as `opc`):

1. Update and install Oracle Instant Client + SQL\*Plus tools (see `oracle-database/hammerdb-client-oracle-setup.sh`).
2. Install HammerDB RPM (see `docs/HAMMERDB-INSTALL.md` or `oracle-database/install-hammerdb-ol9.sh`).
3. Create TNS directory and copy **`tnsnames.ora`**:

   ```bash
   mkdir -p ~/oracle/network/admin
   # copy from repo: oracle-database/hammerdb-tnsnames.rac.example → ~/oracle/network/admin/tnsnames.ora
   ```

4. Copy **`oracle-database/hammerdb-oracle-env.sh`** and **`diagnose-hammerdb-rac-connectivity.sh`** (git clone or `scp` from your laptop).

5. Validate:

   ```bash
   source ~/oracle-xstream-cdc-poc/oracle-database/hammerdb-oracle-env.sh
   bash ~/oracle-xstream-cdc-poc/oracle-database/diagnose-hammerdb-rac-connectivity.sh
   sqlplus -L system@RAC_XSTRPDB_POC
   ```

### Part 5 — Cut over and remove the old VM

1. Point your **scripts/docs** to the **new** public/private IP and hostname.
2. **Stop** or **terminate** the old **`hammerdb-client`** in **`vcn-xstr`** when you no longer need it (**Compute** → instance → **Terminate**).

---

## Before you start (collect from the current `hammerdb-client`)

| Item | Where to find |
|------|----------------|
| **Shape** (e.g. VM.Standard.E5.Flex) | Compute → Instance → **Resources** |
| **Image** (OS) | Instance details |
| **SSH public key** | Your `~/.ssh` / OCI key used at create |
| **Boot volume size** | Block volumes / instance |
| **User data / setup** | Any **cloud-init** or manual steps (HammerDB RPM, Instant Client) |

You will **reinstall** HammerDB + Oracle Instant Client on the new VM **or** restore from a **custom image** (see Option B).

---

## Option A — New instance in `xstrm-connect-db2` (simplest to reason about)

### 1. Pick the subnet

1. **Networking** → **Virtual Cloud Networks** → **`xstrm-connect-db2`**.
2. **Subnets** → choose **`public subnet-xstrm-connect-db2`** (same as Connector) **or** create a **new subnet** in this VCN for load clients (recommended long-term: **private subnet** + **OCI Bastion** for SSH).

### 2. Security list on that subnet (ingress)

Ensure the subnet’s **Security List** allows at least:

| Direction | Source | Protocol | Ports | Purpose |
|-----------|--------|----------|-------|---------|
| **Ingress** | Your admin IP or **Bastion** CIDR | TCP | **22** | SSH |
| **Ingress** | **HammerDB VM private IP** or subnet CIDR (e.g. same subnet) | TCP | **1521** | Oracle (often already covered by **`10.0.0.0/24` → 1521** on **`racdbsl`** if the new IP stays in range) |

**Egress:** Default “allow all” is usually enough for the client to initiate outbound to RAC SCAN/VIPs.

### 3. Create the new compute instance

1. **Compute** → **Instances** → **Create instance**.
2. **Placement:** Compartment as needed; **AD** compatible with the subnet.
3. **Image and shape:** Match your old HammerDB VM (same OS family helps your scripts).
4. **Networking:**
   - **Primary VNIC** → VCN **`xstrm-connect-db2`**.
   - **Subnet** → **`public subnet-xstrm-connect-db2`** (or your new subnet).
   - **Assign public IPv4** → Yes if you SSH from the Internet without Bastion; No if you use Bastion/private only.
5. **SSH keys:** Paste the **same** public key you use today.
6. **Create**.

### 4. Install software on the new VM (same as before)

On the new host (as `opc` or your admin user):

- Oracle **Instant Client** + **SQL\*Plus** (see `oracle-database/hammerdb-client-oracle-setup.sh`).
- **HammerDB** RPM (see `docs/HAMMERDB-INSTALL.md`).
- Copy **`tnsnames.ora`** to **`~/oracle/network/admin/`** (see `oracle-database/hammerdb-tnsnames.rac.example`).
- **`source`** `oracle-database/hammerdb-oracle-env.sh`.

### 5. Validate connectivity

```bash
bash oracle-database/diagnose-hammerdb-rac-connectivity.sh
sqlplus -L system@RAC_XSTRPDB_POC
```

### 6. Cut over and decommission

1. Stop using the old **`hammerdb-client`** in **`vcn-xstr`** for benchmarks.
2. **Terminate** the old instance when you no longer need it (or keep stopped briefly for rollback).

---

## Option B — Custom image from the old instance (faster if OS is identical)

Use this if you want to **clone disks** and avoid full manual reinstall.

### 1. Create a **custom image** from the current instance

1. **Compute** → **Instances** → **`hammerdb-client`** → **More actions** → **Create custom image** (wording may vary slightly).
2. Wait until the image is **Available**.

### 2. Launch a **new** instance from that image

1. **Compute** → **Custom images** → select the image → **Create instance**.
2. **Networking:** VCN **`xstrm-connect-db2`**, subnet **`public subnet-xstrm-connect-db2`** (or chosen subnet).
3. **SSH keys**, **shape** (must be compatible with image), **Create**.

### 3. Fix host-specific settings

Custom images can carry **old hostnames**, **stale `/etc/hosts`**, or **NIC-specific** config. On first boot:

- Verify **`TNS_ADMIN`**, **`tnsnames.ora`**, **`ORACLE_HOME`** paths.
- Re-run **`diagnose-hammerdb-rac-connectivity.sh`**.

### 4. Decommission the old VM

After validation, **terminate** the old instance in **`vcn-xstr`** to avoid duplicate cost.

---

## Option C — Boot volume backup / restore (advanced)

Alternative to custom image: **boot volume backup** → **restore to new volume** → create instance from that volume in the new subnet. More steps; Option A or B is usually enough.

---

## Networking checklist (DB VCN)

After the new VM exists in **`xstrm-connect-db2`**:

- [ ] **Private IP** can open **TCP 1521** to **SCAN** (`10.0.0.29`, `.91`, `.238`) and **node VIPs** (same as Connector path).
- [ ] **Security list** `racdbsl` (or equivalent) allows **source** = new VM IP or subnet CIDR → **1521**.
- [ ] **No NSG** blocking on DB side (or NSG rules aligned — your RAC screenshot showed **no NSG** on DB System).

---

## Related

- **`docs/OCI-HAMMERDB-WHY-CONNECTOR-WORKS.md`** — why the move is needed.
- **`docs/OCI-HAMMERDB-RAC-1521.md`** — SCAN, VIP redirect, firewall.
- **`oracle-database/install-hammerdb-ol9.sh`** — repeatable HammerDB install.
