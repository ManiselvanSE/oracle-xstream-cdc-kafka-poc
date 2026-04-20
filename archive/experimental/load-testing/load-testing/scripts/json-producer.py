#!/usr/bin/env python3
"""
Kafka JSON load producer for throughput testing.
Generates CDC-like JSON messages for Kafka → Flink pipeline testing.

Usage: python json-producer.py <topic> <rate-events-per-sec> [message-size] [duration-sec]

Requires: pip install confluent-kafka
"""

import sys
import time
import json
import random
import string
from datetime import datetime

try:
    from confluent_kafka import Producer
except ImportError:
    print("Install: pip install confluent-kafka")
    sys.exit(1)


def random_string(size):
    return "".join(random.choices(string.ascii_letters + string.digits, k=size))


def generate_payload(target_size):
    """Generate JSON payload of approximately target_size bytes (CDC-like structure)."""
    base = {
        "before": None,
        "after": {
            "id": random.randint(1, 1000000),
            "data": random_string(32),
            "ts_ms": int(time.time() * 1000),
            "op": random.choice(["c", "u", "d"]),
        },
        "source": {"connector": "load-test", "table": "test"},
        "op": "c",
        "ts_ms": int(time.time() * 1000),
    }
    payload = json.dumps(base)
    if len(payload) < target_size:
        base["after"]["padding"] = random_string(target_size - len(payload) - 20)
        payload = json.dumps(base)
    return payload[:target_size] if len(payload) > target_size else payload


def main():
    if len(sys.argv) < 3:
        print("Usage: python json-producer.py <topic> <rate-events-per-sec> [message-size] [duration-sec]")
        print("Example: python json-producer.py test-throughput 5000 1024 60")
        sys.exit(1)

    topic = sys.argv[1]
    rate = int(sys.argv[2])
    msg_size = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    duration = int(sys.argv[4]) if len(sys.argv) > 4 else 60
    bootstrap = "localhost:9092"

    producer = Producer({"bootstrap.servers": bootstrap})
    interval = 1.0 / rate if rate > 0 else 0
    end_time = time.time() + duration
    sent = 0

    print(f"Topic: {topic} | Rate: {rate}/s | Size: ~{msg_size}B | Duration: {duration}s")
    print("Starting...")

    while time.time() < end_time:
        payload = generate_payload(msg_size)
        producer.produce(topic, value=payload.encode("utf-8"))
        sent += 1
        if interval > 0:
            time.sleep(interval)

    producer.flush()
    elapsed = duration
    actual_rate = sent / elapsed if elapsed > 0 else 0
    print(f"Done. Sent {sent} records in {elapsed:.1f}s (~{actual_rate:.0f} events/sec)")


if __name__ == "__main__":
    main()
