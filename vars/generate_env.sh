#!/bin/bash
#
# Bootstrap wrapper for generate_env.py
# Uses system Python3 to avoid circular dependencies
# Safe to run before any environment is set up
#
# This script ensures generate_env.py can run even when:
# - No virtual environment exists
# - Environment variables are not set
# - Python version is not yet determined
#
# Usage: Same as generate_env.py
#   ./generate_env.sh                    # Generate all contexts
#   ./generate_env.sh spark-client       # Generate specific context
#   ./generate_env.sh -f                 # Force regeneration
#   ./generate_env.sh -v spark-image     # Verbose output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use system python3 (not venv) to break circular dependency
PYTHON_CMD="python3"

# Check if python3 is available
if ! command -v "$PYTHON_CMD" >/dev/null 2>&1; then
    echo "Error: python3 not found. Please install Python 3." >&2
    exit 1
fi

# Check if PyYAML is available (required dependency)
if ! "$PYTHON_CMD" -c "import yaml" 2>/dev/null; then
    echo "Warning: PyYAML not found. Attempting to install..." >&2
    # Try to install with system pip or pip3
    if command -v pip3 >/dev/null 2>&1; then
        pip3 install --user pyyaml 2>/dev/null || {
            echo "Error: Failed to install PyYAML. Please run: pip3 install --user pyyaml" >&2
            exit 1
        }
    elif command -v pip >/dev/null 2>&1; then
        pip install --user pyyaml 2>/dev/null || {
            echo "Error: Failed to install PyYAML. Please run: pip install --user pyyaml" >&2
            exit 1
        }
    else
        echo "Error: pip not found. Please install PyYAML:" >&2
        echo "  sudo apt install python3-pip && pip3 install --user pyyaml" >&2
        exit 1
    fi
fi

# Run generate_env.py with system Python
cd "$REPO_ROOT"
exec "$PYTHON_CMD" "$SCRIPT_DIR/generate_env.py" "$@"

