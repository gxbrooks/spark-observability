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

resolve_master_host() {
  local candidates=()
  if [ -n "${SPARK_MASTER_HOST:-}" ]; then candidates+=("$SPARK_MASTER_HOST"); fi
  if [ -n "${SPARK_MASTER:-}" ]; then
    if [[ "$SPARK_MASTER" =~ ^spark://([^:]+):([0-9]+)$ ]]; then
      candidates+=("${BASH_REMATCH[1]}")
    fi
  fi
  candidates+=(
    "spark-master-0.spark-master-headless.spark.svc.cluster.local"
    "spark-master-headless.spark.svc.cluster.local"
    "spark-master"
  )

  local max_attempts=${RESOLUTION_ATTEMPTS:-10}
  local sleep_seconds=${RESOLUTION_SLEEP_SECONDS:-2}
  local attempt=1
  while [ $attempt -le $max_attempts ]; do
    for host in "${candidates[@]}"; do
      if check_dns "$host"; then
        echo "$host"
        return 0
      fi
    done
    sleep "$sleep_seconds"
    attempt=$((attempt+1))
  done
  return 1
}

case $COMPONENT in
  "master")
    # For master: Check self-resolution and port binding
    master_host=${SPARK_MASTER_HOST:-"spark-master-headless.spark.svc.cluster.local"}
    hostname_check=$(check_dns "$master_host" || \
                    check_dns "spark-master-0.spark-master-headless.spark.svc.cluster.local" || \
                    check_dns "spark-master" || \
                    check_dns "localhost")
    
    # For port binding, check both localhost and the configured hostname
    local_port_check=$(check_port "localhost" "7077" && check_port "localhost" "8080")
    exit $((hostname_check + local_port_check))
    ;;
  "worker")
    # For worker: Verify it can see the master without hardcoded IPs
    if grep -q "spark-master" /etc/hosts; then
      master_entry=$(grep "spark-master" /etc/hosts | head -n1)
      master_ip=$(echo "$master_entry" | awk '{print $1}')
      master_host="$master_ip"
      echo "Using master from /etc/hosts: $master_host"
    else
      master_host=$(resolve_master_host) || master_host=""
    fi

    if [ -z "$master_host" ]; then
      echo "Readiness: unable to resolve master host"
      exit 1
    fi
    
    if check_port "$master_host" "7077"; then
      echo "Readiness: connectivity to $master_host:7077 OK"
      exit 0
    else
      echo "Readiness: connectivity to $master_host:7077 FAILED"
      exit 1
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
