#!/bin/bash
#
# Spark Client Wrapper
# 
# This script ensures Spark client applications have proper configuration
# from devops_env.sh without hardcoding values in spark-defaults.conf
#
# Usage: ./spark-submit-client.sh python spark/apps/Chapter_04.py
#        ./spark-submit-client.sh spark-submit --class MyClass myapp.jar

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source devops environment
if [ -f "${SCRIPT_DIR}/devops_env.sh" ]; then
    source "${SCRIPT_DIR}/devops_env.sh"
else
    echo "Error: devops_env.sh not found. Run: python3 linux/generate_env.py"
    exit 1
fi

# Validate critical variables are set
if [[ -z "$PYSPARK_PYTHON" ]]; then
    echo "Error: PYSPARK_PYTHON not set in devops_env.sh"
    exit 1
fi

if [[ -z "$OTEL_EXPORTER_OTLP_ENDPOINT" ]]; then
    echo "Error: OTEL_EXPORTER_OTLP_ENDPOINT not set in devops_env.sh"
    exit 1
fi

# Set Spark configuration from environment variables
# PYSPARK_PYTHON is automatically passed to executors by PySpark
export PYSPARK_PYTHON="${PYSPARK_PYTHON}"

# OTEL endpoint needs to be explicitly passed to executors via Java options
# since it's used by the OTel listener (a Spark listener, not Python code)
export SPARK_EXECUTOR_OPTS="-DOTEL_EXPORTER_OTLP_ENDPOINT=${OTEL_EXPORTER_OTLP_ENDPOINT}"

# Driver also needs it (listener runs in both driver and executors)
export OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT}"

# Display configuration
echo "=== Spark Client Configuration ==="
echo "PYSPARK_PYTHON: ${PYSPARK_PYTHON}"
echo "OTEL_EXPORTER_OTLP_ENDPOINT: ${OTEL_EXPORTER_OTLP_ENDPOINT}"
echo "SPARK_VERSION: ${SPARK_VERSION}"
echo "==================================="
echo ""

# Execute the command
exec "$@"

