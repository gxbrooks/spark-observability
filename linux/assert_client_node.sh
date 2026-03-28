#!/bin/bash

# Assert Client Node Environment
#
# Context : Run on the developer's own workstation (e.g. WSL on GaryPC, or Lab2).
#           This is the Ansible control node — the machine that drives all
#           automation against managed nodes.
#
# Purpose : Installs and configures the full devops client toolchain:
#             - Required packages (ansible-core, jq, maven, etc.)
#             - Java (OpenJDK)
#             - SSH client prerequisites for Ansible workflows
#             - Bash environment links
#             - Python venv with PySpark pinned to cluster version
#             - Spark client apps
#             - Spark events mount
#             - Grafana build utilities
#             - Developer user group memberships (docker, spark, elastic-agent)
#
# Out of scope (handled by assert_managed_node.sh):
#             - SSH server configuration
#             - Ansible service account creation
#
# This script is idempotent and can be run multiple times safely.

# Parse flags
CHECK=false
DEBUG=false
PASSPHRASE=""
SSH_KEY_NAME="id_ed25519_ansible"
PYTHON_VERSION=""  # Will be loaded from devops_env.sh if not specified
JAVA_VERSION=""    # Will be loaded from devops_env.sh if not specified
SPARK_VERSION=""   # Will be loaded from devops_env.sh if not specified

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
        --ssh-key-name|-k)
          SSH_KEY_NAME=$2
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
        -sv)
          SPARK_VERSION=$2
          shift
          ;;
        *) echo "Unknown parameter passed: $1"  >&2
          echo "Usage: $0 [--Check|-c] [--Debug|-d] [-N <passphrase>] [--ssh-key-name|-k <key_name>] [-pyv <python_version>] [-jv <java_version>] [-sv <spark_version>]" >&2
          exit 1
          ;;
    esac
    shift
done

# Set the 'dir' variable to the directory of this script
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$dir/.." && pwd)"

# Bootstrap: Generate environment configuration using system Python
# Use the wrapper script to ensure system Python is used (breaks circular dependency)
# Generate all client contexts (devops, spark-client, ispark) to keep them in sync
if ! $CHECK; then
  echo "Info    : Generating client environment configurations..."
  cd "$root_dir" && bash vars/generate_contexts.sh devops spark-client ispark -f
fi

# Extract PYTHON_VERSION from variables.yaml if not provided via command line
# This must use system Python to avoid circular dependency
if [[ -z "$PYTHON_VERSION" ]] && [[ -f "$root_dir/vars/variables.yaml" ]]; then
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
fi

# Source the generated environment file (if it exists)
DEVOPS_ENV_FILE="$root_dir/vars/contexts/devops/devops_env.sh"
if [[ -f "$DEVOPS_ENV_FILE" ]]; then
  source "$DEVOPS_ENV_FILE"
  $DEBUG && echo "Debug   : Loaded devops environment from $DEVOPS_ENV_FILE"
  # PYTHON_VERSION from env file will be used if not already set
fi

# Override with command-line args if provided (command line takes precedence)
# If still not set, use fallback
[[ -n "$PYTHON_VERSION" ]] || PYTHON_VERSION="3.11"
[[ -n "$JAVA_VERSION" ]] || JAVA_VERSION="${JAVA_VERSION:-17}"
[[ -n "$SPARK_VERSION" ]] || SPARK_VERSION="${SPARK_VERSION:-4.0.1}"

if $DEBUG; then
  echo "Debug   : root_dir = $root_dir"
  [[ -n "$PASSPHRASE" ]] && echo "Debug   : PASSPHRASE = [DEPRECATED ARG PROVIDED]"
  echo "Debug   : CHECK = $CHECK"
  echo "Debug   : SSH_KEY_NAME = $SSH_KEY_NAME"
  echo "Debug   : PYTHON_VERSION = $PYTHON_VERSION"
  echo "Debug   : JAVA_VERSION = $JAVA_VERSION"
  echo "Debug   : SPARK_VERSION = $SPARK_VERSION"
fi

# Function to append flags conditionally
append_flag() {
    local flag=$1
    local condition=$2
    [[ $condition == true ]] && echo "$flag"
}

# Define packages required for devops client
PACKAGES=(jq ncat keychain bind9-dnsutils traceroute ansible-core maven python3-toml make tree tmux yamllint hdfs-cli)

# Install packages using common package assertion script
$root_dir/linux/assert_packages.sh \
  --Packages "${PACKAGES[*]}" \
  $(append_flag "--Check" "$CHECK") \
  $(append_flag "--Debug" "$DEBUG")

# Install Java if specified version is not available
if ! $CHECK && [[ -n "$JAVA_VERSION" ]]; then
  if ! java -version 2>&1 | grep -q "openjdk version \"$JAVA_VERSION"; then
    echo "Info    : Installing OpenJDK $JAVA_VERSION..."
    sudo apt install -y openjdk-${JAVA_VERSION}-jdk-headless
  else
    echo "Info    : Java $JAVA_VERSION already installed"
  fi
fi

if [[ -z "$PASSPHRASE" ]] && ! $CHECK; then
  echo "Error: Passphrase is mandatory to generate/access SSH keys. Use the -N (-p) option to specify it." >&2
  echo "Usage: $0 [--Check|-c] [--Debug|-d] [-N <passphrase>] [--ssh-key-name|-k <key_name>] [-pyv <python_version>] [-jv <java_version>] [-sv <spark_version>]"  >&2
  exit 1
fi

$root_dir/ssh/install_ssh_client.sh \
  $(append_flag "--Check" "$CHECK") \
  $(append_flag "--Debug" "$DEBUG")

$root_dir/ssh/enable_user_for_ssh_client.sh \
    --User "$USER" \
    --Passphrase "$PASSPHRASE" \
    --KeyName "$SSH_KEY_NAME" \
    $(append_flag "--Check" "$CHECK") \
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
    # Install dependencies for generate_env.py and API scripts (esapi/kapi)
    "$VENV_PATH/bin/pip" install --quiet pyyaml toml requests
    # Install Flask and Kubernetes Python clients (moved from system packages)
    "$VENV_PATH/bin/pip" install --quiet flask kubernetes
    echo "Info    : Python requirements installed successfully"
  fi
  
  # Verify/upgrade PySpark to match cluster Spark version
  echo "Info    : Verifying PySpark version matches Spark cluster ($SPARK_VERSION)..."
  PYSPARK_INSTALLED=$("$VENV_PATH/bin/pip" show pyspark 2>/dev/null | grep Version | awk '{print $2}')
  
  if [[ -z "$PYSPARK_INSTALLED" ]]; then
    echo "Info    : Installing PySpark $SPARK_VERSION..."
    "$VENV_PATH/bin/pip" install --quiet pyspark==$SPARK_VERSION
    PYSPARK_INSTALLED=$SPARK_VERSION
  elif [[ "$PYSPARK_INSTALLED" != "$SPARK_VERSION" ]]; then
    echo "Info    : Upgrading PySpark from $PYSPARK_INSTALLED to $SPARK_VERSION..."
    "$VENV_PATH/bin/pip" install --quiet --upgrade pyspark==$SPARK_VERSION
    PYSPARK_INSTALLED=$SPARK_VERSION
  else
    echo "Info    : PySpark $PYSPARK_INSTALLED already matches cluster version"
  fi
  
  # Verify spark-submit version
  SPARK_SUBMIT_VERSION=$("$VENV_PATH/bin/spark-submit" --version 2>&1 | grep "version" | awk '{print $5}')
  if [[ "$SPARK_SUBMIT_VERSION" == "$SPARK_VERSION" ]]; then
    echo "Info    : spark-submit version verified: $SPARK_SUBMIT_VERSION"
  else
    echo "Warning : spark-submit version ($SPARK_SUBMIT_VERSION) may not match cluster ($SPARK_VERSION)"
  fi
  
  echo "Info    : Python venv ready at $VENV_PATH"
  echo "Info    : Activate with: source venv/bin/activate"
else
  echo "Info    : Check mode - would verify/create venv and PySpark version"
fi

# Ensure spark user and group exist
$root_dir/linux/assert_spark_user.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

# Ensure /mnt/spark/events is mounted for event logging
$root_dir/linux/assert_spark_events_mount.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

# Install Grafana build utilities for plugin development
$root_dir/linux/assert_grafana_build_utilities.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

# Verify Spark client applications are properly configured
$root_dir/linux/assert_spark_client_apps.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

# Configure developer user group memberships and workstation-specific paths
$root_dir/linux/assert_developer_user.sh \
    --User "$USER" \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

echo ""
echo "========================================"
echo "Result  : Client node initialized for user '$USER'"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Activate Python venv:  source venv/bin/activate"
echo "  2. Source Spark env:      source vars/contexts/spark_client_env.sh"
echo "  3. Test Spark:            python spark/apps/Chapter_03.py"
echo ""