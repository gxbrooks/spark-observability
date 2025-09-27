#!/bin/bash
#
# iSpark IPython Launcher
# 
# This script sets up a local PySpark environment that connects to the
# Spark cluster running in Kubernetes. You run IPython locally and
# submit jobs to the remote Spark cluster.
#
# Usage: ./launch_ipython.sh

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for pretty output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== iSpark IPython Environment ===${NC}"

# Source environment variables from generated files
if [ -f "${SCRIPT_DIR}/ispark_env.sh" ]; then
    echo -e "${YELLOW}Loading environment variables from ${SCRIPT_DIR}/ispark_env.sh${NC}"
    source "${SCRIPT_DIR}/ispark_env.sh"
fi

# Get Spark master details - use external access
SPARK_MASTER_HOST=${SPARK_MASTER_EXTERNAL_HOST:-"Lab2.lan"}
SPARK_MASTER_PORT=${SPARK_MASTER_EXTERNAL_PORT:-"32582"}
SPARK_MASTER_URL="spark://${SPARK_MASTER_HOST}:${SPARK_MASTER_PORT}"

echo -e "${YELLOW}Spark Master URL: ${SPARK_MASTER_URL}${NC}"

# Check if PySpark is available
if ! python3 -c "import pyspark" 2>/dev/null; then
    echo -e "${GREEN}Installing PySpark...${NC}"
    echo -e "${YELLOW}Note: Using --break-system-packages flag for installation${NC}"
    pip3 install --break-system-packages pyspark==3.5.1 ipython
else
    echo -e "${YELLOW}PySpark already available${NC}"
fi

# Set up environment variables
export SPARK_MASTER_URL="${SPARK_MASTER_URL}"
export SPARK_DATA_DIR="/mnt/spark/data"
export PYSPARK_DRIVER_PYTHON="ipython3"
export PYSPARK_DRIVER_PYTHON_OPTS=""

# Set JAVA_HOME if not already set
if [ -z "$JAVA_HOME" ]; then
    # Try to find Java in common locations
    JAVA_PATHS=(
        "/usr/lib/jvm/java-11-openjdk-amd64"
        "/usr/lib/jvm/java-17-openjdk-amd64" 
        "/usr/lib/jvm/java-8-openjdk-amd64"
        "/usr/lib/jvm/java-11-openjdk"
        "/usr/lib/jvm/java-17-openjdk"
        "/usr/lib/jvm/java-8-openjdk"
        "/opt/java"
        "/usr/local/java"
    )
    
    for path in "${JAVA_PATHS[@]}"; do
        if [ -d "$path" ]; then
            export JAVA_HOME="$path"
            break
        fi
    done
    
    if [ -z "$JAVA_HOME" ]; then
        echo -e "${YELLOW}Warning: JAVA_HOME not set and no Java installation found${NC}"
        echo -e "${YELLOW}Please install Java: sudo apt install openjdk-11-jdk${NC}"
        echo -e "${YELLOW}Or set JAVA_HOME manually${NC}"
        exit 1
    fi
fi

echo -e "${YELLOW}JAVA_HOME: ${JAVA_HOME}${NC}"

echo -e "${GREEN}Launching iSpark IPython client...${NC}"
echo -e "${YELLOW}Note: You're running IPython locally, connecting to remote Spark cluster${NC}"
echo -e "${YELLOW}To exit, press Ctrl+D or type 'exit' in the IPython shell${NC}"
echo -e "${GREEN}=======================================${NC}"

# Launch the Python client
python3 "${SCRIPT_DIR}/spark_ipython_client.py" --master "${SPARK_MASTER_URL}"
