#!/bin/bash
set -eo pipefail # Add this for robust error handling

SPARK_WORKLOAD=$1

echo "SPARK_WORKLOAD: $SPARK_WORKLOAD"

if [ "$SPARK_WORKLOAD" == "master" ]; then
  start-master.sh -p 7077
elif [ "$SPARK_WORKLOAD" == "worker" ]; then
  start-worker.sh spark://spark-master:7077
elif [ "$SPARK_WORKLOAD" == "history" ]; then
  start-history-server.sh
else
  # This is the crucial part for handling client commands like pyspark or bash
  echo "Executing command: $@"
  exec "$@" # This executes the command passed as arguments to the container
fi
