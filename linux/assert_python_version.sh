#!/bin/bash

# Ensure the designated version of Python and pip are loaded and available
# This script follows the pattern of other initialization scripts with --Debug and --Check flags

# Parse arguments
DEBUG=false
CHECK=false
FORCE=false
SETUP_VENV=true  # Default to setting up venv (best practice)
SKIP_VENV=false  # Flag to skip venv setup
PYTHON_VERSION=""  # Must be provided via --PythonVersion or read from variables.yaml

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

# If PYTHON_VERSION not provided, try to read from variables.yaml
if [[ -z "$PYTHON_VERSION" ]]; then
    if [[ -f "$root_dir/vars/variables.yaml" ]]; then
        PYTHON_VERSION=$(
            python3 -c "
import yaml, sys
try:
    with open('$root_dir/vars/variables.yaml') as f:
        vars = yaml.safe_load(f)
        version = vars.get('PYTHON_VERSION', {}).get('value', '')
        if version:
            print(version)
        else:
            print('3.11', file=sys.stderr)
            sys.exit(1)
except Exception as e:
    print('3.11', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null || echo "3.11"
        )
    else
        # Fallback if variables.yaml doesn't exist
        PYTHON_VERSION="3.11"
    fi
fi

# Validate PYTHON_VERSION is set
if [[ -z "$PYTHON_VERSION" ]]; then
    echo "Error   : PYTHON_VERSION must be specified via --PythonVersion or variables.yaml" >&2
    echo "Usage   : $script_name [--PythonVersion|-v <version>] [other options...]" >&2
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d)
            DEBUG=true
            ;;
        --Check|-c)
            CHECK=true
            ;;
        --Force|-f)
            FORCE=true
            ;;
        --SetupVenv|-s)
            SETUP_VENV=true
            ;;
        --SkipVenv|-k)
            SKIP_VENV=true
            SETUP_VENV=false
            ;;
        --PythonVersion|-v)
            PYTHON_VERSION=$2
            shift
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--Force|-f] [--SetupVenv|-s] [--SkipVenv|-k] [--PythonVersion|-v <version>]"
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
        # Also test if pip actually works with the Python version
        if "pip${version}" --version >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Function to install Python version
install_python_version() {
    local version=$1
    echo "Info    : Installing Python ${version}..."
    
    if ! $CHECK; then
        # Attempt to run sudo commands (will prompt for password if needed)
        echo "Info    : Attempting to install Python ${version} with sudo..."
        
        # Update package list
        echo "Info    : Updating package list..."
        if ! sudo apt update; then
            echo "Error   : Failed to update package list"
            echo "Info    : Please run manually: sudo apt update"
            return 1
        fi
        
        # Try standard installation first
        echo "Info    : Installing Python ${version} and development packages..."
        
        # Standard package names for modern Python versions
        if ! sudo apt install -y python${version} python${version}-dev python${version}-venv python${version}-distutils 2>/dev/null; then
            echo "Info    : Standard packages not available, trying with PPA..."
            
            # Add deadsnakes PPA for older/newer Python versions
            echo "Info    : Adding deadsnakes PPA..."
            if ! sudo apt install -y software-properties-common; then
                echo "Error   : Failed to install software-properties-common"
                return 1
            fi
            
            if ! sudo add-apt-repository -y ppa:deadsnakes/ppa; then
                echo "Error   : Failed to add deadsnakes PPA"
                echo "Info    : Please run manually: sudo add-apt-repository ppa:deadsnakes/ppa"
                return 1
            fi
            
            # Update and retry
            if ! sudo apt update; then
                echo "Error   : Failed to update package list after adding PPA"
                return 1
            fi
            
            if ! sudo apt install -y python${version} python${version}-dev python${version}-venv python${version}-distutils; then
                echo "Error   : Failed to install Python ${version} packages"
                echo "Info    : Please run manually: sudo apt install -y python${version} python${version}-dev python${version}-venv python${version}-distutils"
                return 1
            fi
#       fi
        else
            # Install Python version and related packages (without pip package for 3.11+)
            echo "Info    : Installing Python ${version} packages..."
            if [[ "$version" == "3.11" ]] || [[ "$version" == "3.12" ]] || [[ "$version" == "3.13" ]]; then
                # Python 3.11+ doesn't have a pip package, we'll use ensurepip
                if ! sudo apt install -y "python${version}" "python${version}-dev" "python${version}-venv"; then
                    echo "Error   : Failed to install Python ${version} packages"
                    return 1
                fi
            else
                # Python 3.8-3.10 can use pip package
                if ! sudo apt install -y "python${version}" "python${version}-dev" "python${version}-venv" "python${version}-pip"; then
                    echo "Error   : Failed to install Python ${version} packages"
                    return 1
                fi
            fi
        fi
        
        # Install pip if not available or if force flag is set
        if ! check_pip_version "$version" || $FORCE; then
            if $FORCE && check_pip_version "$version"; then
                echo "Info    : Force flag set, reinstalling pip for Python ${version}..."
            else
                echo "Info    : Installing pip for Python ${version}..."
            fi
            
            # For Python 3.11+, use ensurepip (pip package doesn't exist in Ubuntu repos)
            # For Python 3.8-3.10, try the pip package first, fall back to ensurepip
            if [[ "$version" == "3.8" ]] || [[ "$version" == "3.9" ]] || [[ "$version" == "3.10" ]]; then
                # Try package first for older versions
                if sudo apt install -y "python${version}-pip" 2>/dev/null; then
                    echo "Info    : Installed pip for Python ${version} via package"
                else
                    # Fall back to ensurepip
                    echo "Info    : Package not available, using ensurepip for Python ${version}..."
                    if ! sudo "$(command -v python${version})" -m ensurepip --upgrade 2>/dev/null; then
                        echo "Error   : Failed to install pip for Python ${version}"
                        return 1
                    fi
                fi
            else
                # Python 3.11+ uses ensurepip (no pip package available)
                echo "Info    : Installing pip for Python ${version} using ensurepip..."
                if ! sudo "$(command -v python${version})" -m ensurepip --upgrade 2>/dev/null; then
                    echo "Error   : Failed to install pip for Python ${version} using ensurepip"
                    echo "Info    : Please ensure Python ${version} is properly installed"
                    return 1
                fi
            fi
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

# Note: Python 3.8-specific functions removed - Spark 4.0+ requires Python 3.11+
# Virtual environment setup is now handled in assert_client_node.sh

# Function to setup venv PATH in project .bashrc
setup_venv_path() {
    local root_dir="$1"
    local bashrc_file="${root_dir}/linux/.bashrc"
    local venv_path="${root_dir}/venv/bin"
    
    echo "Info    : Setting up venv PATH in project .bashrc..."
    
    # Check if venv/bin is already in PATH
    if grep -q "venv/bin" "$bashrc_file" 2>/dev/null; then
        echo "Info    : venv/bin already in PATH"
        return 0
    fi
    
    # Add venv/bin to PATH
    echo "" >> "$bashrc_file"
    echo "# Add project virtual environment to PATH" >> "$bashrc_file"
    echo "export PATH=\"${venv_path}:\$PATH\"" >> "$bashrc_file"
    echo "Info    : Added venv/bin to PATH in $bashrc_file"
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
        
        # Note: PySpark installation and venv setup are handled in assert_client_node.sh
        # This script only ensures the Python version is installed
    else
        echo "Error   : Python ${version} not found"
        return 1
    fi
}

# Main execution
if check_python_version "$PYTHON_VERSION" && ! $FORCE; then
    echo "Info    : Python ${PYTHON_VERSION} is already available"
    verify_python_installation "$PYTHON_VERSION"
else
    if $FORCE; then
        echo "Info    : Force flag set, reinstalling Python ${PYTHON_VERSION}..."
    else
        echo "Info    : Python ${PYTHON_VERSION} not found, installing..."
    fi
    install_python_version "$PYTHON_VERSION"
    
    if ! $CHECK; then
        verify_python_installation "$PYTHON_VERSION"
    fi
fi

# Note: Virtual environment setup is now handled in assert_client_node.sh
# This script only ensures the Python version is installed and available
if $SETUP_VENV || $SKIP_VENV; then
    echo "Info    : Virtual environment setup is handled by assert_client_node.sh"
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
