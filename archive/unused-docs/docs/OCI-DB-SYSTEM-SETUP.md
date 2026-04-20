# OCI DB System Setup – Oracle Base Database

Reference screenshots and configuration for the Oracle RAC DB System used with the XStream CDC pipeline. **Sensitive details (public IPs, OCIDs, compartment paths, connection strings) are masked below.**

> **Note:** The [Create Oracle Base Database](https://docs.oracle.com/en/cloud/paas/db-shared/create-dbcs.html) documentation may not be directly accessible from all links. Use **OCI Console → Oracle Base Database Service → DB Systems** to create and manage your DB System.

---

## Screenshot 1: DB System Information

Shows the main details page for an Oracle RAC DB System on OCI.

![OCI DB System - General Information and Network (sensitive details redacted)](../screenshots/oci-db-system-info.png)

### Masked Configuration (sensitive values redacted)

| Field | Value (example / masked) |
|-------|-------------------------|
| Name | Mani_RACDB |
| Status | Available |
| Compartment | `[REDACTED]` |
| Availability Domain | PHX-AD-1 |
| OCID | `[REDACTED]` |
| Shape | VM.Standard.E5.Flex |
| CPU Core Count | 8 |
| Oracle Database Software Edition | Enterprise Edition Extreme Performance |
| Storage Management | Oracle Grid Infrastructure |
| VCN | xstrm-connect-db2 |
| Client Subnet | public subnet-xstrm-connect-db2 |
| Cluster Name | xstrmracdb |
| Port | 1521 |
| Hostname Prefix | racdb |
| Host Domain Name | `[REDACTED].oraclevcn.com` |
| SCAN DNS Name | `racdb-scan.[REDACTED].oraclevcn.com` |
| SCAN IP Addresses | `[REDACTED]` |

---

## Screenshot 2: DB System Nodes (RAC)

Shows the Nodes tab for a 2-node Oracle RAC configuration.

![OCI DB System - Nodes (sensitive details redacted)](../screenshots/oci-db-system-nodes.png)

### Masked Configuration (sensitive values redacted)

| Node | State | DNS Name | Public IP | Floating IP | Private IP |
|------|-------|----------|-----------|-------------|------------|
| racdb1 | Available | racdb1.[REDACTED].oraclevcn.com | `[REDACTED]` | `[REDACTED]` | `[REDACTED]` |
| racdb2 | Available | racdb2.[REDACTED].oraclevcn.com | `[REDACTED]` | `[REDACTED]` | `[REDACTED]` |

**Connector connectivity:** Kafka Connect uses the **SCAN DNS name** (e.g. `racdb-scan.<vcn>.oraclevcn.com`) on port 1521. Ensure the Connector VM’s subnet can reach the DB System subnet (security lists / NSGs).

---

## Redaction Applied

The screenshots above have been redacted to hide:
- Public IP addresses
- OCID and compartment path
- SCAN IP addresses
- Host domain names and connection strings
- Node table details (IPs, DNS)
