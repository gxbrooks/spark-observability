#!/bin/bash
#
# Launch IPython with PySpark
# 
# This script provides a simple wrapper to launch PySpark with IPython.
# It uses the standard PySpark command with environment variables.
#
# Usage: ./launch_ipython.sh

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Launching PySpark with IPython ===${NC}"

# Source environment variables
if [ -f "${SCRIPT_DIR}/ispark_env.sh" ]; then
    source "${SCRIPT_DIR}/ispark_env.sh"
    export SPARK_MASTER_URL="spark://${SPARK_MASTER_EXTERNAL_HOST}:${SPARK_MASTER_EXTERNAL_PORT}"
fi

# Activate virtual environment if it exists
if [ -d "${ROOT_DIR}/venv" ]; then
    source "${ROOT_DIR}/venv/bin/activate"
else
    echo -e "${RED}Error: Virtual environment not found at ${ROOT_DIR}/venv${NC}"
    echo "Create it with: python3.8 -m venv venv && source venv/bin/activate && pip install pyspark==3.5.1 ipython"
    exit 1
fi

# Configure PySpark to use IPython
export PYSPARK_DRIVER_PYTHON=ipython
export PYSPARK_DRIVER_PYTHON_OPTS=""

# Display connection info
echo -e "${YELLOW}Spark Master: ${SPARK_MASTER_URL:-spark://Lab2.lan:31686}${NC}"
echo -e "${YELLOW}Python: $(which python)${NC}"
echo -e "${YELLOW}Press Ctrl+D to exit${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

# Launch PySpark with IPython (uses standard pyspark command)
pyspark ${SPARK_MASTER_URL:+--master $SPARK_MASTER_URL}
