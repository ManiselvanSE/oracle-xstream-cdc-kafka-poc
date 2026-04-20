# Validation and Status Checks

---

## Oracle RAC Status

**When:** Before configuring XStream or connector; when troubleshooting connectivity.

**Where:** Run as `grid` user on any RAC node.

**Script:** [check_rac_res_status.sh](https://github.com/guestart/Linux-Shell-Scripts/blob/master/check_rac_res/check_rac_res_status.sh)

```bash
# Download and run (as grid user on RAC node)
curl -sLO https://raw.githubusercontent.com/guestart/Linux-Shell-Scripts/master/check_rac_res/check_rac_res_status.sh
chmod +x check_rac_res_status.sh
./check_rac_res_status.sh
```

**Expected output summary:**

| Section | Expected |
|---------|----------|
| Node Numbers | List of cluster nodes |
| ASM Status | Running on each node |
| Diskgroup Status | MOUNTED |
| Network | Running |
| VIP | Running on each node |
| SCAN VIP | Running |
| Listener | Running |
| SCAN Listener | Running |
| Database Instance | Open on each node |

**If DOWN:** Resolve RAC issues before XStream/connector setup. Refer to Oracle RAC documentation.
