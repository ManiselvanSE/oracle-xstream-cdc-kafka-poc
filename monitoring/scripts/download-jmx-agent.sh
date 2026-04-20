#!/bin/bash
# Download Prometheus JMX Exporter Java agent
# Run from project root: ./monitoring/scripts/download-jmx-agent.sh
set -e
JMX_VERSION="${JMX_VERSION:-0.20.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$(dirname "$SCRIPT_DIR")/agents"
mkdir -p "$AGENTS_DIR"
JAR="$AGENTS_DIR/jmx_prometheus_javaagent-${JMX_VERSION}.jar"
URL="https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/${JMX_VERSION}/jmx_prometheus_javaagent-${JMX_VERSION}.jar"
if [ -f "$JAR" ]; then
  echo "JMX agent already exists: $JAR"
  exit 0
fi
echo "Downloading JMX Prometheus Java agent ${JMX_VERSION}..."
curl -sL -o "$JAR" "$URL"
echo "Downloaded: $JAR"
