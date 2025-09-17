#!/bin/bash
# Kubernetes readiness probe for Spark components

# This script is specifically designed for Kubernetes readiness probes
# Exit code 0 = Ready, any other exit code = Not Ready

COMPONENT=${1:-"unknown"}
echo "Running readiness probe for $COMPONENT"

# Check DNS resolution
check_dns() {
  getent hosts "$1" > /dev/null 2>&1
  return $?
}

# Check if a port is open
check_port() {
  timeout 2 bash -c ">/dev/tcp/$1/$2" 2>/dev/null
  return $?
}

case $COMPONENT in
  "master")
    # For master: Check self-resolution and port binding
    hostname_check=$(check_dns "spark-master-0.spark-master-headless.spark.svc.cluster.local" || 
                    check_dns "spark-master" || 
                    check_dns "localhost")
    port_check=$(check_port "localhost" "7077" && check_port "localhost" "8080")
    exit $((hostname_check + port_check))
    ;;
  "worker")
    # For worker: Verify it can see the master
    master_host=${SPARK_MASTER_HOST:-"spark-master-0.spark-master-headless.spark.svc.cluster.local"}
    check_dns "$master_host" && check_port "$master_host" "7077"
    exit $?
    ;;
  "history")
    # For history server: Just check web UI port
    check_port "localhost" "18080"
    exit $?
    ;;
  *)
    echo "Unknown component: $COMPONENT" >&2
    exit 1
    ;;
esac
