#!/bin/bash
# Run Kafka load test from host - executes kafka-producer-perf-test inside Kafka container
# Usage: ./run-load-from-docker.sh <topic> <rate-events-per-sec> [message-size] [duration-sec]
#
# Example: ./run-load-from-docker.sh test-throughput 5000 1024 60

TOPIC="${1:?Usage: $0 <topic> <rate-events-per-sec> [message-size] [duration-sec]}"
RATE="${2:?Usage: $0 <topic> <rate-events-per-sec> [message-size] [duration-sec]}"
MSG_SIZE="${3:-1024}"
DURATION="${4:-60}"
NUM_RECORDS=$((RATE * DURATION))

echo "Topic: $TOPIC | Rate: $RATE/s | Size: ${MSG_SIZE}B | Duration: ${DURATION}s | Records: $NUM_RECORDS"
# Unset KAFKA_OPTS to avoid JMX agent port conflict (broker already uses it)
docker exec -e KAFKA_OPTS= kafka1 kafka-producer-perf-test \
  --topic "$TOPIC" \
  --num-records "$NUM_RECORDS" \
  --record-size "$MSG_SIZE" \
  --throughput "$RATE" \
  --producer-props bootstrap.servers=kafka1:29092,kafka2:29092,kafka3:29092
