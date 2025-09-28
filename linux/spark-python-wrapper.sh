#!/bin/bash
#
# Spark Python Wrapper Script
# 
# This script ensures PySpark uses Python 3.8 for compatibility with
# the official Apache Spark 3.5.1 image (which uses Python 3.8.10).
#
# Usage: ./spark-python-wrapper.sh python3.8 apps/Chapter_XX.py

# Set the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Set Python environment variables for Spark compatibility
export PYSPARK_PYTHON="python3.8"
export PYSPARK_DRIVER_PYTHON="python3.8"
export PYTHONPATH="${PYTHONPATH}:${ROOT_DIR}/spark"

# Check if Python 3.8 is available
if ! command -v python3.8 &> /dev/null; then
    echo "Error: Python 3.8 is not installed."
    echo "Please run: sudo apt install -y python3.8 python3.8-venv python3.8-dev"
    exit 1
fi

# Check if PySpark is installed for Python 3.8
if ! python3.8 -c "import pyspark" 2>/dev/null; then
    echo "Error: PySpark is not installed for Python 3.8."
    echo "Please run: python3.8 -m pip install --user pyspark==3.5.1 ipython"
    exit 1
fi

echo "Using Python 3.8 for Spark compatibility..."
echo "PYSPARK_PYTHON=$PYSPARK_PYTHON"
echo "PYSPARK_DRIVER_PYTHON=$PYSPARK_DRIVER_PYTHON"

# Execute the command with Python 3.8
exec "$@"
