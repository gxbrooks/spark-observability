#!/bin/bash

# Ensure the designated version of Python and pip are loaded and available
# This script follows the pattern of other initialization scripts with --Debug and --Check flags

# Parse arguments
DEBUG=false
CHECK=false
FORCE=false
SETUP_VENV=true  # Default to setting up venv (best practice)
SKIP_VENV=false  # Flag to skip venv setup
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
        
        # Special handling for Python 3.8
        if [[ "$version" == "3.8" ]]; then
            echo "Info    : Installing Python 3.8 with specific packages..."
            
            # Add deadsnakes PPA for Python 3.8
            echo "Info    : Adding deadsnakes PPA for Python 3.8..."
            if ! sudo apt install -y software-properties-common; then
                echo "Error   : Failed to install software-properties-common"
                return 1
            fi
            
            if ! sudo add-apt-repository -y ppa:deadsnakes/ppa; then
                echo "Error   : Failed to add deadsnakes PPA"
                echo "Info    : Please run manually: sudo add-apt-repository ppa:deadsnakes/ppa"
                return 1
            fi
            
            # Update package list after adding PPA
            echo "Info    : Updating package list after adding PPA..."
            if ! sudo apt update; then
                echo "Error   : Failed to update package list after adding PPA"
                return 1
            fi
            
            # Install Python 3.8 packages (without pip - will install pip separately)
            if ! sudo apt install -y python3.8 python3.8-dev python3.8-venv python3.8-distutils; then
                echo "Error   : Failed to install Python 3.8 packages"
                echo "Info    : Please run manually: sudo apt install -y python3.8 python3.8-dev python3.8-venv python3.8-distutils"
                return 1
            fi
        else
            # Install Python version and related packages
            echo "Info    : Installing Python ${version} packages..."
            if ! sudo apt install -y "python${version}" "python${version}-dev" "python${version}-venv" "python${version}-pip"; then
                echo "Error   : Failed to install Python ${version} packages"
                echo "Info    : Please run manually: sudo apt install -y python${version} python${version}-dev python${version}-venv python${version}-pip"
                return 1
            fi
        fi
        
        # Install pip if not available or if force flag is set
        if ! check_pip_version "$version" || $FORCE; then
            if $FORCE && check_pip_version "$version"; then
                echo "Info    : Force flag set, reinstalling pip for Python ${version}..."
            else
                echo "Info    : Installing pip for Python ${version}..."
            fi
            
            if [[ "$version" == "3.8" ]]; then
                # For Python 3.8, install pip using get-pip.py
                echo "Info    : Installing pip for Python 3.8 using get-pip.py..."
                if ! sudo apt install -y curl; then
                    echo "Error   : Failed to install curl"
                    return 1
                fi
                if ! curl -sS https://bootstrap.pypa.io/pip/3.8/get-pip.py | sudo python3.8; then
                    echo "Error   : Failed to install pip for Python 3.8"
                    echo "Info    : Please run manually: curl -sS https://bootstrap.pypa.io/pip/3.8/get-pip.py | sudo python3.8"
                    return 1
                fi
            else
                if ! sudo apt install -y "python${version}-pip"; then
                    echo "Error   : Failed to install pip for Python ${version}"
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

# Function to install PySpark for Python 3.8
install_pyspark_for_python38() {
    echo "Info    : Installing PySpark for Python 3.8..."
    
    if ! $CHECK; then
        # Check if Python 3.8 is available
        if ! command -v python3.8 &> /dev/null; then
            echo "Error   : Python 3.8 is not installed. Please install it first."
            echo "Info    : Run: sudo apt install -y python3.8 python3.8-dev python3.8-venv python3.8-distutils python3.8-pip"
            return 1
        fi
        
        # Install PySpark and IPython for Python 3.8 in virtual environment
        if [ -d "venv" ]; then
            source venv/bin/activate
            pip install pyspark==3.5.1 ipython
        else
            echo "Warning: Virtual environment not found. Please run with --SetupVenv flag."
            return 1
        fi
        
        # Verify installation
        if python3.8 -c "import pyspark" 2>/dev/null; then
            echo "Success : PySpark installed for Python 3.8"
        else
            echo "Error   : Failed to install PySpark for Python 3.8"
            return 1
        fi
    else
        echo "Check   : Would install PySpark for Python 3.8"
    fi
}

# Function to setup Python 3.8 virtual environment
setup_python38_venv() {
    $DEBUG && echo "Debug   : Checking if Python 3.8 virtual environment exists..."
    
    # Get the root directory (parent of linux directory)
    local root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local venv_dir="${root_dir}/venv"
    
    if [ -d "$venv_dir" ]; then
        $DEBUG && echo "Debug   : Virtual environment already exists at $venv_dir"
        if $CHECK; then
            echo "Check   : Virtual environment already exists - no change needed"
        else
            echo "Info    : Virtual environment already exists - no change needed"
        fi
    else
        if $CHECK; then
            echo "Check   : Virtual environment does not exist - would create at $venv_dir"
        else
            echo "Info    : Creating Python 3.8 virtual environment at $venv_dir..."
            python3.8 -m venv "$venv_dir"
            
            # Activate virtual environment and install packages
            echo "Info    : Installing PySpark in virtual environment..."
            source "$venv_dir/bin/activate"
            
            # Upgrade pip
            python -m pip install --upgrade pip
            
            # Install PySpark and development tools
            pip install pyspark==3.5.1 ipython jupyter
            
            # Verify installation
            if python -c "import pyspark" 2>/dev/null; then
                echo "Success : PySpark installed in virtual environment"
            else
                echo "Error   : Failed to install PySpark in virtual environment"
                return 1
            fi
            
            # Setup PATH in project .bashrc if not already present
            setup_venv_path "$root_dir"
            
            echo "Info    : Virtual environment setup complete"
            echo "Info    : To activate: source $venv_dir/bin/activate"
        fi
    fi
}

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
        
        # Special handling for Python 3.8 - install PySpark and setup venv
        if [[ "$version" == "3.8" ]]; then
            if ! python3.8 -c "import pyspark" 2>/dev/null; then
                echo "Info    : Installing PySpark for Python 3.8..."
                install_pyspark_for_python38
            else
                echo "Success : PySpark already available for Python 3.8"
            fi
            
            # Setup virtual environment for Python 3.8
            setup_python38_venv
        fi
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

# Setup virtual environment (default behavior, idempotent)
if $SETUP_VENV && [[ "$PYTHON_VERSION" == "3.8" ]]; then
    $DEBUG && echo "Debug   : Setting up virtual environment (idempotent)..."
    setup_python38_venv
elif $SKIP_VENV; then
    echo "Info    : Skipping virtual environment setup (--SkipVenv flag)"
else
    echo "Info    : Virtual environment setup only supported for Python 3.8"
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
