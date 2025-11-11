#!/bin/bash

# Assert Managed Node Environment
#
# Ensures a node has all components needed to be managed by Ansible.
# This includes SSH server, service account, Python, and user configuration.
#
# This script is idempotent and can be run multiple times safely.

# Parse arguments
DEBUG=false
CHECK=false
USERNAME="ansible"
PASSWORD=""
PYTHON_VERSION=""  # Will be loaded from managed_node_env.sh if not specified
JAVA_VERSION=""    # Will be loaded from managed_node_env.sh if not specified

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
        --User|-u)
            USERNAME=$2
            shift
            ;;
        --Password|-p)
            PASSWORD=$2
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
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--User|-u <username>] [--Password|-p <password>] [-pyv <python_version>] [-jv <java_version>]"
            exit 1
            ;;
    esac
    shift
done

# Bootstrap: Generate environment configuration using system Python
# Note: We use python3 explicitly to handle the bootstrapping issue
if ! $CHECK; then
  echo "Info    : Generating managed-node environment configuration..."
  cd "$root_dir" && python3 linux/generate_env.py managed-node -f
fi

# Source the generated environment file (if it exists)
if [[ -f "$root_dir/linux/managed_node_env.sh" ]]; then
  source "$root_dir/linux/managed_node_env.sh"
  $DEBUG && echo "Debug   : Loaded managed-node environment from managed_node_env.sh"
fi

# Override with command-line args or defaults if provided
[[ -n "$PYTHON_VERSION" ]] || PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
[[ -n "$JAVA_VERSION" ]] || JAVA_VERSION="${JAVA_VERSION:-17}"

$DEBUG && echo "Debug   : PYTHON_VERSION = $PYTHON_VERSION"
$DEBUG && echo "Debug   : JAVA_VERSION = $JAVA_VERSION"

append_flag() {
    local flag=$1
    local condition=$2
    [[ $condition == true ]] && echo "$flag"
}

$DEBUG && echo "Starting: $script_name: root_dir = $root_dir"

# Define packages required for managed nodes
MANAGED_PACKAGES=(jq ncat keychain bind9-dnsutils traceroute)

# Install required packages
$root_dir/linux/assert_packages.sh \
    --Packages "${MANAGED_PACKAGES[*]}" \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

$DEBUG && echo "Checking: Is the ssh server running?"
$root_dir/ssh/assert_ssh_server.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG") 

# Configure service account (ansible user)
$root_dir/linux/assert_service_account.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG") \
    --Password "$PASSWORD" \
    --User "$USERNAME"

$DEBUG && echo "Checking: Python version management"
$root_dir/linux/assert_python_version.sh \
    --PythonVersion "$PYTHON_VERSION" \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

# Ensure spark user and group exist
$root_dir/linux/assert_spark_user.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

# Configure developer user (current user)
$root_dir/linux/assert_developer_user.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG") \
    --User "$USER"
