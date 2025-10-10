#!/bin/bash

# Setup and configure the base utilities needed to support a Linux devops environment. 
# This includes SSH and Git client configuration and packages for json formmating (jq), key
# management,  and network debugging..

# Parse flags
CHECK=false
DEBUG=false
PASSPHRASE=""
PYTHON_VERSION="3.8"
while [[ $# -gt 0 ]]; do
    echo "arg: $1"
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
        *) echo "Unknown parameter passed: $1"  >&2
          echo "Usage: $0 [--Check|-c] [--Debug|-d] [-N <passphrase>] [-pyv <python_version>]" >&2
          exit 1
          ;;
    esac
    shift
done

if [[ -z "$PASSPHRASE" ]]; then
  echo "Error: Passphrase is mandatory for securing keys. Use the -N (-p) option to specify it." >&2
  echo "Usage: $0 [--Check|-c] [--Debug|-d] [-N <passphrase>] [-pyv <python_version>]"  >&2
  exit 1
fi

# Set the 'dir' variable to the directory of this script
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$dir/.." && pwd)"

if $DEBUG; then
  echo "Debug: root_dir = $root_dir"
  echo "Debug: PASSPHRASE = $PASSPHRASE"
  echo "Debug: CHECK = $CHECK"
fi

# Validate passphrase

if ! $CHECK; then
  sudo apt update && sudo apt upgrade -y
  sudo apt update && sudo apt  -y install jq ncat keychain bind9-dnsutils traceroute ansible-core hdfs-cli
fi

if ! $CHECK; then
  git config --global user.email "gxbrooks@gmail.com"
  git config --global user.name "Gary Brooks"
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

# Ensure Python is available for Spark compatibility (venv setup is now default)
$root_dir/linux/assert_python_version.sh \
    --PythonVersion "$PYTHON_VERSION" \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

# Ensure spark user and group exist
$root_dir/linux/assert_spark_user.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

echo "Result  : Devops client initialized for user '$USER'."