#!/bin/bash
# Utility script to check the health of Spark components and restart them if necessary

# Exit immediately if a command exits with a non-zero status
set -e

function check_dns_resolution() {
  local host=$1
  echo "Checking DNS resolution for $host..."
  if getent hosts "$host" > /dev/null; then
    local ip=$(getent hosts "$host" | awk '{ print $1 }')
    echo "✓ DNS resolution successful for $host: $ip"
    return 0
  else
    echo "✗ DNS resolution failed for $host"
    # Try alternative DNS names
    for alt_host in "${host}.spark.svc.cluster.local" "${host}-0.${host}-headless.spark.svc.cluster.local"; do
      echo "  Trying alternative: $alt_host"
      if getent hosts "$alt_host" > /dev/null; then
        local alt_ip=$(getent hosts "$alt_host" | awk '{ print $1 }')
        echo "  ✓ Alternative resolution successful: $alt_host -> $alt_ip"
        echo "  Consider updating your configuration to use $alt_host instead"
      fi
    done
    return 1
  fi
}

function check_spark_master() {
  echo "Checking Spark Master health..."
  
  # Try multiple possible hostnames for the master
  local master_hosts=("spark-master" 
                    "spark-master-0.spark-master-headless.spark.svc.cluster.local" 
                    "spark-master.spark.svc.cluster.local" 
                    "localhost")
  
  for host in "${master_hosts[@]}"; do
    echo "Trying to connect to Spark master at $host:8080..."
    if curl -s --connect-timeout 5 "http://$host:8080/json/" | grep -q "status"; then
      echo "✓ Spark Master is healthy at $host"
      # If this isn't the preferred hostname, suggest updating configuration
      if [[ "$host" != "spark-master-0.spark-master-headless.spark.svc.cluster.local" ]]; then
        echo "⚠️ Consider updating your configuration to use the FQDN: spark-master-0.spark-master-headless.spark.svc.cluster.local"
      fi
      return 0
    fi
  done
  
  echo "✗ Spark Master health check failed on all hostnames"
  return 1
}

function restart_spark_master() {
  echo "Restarting Spark Master..."
  # In Kubernetes, we would use kubectl to restart the pod
  # For local testing purposes:
  stop-master.sh || true
  sleep 2
  start-master.sh -p 7077
  echo "Spark Master restarted"
}

function check_spark_worker() {
  local master=${1:-"spark-master-0.spark-master-headless.spark.svc.cluster.local"}
  echo "Checking Spark Worker connection to $master..."
  
  # First check if worker UI is accessible
  echo "Checking worker UI..."
  if ! curl -s --connect-timeout 5 "http://localhost:8081/json/" > /dev/null; then
    echo "✗ Worker UI is not accessible - worker may not be running"
    return 1
  fi
  
  # Check if worker is connected to any master
  local worker_status=$(curl -s --connect-timeout 5 "http://localhost:8081/json/")
  if echo "$worker_status" | grep -q "masterUrl"; then
    echo "✓ Worker is connected to a master"
    
    # Extract the master URL from worker status
    local connected_master=$(echo "$worker_status" | grep -o '"masterUrl" : "[^"]*"' | cut -d'"' -f4)
    echo "  Connected to master at: $connected_master"
    
    # Check if connected to expected master
    if echo "$connected_master" | grep -q "$master"; then
      echo "✓ Worker is connected to the expected master"
    else
      echo "⚠️ Worker is connected to a different master than expected"
      echo "  Expected: $master"
      echo "  Actual: $connected_master"
    fi
    
    return 0
  else
    echo "✗ Worker is not connected to any master"
    return 1
  fi
}

function restart_spark_worker() {
  local master=$1
  echo "Restarting Spark Worker..."
  # In Kubernetes, we would use kubectl to restart the pod
  # For local testing purposes:
  stop-worker.sh || true
  sleep 2
  start-worker.sh "$master"
  echo "Spark Worker restarted"
}

function diagnose_cluster_dns() {
  echo "=== Running DNS diagnosis across the cluster ==="
  
  # List of important hostnames to check
  local hostnames=(
    "spark-master"
    "spark-master.spark.svc.cluster.local" 
    "spark-master-0.spark-master-headless.spark.svc.cluster.local"
    "spark-master-headless.spark.svc.cluster.local"
  )
  
  # Perform DNS lookups and display results
  echo "DNS lookup results:"
  for host in "${hostnames[@]}"; do
    echo -n "  $host: "
    if ip=$(getent hosts "$host" 2>/dev/null | awk '{ print $1 }'); then
      echo "✓ Resolved to $ip"
    else
      echo "✗ Resolution failed"
    fi
  done
  
  # Check kube-dns/coredns service
  echo "Checking Kubernetes DNS service..."
  if kubectl get svc -n kube-system | grep -q "kube-dns\|coredns"; then
    echo "✓ Kubernetes DNS service exists"
    kubectl get svc -n kube-system | grep "kube-dns\|coredns"
  else
    echo "✗ Kubernetes DNS service not found or not accessible"
  fi
  
  echo "=== DNS diagnosis complete ==="
}

# Main execution
if [ "$1" == "master" ]; then
  check_dns_resolution "spark-master" || 
  check_dns_resolution "spark-master-0.spark-master-headless.spark.svc.cluster.local" ||
  echo "Warning: DNS resolution issue for all spark-master hostnames"
  check_spark_master || restart_spark_master
elif [ "$1" == "worker" ]; then
  master=${2:-"spark://spark-master-0.spark-master-headless.spark.svc.cluster.local:7077"}
  check_dns_resolution "spark-master-0.spark-master-headless.spark.svc.cluster.local" || 
  check_dns_resolution "spark-master" || 
  echo "Warning: DNS resolution issue for all spark-master hostnames"
  check_spark_worker "$master" || restart_spark_worker "$master"
elif [ "$1" == "dns" ]; then
  # New option to diagnose DNS issues across the cluster
  diagnose_cluster_dns
elif [ "$1" == "all" ]; then
  # Check everything
  echo "=== Running full health check ==="
  diagnose_cluster_dns
  check_dns_resolution "spark-master-0.spark-master-headless.spark.svc.cluster.local"
  check_spark_master
  check_spark_worker "spark://spark-master-0.spark-master-headless.spark.svc.cluster.local:7077"
  echo "=== Full health check complete ==="
else
  echo "Usage: $0 {master|worker|dns|all} [master-url]"
  echo "Options:"
  echo "  master       - Check and restart Spark Master if needed"
  echo "  worker       - Check and restart Spark Worker if needed"
  echo "  dns          - Run DNS diagnosis across the cluster"
  echo "  all          - Run all checks"
  echo "Example: $0 worker spark://spark-master-0.spark-master-headless.spark.svc.cluster.local:7077"
  exit 1
fi
