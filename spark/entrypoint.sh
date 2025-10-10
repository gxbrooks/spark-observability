#!/bin/bash

# DEPRECATED: This script is no longer used
# Standard Apache Spark image now uses built-in scripts with runtime environment variables

set -euo pipefail

ROLE=${1:-}

if [ -z "$ROLE" ]; then
  echo "Usage: $0 [master|worker|history|client]"
  exit 1
fi

case "$ROLE" in
  master)
    : "${SPARK_MASTER_HOST:?SPARK_MASTER_HOST not set}"
    : "${SPARK_MASTER_PORT:?SPARK_MASTER_PORT not set}"
    echo "Starting Spark master at ${SPARK_MASTER_HOST}:${SPARK_MASTER_PORT}"
    exec start-master.sh -p "${SPARK_MASTER_PORT}" --host "${SPARK_MASTER_HOST}"
    ;;
  worker)
    : "${SPARK_MASTER:?SPARK_MASTER (spark://host:port) not set}"
    echo "Connecting worker to ${SPARK_MASTER}"
    exec start-worker.sh "${SPARK_MASTER}"
    ;;
  history)
    echo "Starting Spark History Server"
    exec start-history-server.sh
    ;;
  client)
    exec bash
    ;;
  *)
    echo "Unknown role: $ROLE" >&2
    exit 1
    ;; 
esac
