#!/bin/bash
#
# Spark Python Wrapper Script (DEPRECATED)
# 
# This script is deprecated. Use linux/devops_env.sh instead:
#   source linux/devops_env.sh
#   python3 spark/apps/Chapter_XX.py
#
# This wrapper is kept for backwards compatibility only.
#
# Usage: ./spark-python-wrapper.sh python3 apps/Chapter_XX.py

# Set the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "⚠️  WARNING: This wrapper is deprecated!"
echo "   Use instead: source linux/devops_env.sh && python3 spark/apps/Chapter_XX.py"
echo ""

# Source devops environment for Python version
if [ -f "${SCRIPT_DIR}/devops_env.sh" ]; then
    source "${SCRIPT_DIR}/devops_env.sh"
else
    echo "Error: devops_env.sh not found. Run: python3 linux/generate_env.py"
    exit 1
fi

# Set Python environment variables from devops_env.sh
export PYTHONPATH="${PYTHONPATH}:${ROOT_DIR}/spark"

# Check if Python is available
if ! command -v python${PYTHON_VERSION} &> /dev/null; then
    echo "Error: Python ${PYTHON_VERSION} is not installed."
    echo "Please run: ./linux/assert_python_version.sh --PythonVersion ${PYTHON_VERSION}"
    exit 1
fi

# Check if PySpark is installed
if ! python${PYTHON_VERSION} -c "import pyspark" 2>/dev/null; then
    echo "Error: PySpark is not installed for Python ${PYTHON_VERSION}."
    echo "Please run: python${PYTHON_VERSION} -m pip install --user pyspark==${SPARK_VERSION:-4.0.1}"
    exit 1
fi

echo "Using Python ${PYTHON_VERSION} from devops_env.sh..."
echo "PYSPARK_PYTHON=$PYSPARK_PYTHON"

# Execute the command
exec "$@"
