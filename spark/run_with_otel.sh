#!/bin/bash
# Helper script to run Spark applications with OpenTelemetry tracing enabled
#
# Usage: ./run_with_otel.sh <python_script>
# Example: ./run_with_otel.sh apps/Chapter_03.py

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if script argument provided
if [ -z "$1" ]; then
    echo "Usage: $0 <python_script>"
    echo "Example: $0 code/Ch03/word_count.py"
    exit 1
fi

PYTHON_SCRIPT="$1"

# Check if file exists
if [ ! -f "$SCRIPT_DIR/$PYTHON_SCRIPT" ] && [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "Error: Python script not found: $PYTHON_SCRIPT"
    exit 1
fi

# Resolve full path
if [ -f "$SCRIPT_DIR/$PYTHON_SCRIPT" ]; then
    PYTHON_SCRIPT="$SCRIPT_DIR/$PYTHON_SCRIPT"
fi

echo "=== Running Spark Application with OpenTelemetry Tracing ==="
echo "Script: $PYTHON_SCRIPT"
echo "OTel Endpoint: http://Lab2.local:31317"
echo ""

# Activate venv
cd "$PROJECT_ROOT"
source venv/bin/activate

# Load Spark environment
source spark/spark_env.sh

# Set OTel endpoint
export OTEL_EXPORTER_OTLP_ENDPOINT="http://Lab2.local:31317"

# Add OTel config to PYSPARK_SUBMIT_ARGS if not already there
export PYSPARK_SUBMIT_ARGS="--conf spark.extraListeners=com.elastic.spark.otel.OTelSparkListener --conf spark.jars=$PROJECT_ROOT/spark/otel-listener/target/spark-otel-listener-1.0.0.jar pyspark-shell"

# Run the script
echo "Starting Spark application..."
python "$PYTHON_SCRIPT"

echo ""
echo "=== Execution Complete ==="
echo "Check traces in Kibana: http://GaryPC.local:5601"
echo "  Data View: OpenTelemetry Traces"
echo "  Index: traces-generic-default"

