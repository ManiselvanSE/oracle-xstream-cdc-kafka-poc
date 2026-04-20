#!/bin/bash
# Copy Oracle JARs from mounted Instant Client into connector plugin lib
# Required for OCI driver - connector classloader loads from plugin lib only
CONNECTOR_LIB="/usr/share/confluent-hub-components/confluentinc-kafka-connect-oracle-xstream-cdc-source/lib"
ORACLE_LIB="/opt/oracle/instantclient"
if [ -f "$ORACLE_LIB/ojdbc8.jar" ]; then
  cp -f "$ORACLE_LIB/ojdbc8.jar" "$CONNECTOR_LIB/" 2>/dev/null || true
fi
if [ -f "$ORACLE_LIB/xstreams.jar" ]; then
  cp -f "$ORACLE_LIB/xstreams.jar" "$CONNECTOR_LIB/" 2>/dev/null || true
fi
exec /etc/confluent/docker/run
