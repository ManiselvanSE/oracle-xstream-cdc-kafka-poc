#!/bin/bash
# Check connector and Grafana status from your Mac (SSH to VM and run checks)
# Usage: ./scripts/status-from-mac.sh [vm-ip]
# Example: ./scripts/status-from-mac.sh 74.225.27.158
# Prereq: Set SSH_KEY and optionally VM_IP in the script or env

# Load config from project root (VM_IP, SSH_KEY)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$PROJECT_ROOT/.status-config" ] && source "$PROJECT_ROOT/.status-config" 2>/dev/null

VM_IP="${1:-${VM_IP:-74.225.27.158}}"
SSH_KEY="${SSH_KEY:-$HOME/Desktop/Mani/ssh-key-2026-03-12.key}"

# Try common key paths if default missing
if [ ! -f "$SSH_KEY" ]; then
  for k in "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519" "$PROJECT_ROOT/docker/ssh-key.pem"; do
    [ -f "$k" ] && SSH_KEY="$k" && break
  done
fi

if [ ! -f "$SSH_KEY" ]; then
  echo "SSH key not found: $SSH_KEY"
  echo "Set SSH_KEY env or pass VM_IP: ./scripts/status-from-mac.sh 74.225.27.158"
  echo "Or: SSH_KEY=/path/to/key ./scripts/status-from-mac.sh $VM_IP"
  exit 1
fi

echo "=== Oracle XStream CDC – Status from Mac ==="
echo "VM: $VM_IP"
echo ""

echo "--- Connector Status ---"
SSH_OUT=$(ssh -i "$SSH_KEY" -o ConnectTimeout=8 -o StrictHostKeyChecking=no \
  opc@"$VM_IP" "curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status 2>/dev/null | jq . 2>/dev/null" 2>&1)
if [[ "$SSH_OUT" == *"Operation timed out"* ]] || [[ "$SSH_OUT" == *"Connection refused"* ]]; then
  echo "Cannot reach VM at $VM_IP"
  echo "  $SSH_OUT"
  echo ""
  echo "  → Check VM is Running in OCI Console; IP may have changed if VM was restarted."
  echo "  → Verify OCI Security List allows SSH (port 22) from your IP."
  echo "  → Try: ssh -i $SSH_KEY opc@$VM_IP"
else
  echo "$SSH_OUT" | grep -q '.' && echo "$SSH_OUT" || echo "Connector not deployed or Connect not running on VM."
fi

echo ""
echo "--- Grafana Status ---"
GRAFANA=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 \
  opc@"$VM_IP" "curl -s -o /dev/null -w '%{http_code}' http://localhost:3000 2>/dev/null" 2>/dev/null)
if [ "$GRAFANA" = "302" ] || [ "$GRAFANA" = "200" ]; then
  echo "Grafana: UP (HTTP $GRAFANA)"
else
  echo "Grafana: DOWN or not reachable (HTTP $GRAFANA)"
fi

echo ""
echo "--- How to Access from Mac ---"
echo "1. Open a new terminal and run (keep it open):"
echo "   ssh -i $SSH_KEY -L 3000:localhost:3000 -L 8083:localhost:8083 -L 9090:localhost:9090 opc@$VM_IP"
echo ""
echo "2. Then in your browser:"
echo "   Grafana:    http://localhost:3000  (admin/admin)"
echo "   Connect:    http://localhost:8083/connectors"
echo "   Prometheus: http://localhost:9090"
echo ""
echo "3. Or check connector again from another terminal (after tunnel is up):"
echo "   curl -s http://localhost:8083/connectors/oracle-xstream-rac-connector/status | jq ."
