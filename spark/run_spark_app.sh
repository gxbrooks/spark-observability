#!/bin/bash
#
# Spark Application Runner
# Usage: ./run_spark_app.sh path/to/your/script.py
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if script argument provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: No script provided${NC}"
    echo "Usage: $0 path/to/script.py"
    exit 1
fi

SPARK_SCRIPT="$1"

# Check if script exists
if [ ! -f "$SPARK_SCRIPT" ]; then
    echo -e "${RED}Error: Script not found: $SPARK_SCRIPT${NC}"
    exit 1
fi

# Load environment variables
if [ -f "${SCRIPT_DIR}/ispark/ispark_env.sh" ]; then
    source "${SCRIPT_DIR}/ispark/ispark_env.sh"
fi

# Set Spark master URL
SPARK_MASTER_HOST=${SPARK_MASTER_EXTERNAL_HOST:-"Lab2.lan"}
SPARK_MASTER_PORT=${SPARK_MASTER_EXTERNAL_PORT:-"32582"}
export SPARK_MASTER_URL="spark://${SPARK_MASTER_HOST}:${SPARK_MASTER_PORT}"

# Set Python environment
export PYSPARK_PYTHON=python3.8
export PYSPARK_DRIVER_PYTHON=python3.8

echo -e "${GREEN}=== Spark Application Runner ===${NC}"
echo -e "${YELLOW}Spark Master: ${SPARK_MASTER_URL}${NC}"
echo -e "${YELLOW}Script: ${SPARK_SCRIPT}${NC}"
echo -e "${YELLOW}Python: $(which python3)${NC}"
echo -e "${GREEN}================================${NC}"

# Activate venv if it exists
if [ -d "${PROJECT_ROOT}/venv" ]; then
    echo -e "${YELLOW}Activating virtual environment...${NC}"
    source "${PROJECT_ROOT}/venv/bin/activate"
fi

# Run the Spark application
python3 "$SPARK_SCRIPT"
