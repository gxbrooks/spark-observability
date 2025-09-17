#!/bin/bash
set -eo pipefail # Add this for robust error handling

SPARK_WORKLOAD=$1
HOST_IP=$(hostname -i)
HOST_NAME=$(hostname)

echo "SPARK_WORKLOAD: $SPARK_WORKLOAD"
echo "Container IP Address: $HOST_IP"
echo "Container Hostname: $HOST_NAME"

# DNS resolution handling based on role
if [ "$SPARK_WORKLOAD" == "master" ]; then
  # For master only: Set up proper hostname resolution
  echo "Setting up master hostname resolution"
  echo "$HOST_IP $HOST_NAME spark-master spark-master.spark.svc.cluster.local" >> /etc/hosts
  
  # Set SPARK_LOCAL_IP and SPARK_LOCAL_HOSTNAME for better network binding
  export SPARK_LOCAL_IP=$HOST_IP
  export SPARK_LOCAL_HOSTNAME=$HOST_NAME
  echo "Starting Spark master at $SPARK_LOCAL_HOSTNAME:7077"
  start-master.sh -p 7077
elif [ "$SPARK_WORKLOAD" == "worker" ]; then
  # For workers: Configure local environment but don't change hosts file
  export SPARK_LOCAL_IP=$HOST_IP
  export SPARK_LOCAL_HOSTNAME=$HOST_NAME
  
  # Multiple master discovery methods, with fallbacks
  echo "Attempting to discover Spark master..."
  
  # Method 1: Standard Kubernetes DNS
  if getent hosts spark-master.spark.svc.cluster.local > /dev/null; then
    MASTER_HOST="spark-master.spark.svc.cluster.local"
    echo "Resolved master via Kubernetes DNS: $MASTER_HOST"
  # Method 2: Simple service name
  elif getent hosts spark-master > /dev/null; then
    MASTER_HOST="spark-master"
    echo "Resolved master via simple name: $MASTER_HOST"
  # Method 3: From environment variable
  elif [ ! -z "$SPARK_MASTER_HOST_IP" ]; then
    MASTER_HOST="$SPARK_MASTER_HOST_IP"
    echo "Using master IP from environment: $MASTER_HOST"
  # Fallback
  else
    MASTER_HOST="spark-master"
    echo "Warning: Cannot resolve spark-master, using default name"
  fi
  
  echo "Connecting worker to Spark master at $MASTER_HOST:7077"
  start-worker.sh spark://$MASTER_HOST:7077
elif [ "$SPARK_WORKLOAD" == "history" ]; then
  # For history server: Similar to worker configuration
  export SPARK_LOCAL_IP=$HOST_IP
  export SPARK_LOCAL_HOSTNAME=$HOST_NAME
  echo "Starting Spark history server"
  start-history-server.sh
else
  # For client commands (pyspark, spark-shell, etc.)
  echo "Setting up client environment"
  export SPARK_LOCAL_IP=$HOST_IP
  export SPARK_LOCAL_HOSTNAME=$HOST_NAME
  
  # Try to resolve the master for client commands
  if ! getent hosts spark-master > /dev/null; then
    echo "Warning: spark-master not resolvable, client operations may fail"
    echo "Available DNS entries:"
    getent hosts
  fi
  
  # Execute the provided command
  echo "Executing command: $@"
  exec "$@" # This executes the command passed as arguments to the container
fi
