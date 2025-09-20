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
    # First try from the environment variable
    master_host=${SPARK_MASTER_HOST:-"spark-master-headless.spark.svc.cluster.local"}
    hostname_check=$(check_dns "$master_host" || 
                    check_dns "spark-master-0.spark-master-headless.spark.svc.cluster.local" || 
                    check_dns "spark-master" || 
                    check_dns "localhost")
    
    # For port binding, check both localhost and the configured hostname
    local_port_check=$(check_port "localhost" "7077" && check_port "localhost" "8080")
    exit $((hostname_check + local_port_check))
    ;;
  "worker")
    # For worker: Verify it can see the master
    # Try multiple possible hostnames for the master, preferring the one in the environment
    
    # Check if we have a direct IP connection to the master (best option)
    if grep -q "spark-master" /etc/hosts; then
      master_entry=$(grep "spark-master" /etc/hosts)
      master_ip=$(echo "$master_entry" | awk '{print $1}')
      master_host="$master_ip"
      echo "✓ Found master entry in /etc/hosts: $master_entry"
    else
      # Fall back to environment variable or default hostname
      master_host=${SPARK_MASTER_HOST:-"spark-master-0.spark-master-headless.spark.svc.cluster.local"}
      
      # Test DNS resolution with multiple fallbacks
      if check_dns "spark-master-0.spark-master-headless.spark.svc.cluster.local"; then
        echo "✓ DNS resolution for spark-master-0.spark-master-headless.spark.svc.cluster.local successful"
        master_host="spark-master-0.spark-master-headless.spark.svc.cluster.local"
      elif check_dns "$master_host"; then
        echo "✓ DNS resolution for $master_host successful"
      elif check_dns "spark-master"; then
        echo "✓ DNS resolution for spark-master successful"
        master_host="spark-master"
      elif check_dns "spark-master-headless.spark.svc.cluster.local"; then
        echo "✓ DNS resolution for spark-master-headless.spark.svc.cluster.local successful"
        master_host="spark-master-headless.spark.svc.cluster.local"
      # Last resort - try the hardcoded IP we observed
      else
        echo "⚠ DNS resolutions failed, trying hardcoded IP 10.244.0.51"
        master_host="10.244.0.51"
      fi
    fi
    
    # Now check port connectivity
    if check_port "$master_host" "7077"; then
      echo "✓ Port connectivity to $master_host:7077 successful"
      exit 0
    else
      echo "✗ Port connectivity check failed for $master_host:7077"
      
      # One last attempt with the pod IP
      if check_port "10.244.0.51" "7077"; then
        echo "✓ Direct IP connectivity to 10.244.0.51:7077 successful"
        # Add this to /etc/hosts for future use
        echo "10.244.0.51 spark-master-0.spark-master-headless.spark.svc.cluster.local spark-master spark-master.spark.svc.cluster.local spark-master-headless.spark.svc.cluster.local" >> /etc/hosts
        exit 0
      else
        echo "✗ All connectivity attempts failed"
        exit 1
      fi
    fi
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
