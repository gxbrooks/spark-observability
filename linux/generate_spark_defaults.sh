#!/bin/bash
#
# Generate spark-defaults.conf from Jinja2 template and environment variables
# This ensures no hardcoded user-specific paths in the configuration
#
# Usage: ./generate_spark_defaults.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Try to use venv if available (has jinja2), otherwise use sed
if [ -f "${ROOT_DIR}/venv/bin/python3" ]; then
    PYTHON="${ROOT_DIR}/venv/bin/python3"
elif command -v python3 &> /dev/null; then
    PYTHON="python3"
else
    echo "Error: Python3 not found" >&2
    exit 1
fi

# Check if jinja2 is available
if ! $PYTHON -c "import jinja2" 2>/dev/null; then
    echo "Warning: Jinja2 not available, using sed for template substitution" >&2
    USE_SED=1
else
    USE_SED=0
fi

# Source devops environment for variable values
DEVOPS_ENV="${ROOT_DIR}/vars/contexts/devops/devops_env.sh"
if [ ! -f "${DEVOPS_ENV}" ]; then
    echo "Error: devops_env.sh not found at ${DEVOPS_ENV}" >&2
    echo "Run: bash vars/generate_env.sh devops" >&2
    exit 1
fi

source "${DEVOPS_ENV}"

# Validate required variables
if [[ -z "$PYSPARK_PYTHON" || -z "$OTEL_EXPORTER_OTLP_ENDPOINT" ]]; then
    echo "Error: Required variables not set in devops_env.sh" >&2
    echo "  PYSPARK_PYTHON: ${PYSPARK_PYTHON:-(not set)}" >&2
    echo "  OTEL_EXPORTER_OTLP_ENDPOINT: ${OTEL_EXPORTER_OTLP_ENDPOINT:-(not set)}" >&2
    exit 1
fi

# Validate ES variables are set (ES_HOST and ES_PORT, construct ES_URL)
if [[ -z "$ES_HOST" ]]; then
    echo "Error: ES_HOST not set in devops_env.sh" >&2
    exit 1
fi
if [[ -z "$ES_PORT" ]]; then
    echo "Error: ES_PORT not set in devops_env.sh" >&2
    exit 1
fi
# Construct ES_URL from ES_HOST and ES_PORT
ES_URL="https://${ES_HOST}:${ES_PORT}"
if [[ -z "$ES_USER" ]]; then
    echo "Error: ES_USER not set in devops_env.sh" >&2
    exit 1
fi
if [[ -z "$ES_PASSWORD" ]]; then
    echo "Error: ES_PASSWORD not set in devops_env.sh" >&2
    exit 1
fi

# Validate JAR path is set, then expand ~
if [[ -z "$SPARK_OTEL_LISTENER_JAR" ]]; then
    echo "Error: SPARK_OTEL_LISTENER_JAR not set in devops_env.sh" >&2
    exit 1
fi
SPARK_OTEL_LISTENER_JAR="${SPARK_OTEL_LISTENER_JAR/#\~/${HOME}}"

if [ ! -f "$SPARK_OTEL_LISTENER_JAR" ]; then
    echo "Warning: OTel listener JAR not found at: $SPARK_OTEL_LISTENER_JAR" >&2
    echo "  Run: ansible-playbook -i ansible/inventory.yml ansible/playbooks/spark/build.yml" >&2
fi

# Template and output paths
TEMPLATE="${ROOT_DIR}/spark/conf/spark-defaults.conf.j2"
OUTPUT="${ROOT_DIR}/spark/conf/spark-defaults.conf"

if [ ! -f "$TEMPLATE" ]; then
    echo "Error: Template not found: $TEMPLATE" >&2
    exit 1
fi

# Generate using appropriate method
if [ "$USE_SED" = "1" ]; then
    # Fallback: sed-based substitution
    # Escape special characters in variables for sed
    PYSPARK_PYTHON_ESC=$(echo "$PYSPARK_PYTHON" | sed 's/[[\.*^$()+?{|]/\\&/g')
    OTEL_ENDPOINT_ESC=$(echo "$OTEL_EXPORTER_OTLP_ENDPOINT" | sed 's/[[\.*^$()+?{|]/\\&/g')
    JAR_PATH_ESC=$(echo "$SPARK_OTEL_LISTENER_JAR" | sed 's/[[\.*^$()+?{|]/\\&/g')
    # ES_URL is constructed above from ES_HOST and ES_PORT
    ES_URL_ESC=$(echo "$ES_URL" | sed 's/[[\.*^$()+?{|]/\\&/g')
    ES_USER_ESC=$(echo "$ES_USER" | sed 's/[[\.*^$()+?{|]/\\&/g')
    ES_PASSWORD_ESC=$(echo "$ES_PASSWORD" | sed 's/[[\.*^$()+?{|]/\\&/g')
    sed -e "s|{{ PYSPARK_PYTHON }}|${PYSPARK_PYTHON_ESC}|g" \
        -e "s|{{ OTEL_EXPORTER_OTLP_ENDPOINT }}|${OTEL_ENDPOINT_ESC}|g" \
        -e "s|{{ SPARK_OTEL_LISTENER_JAR }}|${JAR_PATH_ESC}|g" \
        -e "s|{{ ES_URL }}|${ES_URL_ESC}|g" \
        -e "s|{{ ES_USER }}|${ES_USER_ESC}|g" \
        -e "s|{{ ES_PASSWORD }}|${ES_PASSWORD_ESC}|g" \
        "$TEMPLATE" > "$OUTPUT"
else
    # Preferred: Jinja2 rendering via Python
    $PYTHON -c "
import sys
from jinja2 import Template
from pathlib import Path

template_file = Path('$TEMPLATE')
output_file = Path('$OUTPUT')

with open(template_file, 'r') as f:
    template = Template(f.read())

rendered = template.render(
    PYSPARK_PYTHON='$PYSPARK_PYTHON',
    OTEL_EXPORTER_OTLP_ENDPOINT='$OTEL_EXPORTER_OTLP_ENDPOINT',
    SPARK_OTEL_LISTENER_JAR='$SPARK_OTEL_LISTENER_JAR',
    ES_URL='$ES_URL',
    ES_USER='$ES_USER',
    ES_PASSWORD='$ES_PASSWORD'
)

with open(output_file, 'w') as f:
    f.write(rendered)
"
fi

echo "✓ Generated spark-defaults.conf"
echo "  Template: $TEMPLATE"
echo "  Output: $OUTPUT"
echo "  PYSPARK_PYTHON: $PYSPARK_PYTHON"
echo "  OTEL_EXPORTER_OTLP_ENDPOINT: $OTEL_EXPORTER_OTLP_ENDPOINT"
echo "  SPARK_OTEL_LISTENER_JAR: $SPARK_OTEL_LISTENER_JAR"

