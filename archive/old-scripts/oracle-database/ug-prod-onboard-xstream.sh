#!/bin/bash
# Add ORDERMGMT.MTX* tables only to XStream capture/apply (outbound server rules).
# Prereqs: supplemental logging / grants per your DBA process; run 11-add-table-to-cdc.sql pattern.
# Usage: ./ug-prod-onboard-xstream.sh
# Requires: sqlplus, ORACLE_PWD
# Conn: c##xstrmadmin@//host:1521/SERVICE as sysdba
#
# Aligns with connector table.include.list=ORDERMGMT\.MTX.* and HammerDB MTX custom driver workload.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADD_TABLE="11-add-table-to-cdc.sql"

TABLES=(
  "ORDERMGMT.MTX_BNSART_RANGE_DETAILS"
  "ORDERMGMT.MTX_BATCH_PAYMENT"
  "ORDERMGMT.MTX_USER_BANK_SWEEP_DTLS"
  "ORDERMGMT.MTX_BATCHES"
  "ORDERMGMT.MTX_BNSART_RANGE"
  "ORDERMGMT.MTX_TRANSACTION_APPROVAL"
  "ORDERMGMT.MTX_AMBIGUOUS_TXN_DETAILS"
  "ORDERMGMT.MTX_PARTY_ACCESS"
  "ORDERMGMT.MTX_PARTY"
  "ORDERMGMT.MTX_ADMIN_AUDIT_TRAIL"
  "ORDERMGMT.MTX_AUDIT_TRAIL"
  "ORDERMGMT.MTX_PARTY_BARRED_HIST"
  "ORDERMGMT.MTX_COMMISSION_RANGE"
  "ORDERMGMT.MTX_COMMISSION_RANGE_DETAILS"
  "ORDERMGMT.MTX_TRANSACTION_HEADER_META"
  "ORDERMGMT.MTX_SERVICE_CHARGE"
  "ORDERMGMT.MTX_SERVICE_CHARGE_RANGE"
  "ORDERMGMT.MTX_SERV_CHRG_RANGE_DETAILS"
  "ORDERMGMT.MTX_PARTY_BLACK_LIST"
  "ORDERMGMT.MTX_CHURN_USERS"
  "ORDERMGMT.MTX_TRANSACTION_HEADER"
  "ORDERMGMT.MTX_WALLET"
  "ORDERMGMT.MTX_WALLET_BALANCES"
  "ORDERMGMT.MTX_TRANSACTION_ITEMS"
)

# Connection string - override via env
: "${ORACLE_CONN:=//localhost:1521/XSTRPDB}"
: "${ORACLE_USER:="c##xstrmadmin"}"

echo "Adding ORDERMGMT.MTX* tables to XStream (${#TABLES[@]} tables)..."
cd "$SCRIPT_DIR"
for t in "${TABLES[@]}"; do
  echo "Adding $t..."
  sqlplus -S "${ORACLE_USER}/${ORACLE_PWD:?Set ORACLE_PWD}@${ORACLE_CONN} as sysdba" "@${ADD_TABLE}" "$t" || true
done

echo ""
if [ -n "${ONBOARD_VM_IP:-}" ]; then
  echo "Running onboard-tables-deploy-on-vm.sh on $ONBOARD_VM_IP..."
  ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "opc@${ONBOARD_VM_IP}" \
    "cd ~/oracle-xstream-cdc-poc 2>/dev/null || cd /home/opc/oracle-xstream-cdc-poc && ./docker/scripts/onboard-tables-deploy-on-vm.sh" \
    || echo "SSH failed - run onboard-tables-deploy-on-vm.sh manually on VM"
else
  echo "Next steps (run on VM where Kafka/Connect run):"
  echo "  1. ./docker/scripts/onboard-tables-deploy-on-vm.sh   # precreate topics, sync connector, restart"
  echo "  2. Verify rules: sqlplus ... @oracle-database/verify-mtx-xstream-rules.sql"
  echo ""
  echo "Or set ONBOARD_VM_IP to auto-run step 1 via SSH: ONBOARD_VM_IP=<vm-ip> ./ug-prod-onboard-xstream.sh"
fi
