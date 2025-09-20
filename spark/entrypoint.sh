#!/bin/bash
set -eo pipefail # Add this for robust error handling

SPARK_WORKLOAD=$1
HOST_IP=$(hostname -i)
HOST_NAME=$(hostname)

echo "SPARK_WORKLOAD: $SPARK_WORKLOAD"
echo "Container IP Address: $HOST_IP"
echo "Container Hostname: $HOST_NAME"

# Set common environment variables for all Spark components
export SPARK_LOCAL_IP=$HOST_IP
export SPARK_LOCAL_HOSTNAME=$HOST_NAME

# Set network timeout environment variables from ConfigMap
export SPARK_NETWORK_TIMEOUT=${SPARK_NETWORK_TIMEOUT:-600s}
export SPARK_RPC_ASKTIME=${SPARK_RPC_ASK_TIMEOUT:-60s}
export SPARK_RPC_LOOKUPTIME=${SPARK_RPC_LOOKUP_TIMEOUT:-60s}
export SPARK_EXECUTOR_HEARTBEAT_INTERVAL=${SPARK_EXECUTOR_HEARTBEAT_INTERVAL:-120s}

# Ensure the event logs directory exists (needed for all components)
EVENTS_DIR=${SPARK_EVENTS_DIR:-/mnt/spark-events}
if [ ! -d "$EVENTS_DIR" ]; then
  echo "Creating Spark events directory: $EVENTS_DIR"
  mkdir -p "$EVENTS_DIR" 2>/dev/null || echo "Warning: Failed to create $EVENTS_DIR directory"
else
  # Just check if directory is accessible without listing contents
  if [ -r "$EVENTS_DIR" ] && [ -w "$EVENTS_DIR" ]; then
    echo "Verified Spark events directory is accessible: $EVENTS_DIR"
  else
    echo "WARNING: Spark events directory exists but may not be accessible: $EVENTS_DIR"
  fi
fi

# DNS resolution handling based on role
if [ "$SPARK_WORKLOAD" == "master" ]; then
  # For master only: Set up proper hostname resolution
  echo "Setting up master hostname resolution"
  echo "$HOST_IP $HOST_NAME spark-master spark-master.spark.svc.cluster.local spark-master-headless.spark.svc.cluster.local spark-master-0.spark-master-headless.spark.svc.cluster.local" >> /etc/hosts
  
  # Use the hostname from the ConfigMap if available, otherwise default to a stable DNS name
  if [ ! -z "$SPARK_MASTER_HOST" ]; then
    export SPARK_LOCAL_HOSTNAME=$SPARK_MASTER_HOST
    echo "Using SPARK_MASTER_HOST from ConfigMap: $SPARK_MASTER_HOST"
  else
    export SPARK_LOCAL_HOSTNAME="spark-master-headless.spark.svc.cluster.local"
    echo "Using default hostname: $SPARK_LOCAL_HOSTNAME"
  fi
  
  echo "Starting Spark master at $SPARK_LOCAL_HOSTNAME:7077"
  start-master.sh -p 7077 --host $SPARK_LOCAL_HOSTNAME
elif [ "$SPARK_WORKLOAD" == "worker" ]; then
  # For workers: Configure local environment and update hosts file for reliable DNS
  
  # Multiple master discovery methods, with fallbacks
  echo "Attempting to discover Spark master..."
  
  # Use the Kubernetes pod discovery to find the master's IP directly
  # This avoids relying on potentially broken DNS resolution
  if getent hosts spark-master-0.spark-master-headless.spark.svc.cluster.local > /dev/null; then
    MASTER_HOST="spark-master-0.spark-master-headless.spark.svc.cluster.local"
    echo "Resolved master via StatefulSet DNS: $MASTER_HOST"
    
    # Extract the IP address for direct connectivity
    MASTER_IP=$(getent hosts $MASTER_HOST | awk '{ print $1 }')
    if [[ "$MASTER_IP" == "192.168."* || "$MASTER_IP" == "10."* ]]; then
      echo "Found valid-looking master IP: $MASTER_IP"
      
      # Add to hosts file for reliable local resolution
      echo "$MASTER_IP $MASTER_HOST spark-master spark-master.spark.svc.cluster.local spark-master-headless.spark.svc.cluster.local" >> /etc/hosts
      echo "Added master to hosts file for reliable resolution"
    else
      echo "Warning: Master IP $MASTER_IP doesn't look like a valid internal IP"
    fi
  # Try to get it from the Kubernetes service
  elif getent hosts spark-master-headless.spark.svc.cluster.local > /dev/null; then
    MASTER_HOST="spark-master-headless.spark.svc.cluster.local"
    echo "Resolved master via headless service: $MASTER_HOST"
  # Method 2: Simple service name
  elif getent hosts spark-master > /dev/null; then
    MASTER_HOST="spark-master"
    echo "Resolved master via simple name: $MASTER_HOST"
  # Method 3: From environment variable
  elif [ ! -z "$SPARK_MASTER_HOST_IP" ]; then
    MASTER_HOST="$SPARK_MASTER_HOST_IP"
    echo "Using master IP from environment: $MASTER_HOST"
  # Fallback - hard-code the master pod IP we observed
  else
    MASTER_HOST="10.244.0.51"
    echo "Warning: Could not resolve master, using hard-coded IP: $MASTER_HOST"
    # Add hard-coded entry to hosts file as a last resort
    echo "$MASTER_HOST spark-master-0.spark-master-headless.spark.svc.cluster.local spark-master spark-master.spark.svc.cluster.local spark-master-headless.spark.svc.cluster.local" >> /etc/hosts
  fi
  
  echo "Connecting worker to Spark master at $MASTER_HOST:7077"
  start-worker.sh spark://$MASTER_HOST:7077
elif [ "$SPARK_WORKLOAD" == "history" ]; then
  # For history server: use spark-defaults.conf settings
  
  echo "Starting Spark history server"
  
  # Print spark-defaults.conf content for debugging
  if [ -f "/opt/spark/conf/spark-defaults.conf" ]; then
    echo "Contents of spark-defaults.conf:"
    cat /opt/spark/conf/spark-defaults.conf
  else
    echo "Warning: /opt/spark/conf/spark-defaults.conf not found!"
  fi
  
  # Start the history server using the settings in spark-defaults.conf
  start-history-server.sh
else
  # For client commands (pyspark, spark-shell, etc.)
  echo "Setting up client environment"
  
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
