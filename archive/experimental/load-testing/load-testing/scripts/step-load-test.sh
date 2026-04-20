#!/bin/bash
# Step load test: gradually increase throughput to find max capacity
# Usage: ./step-load-test.sh <topic> [message-size]
#
# Steps: 5K → 10K → 25K → 50K → 75K → 100K events/sec
# Each step runs 2 minutes. Monitor Grafana/Prometheus during test.

TOPIC="${1:?Usage: $0 <topic> [message-size]}"
MSG_SIZE="${2:-1024}"
STEP_DURATION=120

RATES=(5000 10000 25000 50000 75000 100000)

echo "=== Step Load Test: $TOPIC ==="
echo "Message size: ${MSG_SIZE}B | Step duration: ${STEP_DURATION}s"
echo "Steps: ${RATES[*]} events/sec"
echo ""

for RATE in "${RATES[@]}"; do
  echo ">>> Step: $RATE events/sec (${STEP_DURATION}s)"
  # Unset KAFKA_OPTS to avoid JMX agent port conflict
  docker exec -e KAFKA_OPTS= kafka1 kafka-producer-perf-test \
    --topic "$TOPIC" \
    --num-records $((RATE * STEP_DURATION)) \
    --record-size "$MSG_SIZE" \
    --throughput "$RATE" \
    --producer-props bootstrap.servers=kafka1:29092,kafka2:29092,kafka3:29092
  echo ">>> Step $RATE done. Waiting 30s before next step..."
  sleep 30
done

echo ""
echo "=== Step load test complete ==="
