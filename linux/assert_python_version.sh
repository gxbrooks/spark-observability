#!/bin/bash

# Ensure the designated version of Python and pip are loaded and available
# This script follows the pattern of other initialization scripts with --Debug and --Check flags

# Parse arguments
DEBUG=false
CHECK=false
PYTHON_VERSION="3.12"

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d)
            DEBUG=true
            ;;
        --Check|-c)
            CHECK=true
            ;;
        --PythonVersion|-v)
            PYTHON_VERSION=$2
            shift
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--PythonVersion|-v <version>]"
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Starting: $script_name: root_dir = $root_dir"
$DEBUG && echo "Target Python version: $PYTHON_VERSION"

# Function to check if Python version is available
check_python_version() {
    local version=$1
    if command -v "python${version}" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to check if pip for specific Python version is available
check_pip_version() {
    local version=$1
    if command -v "pip${version}" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to install Python version
install_python_version() {
    local version=$1
    echo "Info    : Installing Python ${version}..."
    
    if ! $CHECK; then
        # Update package list
        sudo apt update
        
        # Install Python version and related packages
        sudo apt install -y "python${version}" "python${version}-dev" "python${version}-venv" "python${version}-pip"
        
        # Install pip if not available
        if ! check_pip_version "$version"; then
            sudo apt install -y "python${version}-pip"
        fi
        
        # Create symlinks if they don't exist
        if [[ "$version" != "3" ]]; then
            sudo ln -sf "/usr/bin/python${version}" "/usr/bin/python"
            sudo ln -sf "/usr/bin/pip${version}" "/usr/bin/pip"
        fi
    else
        echo "Check   : Would install Python ${version} and related packages"
    fi
}

# Function to verify Python installation
verify_python_installation() {
    local version=$1
    echo "Info    : Verifying Python ${version} installation..."
    
    if check_python_version "$version"; then
        local python_path=$(command -v "python${version}")
        local python_actual_version=$("python${version}" --version 2>&1)
        echo "Success : Python ${version} found at: $python_path"
        echo "Info    : Version: $python_actual_version"
        
        if check_pip_version "$version"; then
            local pip_path=$(command -v "pip${version}")
            local pip_actual_version=$("pip${version}" --version 2>&1)
            echo "Success : pip for Python ${version} found at: $pip_path"
            echo "Info    : Version: $pip_actual_version"
        else
            echo "Warning : pip for Python ${version} not found"
            return 1
        fi
    else
        echo "Error   : Python ${version} not found"
        return 1
    fi
}

# Main execution
if check_python_version "$PYTHON_VERSION"; then
    echo "Info    : Python ${PYTHON_VERSION} is already available"
    verify_python_installation "$PYTHON_VERSION"
else
    echo "Info    : Python ${PYTHON_VERSION} not found, installing..."
    install_python_version "$PYTHON_VERSION"
    
    if ! $CHECK; then
        verify_python_installation "$PYTHON_VERSION"
    fi
fi

# Set up environment variables for the current session
export PYTHON_VERSION="$PYTHON_VERSION"
export PYSPARK_PYTHON="python${PYTHON_VERSION}"
export PYSPARK_DRIVER_PYTHON="python${PYTHON_VERSION}"

$DEBUG && echo "Environment variables set:"
$DEBUG && echo "  PYTHON_VERSION=$PYTHON_VERSION"
$DEBUG && echo "  PYSPARK_PYTHON=$PYSPARK_PYTHON"
$DEBUG && echo "  PYSPARK_DRIVER_PYTHON=$PYSPARK_DRIVER_PYTHON"

echo "Result  : Python ${PYTHON_VERSION} environment configured successfully"
