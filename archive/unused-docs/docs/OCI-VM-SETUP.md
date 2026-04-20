# OCI VM Setup for Oracle XStream CDC Connector

Step-by-step guide to create the Connector VM on Oracle Cloud Infrastructure.

---

## 1. Create VCN (Virtual Cloud Network)

### Console

1. OCI Console → **Networking** → **Virtual Cloud Networks**
2. **Start VCN Wizard** → **Create VCN with Internet Connectivity**
3. VCN name: `xstream-cdc-vcn`
4. CIDR: `10.0.0.0/16`
5. Create public and private subnets

### CLI

```bash
oci network vcn create \
  --compartment-id <compartment-ocid> \
  --display-name xstream-cdc-vcn \
  --cidr-blocks '["10.0.0.0/16"]'
```

---

## 2. Create Subnet

### Console

1. VCN → **Subnets** → **Create Subnet**
2. Name: `xstream-cdc-subnet`
3. Type: **Private**
4. CIDR: `10.0.1.0/24`

### CLI

```bash
oci network subnet create \
  --compartment-id <compartment-ocid> \
  --vcn-id <vcn-ocid> \
  --display-name xstream-cdc-subnet \
  --cidr-block 10.0.1.0/24 \
  --prohibit-public-ip-on-vnic true
```

---

## 3. Security List (Ingress Rules)

| Source | Port | Protocol | Purpose |
|--------|------|----------|---------|
| 0.0.0.0/0 or your IP | 22 | TCP | SSH |
| Subnet CIDR | 1521 | TCP | Oracle (from VM) |
| Subnet CIDR | 9092, 9094, 9095 | TCP | Kafka brokers |
| Subnet CIDR | 8083 | TCP | Kafka Connect REST |
| Subnet CIDR | 3000 | TCP | Grafana (optional) |

### CLI (add rule)

```bash
oci network security-list update \
  --security-list-id <security-list-ocid> \
  --ingress-security-rules '[{"source":"10.0.1.0/24","protocol":"6","tcpOptions":{"destinationPortRange":{"min":22,"max":22}}}]'
```

---

## 4. Create Compute VM

### Console

1. **Compute** → **Instances** → **Create Instance**
2. Name: `xstream-connector-vm`
3. Image: **Oracle Linux 9**
4. Shape: **VM.Standard.E4.Flex** (4 OCPUs, 16 GB RAM)
5. VCN: `xstream-cdc-vcn`, Subnet: `xstream-cdc-subnet`
6. SSH keys: Upload or paste public key

### CLI

```bash
oci compute instance launch \
  --compartment-id <compartment-ocid> \
  --availability-domain <ad-name> \
  --display-name xstream-connector-vm \
  --shape VM.Standard.E4.Flex \
  --shape-config '{"ocpus": 4, "memoryInGBs": 16}' \
  --source-details '{"sourceType":"image","imageId":"<oracle-linux-9-ocid>"}' \
  --subnet-id <subnet-ocid> \
  --ssh-authorized-keys-file ~/.ssh/id_rsa.pub
```

---

## 5. Attach Block Volume (Optional)

If you need extra storage for Kafka data:

### Console

1. **Block Storage** → **Block Volumes** → **Create**
2. Size: 100–500 GB
3. **Attached Instances** → Attach to `xstream-connector-vm`
4. SSH to VM, partition, format, mount (e.g. `/var/lib/kafka-data`)

---

## 6. Connect via Bastion (if private subnet)

If the VM has no public IP, use **Bastion** or **Bastion Session**:

1. Create Bastion in a public subnet
2. **Bastion** → **Create Session** → SSH
3. Use the generated command to connect

---

## Quick Reference

| Resource | Typical Value |
|----------|---------------|
| VCN CIDR | 10.0.0.0/16 |
| Subnet CIDR | 10.0.1.0/24 |
| VM shape | VM.Standard.E4.Flex (4 OCPUs, 16 GB) |
| OS | Oracle Linux 9 |
| Ports | 22, 1521, 9092, 9094, 9095, 8083, 3000 |
