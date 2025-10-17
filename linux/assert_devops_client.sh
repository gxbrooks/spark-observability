#!/bin/bash

# Assert Devops Client Environment
# 
# Ensures all components needed for a Linux devops environment are properly configured.
# This includes SSH, Git, Python, Java, and development tools.
# 
# This script is idempotent and can be run multiple times safely.

# Parse flags
CHECK=false
DEBUG=false
PASSPHRASE=""
PYTHON_VERSION=""  # Will be loaded from devops_env.sh if not specified
JAVA_VERSION=""    # Will be loaded from devops_env.sh if not specified

while [[ $# -gt 0 ]]; do
    case $1 in
        --Check|-c) 
          CHECK=true 
          ;;
        --Debug|-d) 
          DEBUG=true 
          ;;
        -N|-p) 
          PASSPHRASE=$2
          shift
          ;;
        -pyv)
          PYTHON_VERSION=$2
          shift
          ;;
        -jv)
          JAVA_VERSION=$2
          shift
          ;;
        *) echo "Unknown parameter passed: $1"  >&2
          echo "Usage: $0 [--Check|-c] [--Debug|-d] [-N <passphrase>] [-pyv <python_version>] [-jv <java_version>]" >&2
          exit 1
          ;;
    esac
    shift
done

if [[ -z "$PASSPHRASE" ]]; then
  echo "Error: Passphrase is mandatory passphrase to access securing keys. Use the -N (-p) option to specify it." >&2
  echo "Usage: $0 [--Check|-c] [--Debug|-d] [-N <passphrase>] [-pyv <python_version>] [-jv <java_version>]"  >&2
  exit 1
fi

# Set the 'dir' variable to the directory of this script
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$dir/.." && pwd)"

# Bootstrap: Generate environment configuration using system Python
# Note: We use python3 explicitly to handle the bootstrapping issue
if ! $CHECK; then
  echo "Info    : Generating devops environment configuration..."
  cd "$root_dir" && python3 linux/generate_env.py devops -f
fi

# Source the generated environment file (if it exists)
if [[ -f "$root_dir/linux/devops_env.sh" ]]; then
  source "$root_dir/linux/devops_env.sh"
  $DEBUG && echo "Debug   : Loaded devops environment from devops_env.sh"
fi

# Override with command-line args if provided
[[ -n "$PYTHON_VERSION" ]] || PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
[[ -n "$JAVA_VERSION" ]] || JAVA_VERSION="${JAVA_VERSION:-17}"

if $DEBUG; then
  echo "Debug   : root_dir = $root_dir"
  echo "Debug   : PASSPHRASE = [REDACTED]"
  echo "Debug   : CHECK = $CHECK"
  echo "Debug   : PYTHON_VERSION = $PYTHON_VERSION"
  echo "Debug   : JAVA_VERSION = $JAVA_VERSION"
fi

# Install base packages
if ! $CHECK; then
  echo "Info    : Updating package lists and upgrading system..."
  sudo apt update && sudo apt upgrade -y
  echo "Info    : Installing devops utilities..."
  sudo apt  install -y jq ncat keychain bind9-dnsutils traceroute ansible-core
fi

# Install Java if specified version is not available
if ! $CHECK && [[ -n "$JAVA_VERSION" ]]; then
  if ! java -version 2>&1 | grep -q "openjdk version \"$JAVA_VERSION"; then
    echo "Info    : Installing OpenJDK $JAVA_VERSION..."
    sudo apt install -y openjdk-${JAVA_VERSION}-jdk-headless
  else
    echo "Info    : Java $JAVA_VERSION already installed"
  fi
fi

# Configure Git if not already configured
if ! $CHECK; then
  current_email=$(git config --global user.email 2>/dev/null || echo "")
  if [[ -z "$current_email" ]]; then
    echo "Info    : Configuring Git user..."
    git config --global user.email "gxbrooks@gmail.com"
    git config --global user.name "Gary Brooks"
  else
    echo "Info    : Git already configured (user: $current_email)"
  fi
fi
# Function to append flags conditionally
append_flag() {
    local flag=$1
    local condition=$2
    [[ $condition == true ]] && echo "$flag"
}

$root_dir/ssh/install_ssh_client.sh \
  $(append_flag "--Check" "$CHECK") \
  $(append_flag "--Debug" "$DEBUG")

$root_dir/ssh/enable_user_for_git_client.sh \
    --User "$USER" \
    --Passphrase "$PASSPHRASE" \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

$root_dir/ssh/enable_user_for_ssh_client.sh \
    --User "$USER" \
    --Passphrase "$PASSPHRASE" \
    $(append_flag "--Check" "$CHECK")\
    $(append_flag "--Debug" "$DEBUG")

# link into the users bash environment
$root_dir/linux/link_to_user_env.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

# Ensure Python is available for Spark compatibility
$root_dir/linux/assert_python_version.sh \
    --PythonVersion "$PYTHON_VERSION" \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

# Setup Python virtual environment for development
if ! $CHECK; then
  VENV_PATH="$root_dir/venv"
  PYTHON_CMD="python${PYTHON_VERSION}"
  
  # Check if venv exists and is the right Python version
  if [[ -f "$VENV_PATH/bin/python" ]]; then
    current_venv_version=$("$VENV_PATH/bin/python" --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
    if [[ "$current_venv_version" == "$PYTHON_VERSION" ]]; then
      echo "Info    : Python venv already exists with correct version ($PYTHON_VERSION)"
    else
      echo "Info    : Backing up old venv (Python $current_venv_version) and creating new one..."
      mv "$VENV_PATH" "${VENV_PATH}.python${current_venv_version}.backup"
      $PYTHON_CMD -m venv "$VENV_PATH"
    fi
  else
    echo "Info    : Creating Python $PYTHON_VERSION virtual environment..."
    $PYTHON_CMD -m venv "$VENV_PATH"
  fi
  
  # Install/upgrade requirements in venv
  if [[ -f "$root_dir/spark/requirements/requirements.txt" ]]; then
    echo "Info    : Installing Python requirements in venv..."
    "$VENV_PATH/bin/pip" install --quiet --upgrade pip
    "$VENV_PATH/bin/pip" install --quiet -r "$root_dir/spark/requirements/requirements.txt"
    # Install dependencies for generate_env.py
    "$VENV_PATH/bin/pip" install --quiet pyyaml toml
    echo "Info    : Python requirements installed successfully"
  fi
  
  echo "Info    : Python venv ready at $VENV_PATH"
  echo "Info    : Activate with: source venv/bin/activate"
else
  echo "Info    : Check mode - would verify/create venv"
fi

# Ensure spark user and group exist
$root_dir/linux/assert_spark_user.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

# Verify Spark client applications are properly configured
$root_dir/linux/assert_spark_client_apps.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

echo ""
echo "========================================"
echo "Result  : Devops client initialized for user '$USER'"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Activate Python venv:  source venv/bin/activate"
echo "  2. Source Spark env:      source spark/spark_env.sh"
echo "  3. Test Spark:            python spark/apps/Chapter_03.py"
echo ""