#!/usr/bin/env bash
# Kafka broker images set KAFKA_OPTS with a JMX exporter that binds :9990; a second JVM
# (e.g. kafka-topics) then fails with BindException. Clear KAFKA_OPTS for CLI tools.
# Usage (Connect VM): ./docker/scripts/kafka-topics-no-jmx.sh --list
#   ./docker/scripts/kafka-topics-no-jmx.sh --delete --topic __orcl-schema-changes.racdb
set -euo pipefail
exec docker exec -e KAFKA_OPTS= kafka1 kafka-topics "$@" --bootstrap-server kafka1:29092
