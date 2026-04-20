#!/bin/bash
# Copy updated docker/scripts from this repo to the Kafka Connect VM over SSH.
#
# Usage (from repo root or anywhere):
#   VM=137.131.53.98 SSH_KEY=$HOME/Desktop/Mani/ssh-key-2026-03-12.key ./scripts/push-connect-vm-docker-scripts.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${VM:?Set VM to the Connect VM public IP (e.g. 137.131.53.98)}"
: "${SSH_KEY:=$HOME/Desktop/Mani/ssh-key-2026-03-12.key}"
if [ ! -f "$SSH_KEY" ]; then
  echo "SSH key not found: $SSH_KEY" >&2
  exit 1
fi
SCRIPTS=(
  check-tpcc-kafka-offsets.sh
  validate-tpcc-cdc-pipeline.sh
  validate-mtx-cdc-pipeline.sh
  remediate-tpcc-zero-offsets.sh
  diagnose-tpcc-vs-ordermgmt-kafka.sh
  connector-recreate-full-snapshot.sh
  connector-recreate-streaming-only.sh
  connector-apply-streaming-only.sh
  connector-apply-initial-snapshot.sh
  sync-docker-connector-oracle-from-rac-json.sh
  deploy-connector.sh
  verify-cdc-stack.sh
  kafka-topics-no-jmx.sh
  delete-tpcc-kafka-topics.sh
  recreate-tpcc-kafka-topics.sh
  sync-connector-table-include-from-example.sh
  reset-tpcc-kafka-for-connector-json.sh
  check-ordermgmt-mtx-kafka-offsets.sh
  list-empty-kafka-topics.sh
)
for f in "${SCRIPTS[@]}"; do
  [ -f "$ROOT/docker/scripts/$f" ] || { echo "Missing $ROOT/docker/scripts/$f" >&2; exit 1; }
done
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
  $(for f in "${SCRIPTS[@]}"; do echo "$ROOT/docker/scripts/$f"; done) \
  "opc@${VM}:~/oracle-xstream-cdc-poc/docker/scripts/"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "opc@${VM}" \
  "chmod +x ~/oracle-xstream-cdc-poc/docker/scripts/"*.sh
echo "Pushed to opc@${VM}:~/oracle-xstream-cdc-poc/docker/scripts/"
echo "On VM: cd ~/oracle-xstream-cdc-poc && ./docker/scripts/validate-mtx-cdc-pipeline.sh && ./docker/scripts/check-ordermgmt-mtx-kafka-offsets.sh"
