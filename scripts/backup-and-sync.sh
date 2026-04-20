#!/bin/bash
# Backup project and sync to OCI VM
# Run from project root: ./scripts/backup-and-sync.sh <vm-ip>
# Example: ./scripts/backup-and-sync.sh 137.131.53.98

set -e

VM_IP="${1:?Usage: ./scripts/backup-and-sync.sh <vm-ip>}"
SSH_KEY="${SSH_KEY:-$HOME/Desktop/Mani/ssh-key-2026-03-12.key}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$(dirname "$PROJECT_ROOT")"

cd "$PROJECT_ROOT"

echo "=== 1. Backup ==="
BACKUP_FILE="$BACKUP_DIR/oracle-xstream-cdc-poc-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$BACKUP_FILE" -C "$BACKUP_DIR" "$(basename "$PROJECT_ROOT")"
echo "Backup: $BACKUP_FILE"

echo ""
echo "=== 2. Sync to VM ==="
scp -i "$SSH_KEY" -r -o ConnectTimeout=15 "$PROJECT_ROOT" opc@"$VM_IP":~/oracle-xstream-cdc-poc-fresh
echo "Synced to opc@$VM_IP:~/oracle-xstream-cdc-poc-fresh"

echo ""
echo "=== 3. Run on VM (SSH in and run): ==="
echo "  cd ~"
echo "  mv oracle-xstream-cdc-poc oracle-xstream-cdc-poc-old-\$(date +%Y%m%d)"
echo "  mv oracle-xstream-cdc-poc-fresh oracle-xstream-cdc-poc"
echo "  cd oracle-xstream-cdc-poc"
echo "  ./docker/scripts/bring-up.sh"
