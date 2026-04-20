#!/bin/bash
# Kafka load generator for throughput testing (Kafka → Flink pipeline)
# Usage: ./kafka-load-generator.sh <topic> <target-rate-events-per-sec> [message-size-bytes] [duration-sec]
#
# Examples:
#   ./kafka-load-generator.sh test-throughput 5000 1024 60    # 5K events/sec, 1KB msg, 60s
#   ./kafka-load-generator.sh test-throughput 10000 1024 120   # 10K events/sec
#   ./kafka-load-generator.sh racdb.ORDERMGMT.MTX_TRANSACTION_ITEMS 50000 1024 300  # 50K for 5min

set -e

TOPIC="${1:?Usage: $0 <topic> <target-rate-events-per-sec> [message-size-bytes] [duration-sec]}"
TARGET_RATE="${2:?Usage: $0 <topic> <target-rate-events-per-sec> [message-size-bytes] [duration-sec]}"
MSG_SIZE="${3:-1024}"
DURATION="${4:-60}"
BOOTSTRAP="${BOOTSTRAP_SERVERS:-localhost:9092}"

# For kafka-producer-perf-test: num-records = rate * duration
NUM_RECORDS=$((TARGET_RATE * DURATION))

echo "=== Kafka Load Generator ==="
echo "Topic:        $TOPIC"
echo "Target rate:  $TARGET_RATE events/sec"
echo "Message size: $MSG_SIZE bytes"
echo "Duration:     $DURATION seconds"
echo "Total records: $NUM_RECORDS"
echo "Bootstrap:    $BOOTSTRAP"
echo ""

# Use kafka-producer-perf-test if available (Confluent/Kafka)
if command -v kafka-producer-perf-test >/dev/null 2>&1; then
  echo "Using kafka-producer-perf-test..."
  kafka-producer-perf-test \
    --topic "$TOPIC" \
    --num-records "$NUM_RECORDS" \
    --record-size "$MSG_SIZE" \
    --throughput "$TARGET_RATE" \
    --producer-props bootstrap.servers="$BOOTSTRAP"
elif docker exec kafka1 which kafka-producer-perf-test >/dev/null 2>&1; then
  echo "Using kafka-producer-perf-test (via Docker)..."
  docker exec -e TOPIC="$TOPIC" -e NUM_RECORDS="$NUM_RECORDS" -e MSG_SIZE="$MSG_SIZE" -e TARGET_RATE="$TARGET_RATE" \
    kafka1 kafka-producer-perf-test \
    --topic "$TOPIC" \
    --num-records "$NUM_RECORDS" \
    --record-size "$MSG_SIZE" \
    --throughput "$TARGET_RATE" \
    --producer-props bootstrap.servers=kafka1:29092,kafka2:29092,kafka3:29092
else
  echo "kafka-producer-perf-test not found. Use Docker:"
  echo "  docker exec -it kafka1 kafka-producer-perf-test --topic $TOPIC --num-records $NUM_RECORDS --record-size $MSG_SIZE --throughput $TARGET_RATE --producer-props bootstrap.servers=kafka1:29092,kafka2:29092,kafka3:29092"
  echo ""
  echo "Or run from project root:"
  echo "  ./load-testing/scripts/run-load-from-docker.sh $TOPIC $TARGET_RATE $MSG_SIZE $DURATION"
  exit 1
fi
