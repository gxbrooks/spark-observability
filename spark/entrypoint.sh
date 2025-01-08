#!/bin/bash

SPARK_WORKLOAD=$1

echo "Starting Elastic Agent"
# "elastic-agent run" will not start a new agent if one is already running
/usr/bin/elastic-agent run > /opt/Elastic/Agent/data/elastic-agent-8.15.0-25075f/logs/console.log 2>&1 &


# need to wrap Spark entrypoint.sh instead of copying it in

echo "SPARK_WORKLOAD: $SPARK_WORKLOAD"

if [ "$SPARK_WORKLOAD" == "master" ];
then
  start-master.sh -p 7077
elif [ "$SPARK_WORKLOAD" == "worker" ];
then
  start-worker.sh spark://spark-master:7077
elif [ "$SPARK_WORKLOAD" == "history" ]
then
  start-history-server.sh
fi
