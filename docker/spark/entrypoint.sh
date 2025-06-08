#!/bin/bash

SPARK_WORKLOAD=$1

# "elastic-agent run" will not start a new agent if one is already running
# use a non-zero exit, if for some reason the systemctl fails
# systemctl start elastic-agent && exit 23 
# systemctl start elastic-agent 

# Run Elastic Agent at the host level
# echo "Starting Elastic Agent"
# # "elastic-agent run" will not start a new agent if one is already running
# /usr/bin/elastic-agent run &


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
