#!/bin/bash

# Parse arguments
DEBUG=false
CHECK=false
USERNAME="ansible"
PASSWORD=""
PYTHON_VERSION="3.8"

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
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--User|-u <username>] [--Password|-p <password>] [-pyv <python_version>]"
            exit 1
            ;;
    esac
    shift
done

append_flag() {
    local flag=$1
    local condition=$2
    [[ $condition == true ]] && echo "$flag"
}

$DEBUG && echo "Starting: $script_name: root_dir = $root_dir"
$DEBUG && echo "Checking: Is the ssh server running?"
$root_dir/ssh/assert_ssh_server.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG") 

# Configure service account (ansible user)
$root_dir/linux/assert_service_account.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG") \
    --Password "$PASSWORD" \
    --Username "$USERNAME"

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
