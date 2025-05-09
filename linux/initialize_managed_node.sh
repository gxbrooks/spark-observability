#!/bin/bash

# Parse arguments
DEBUG=false
CHECK=false
USERNAME="ansible"
PASSWORD=""

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
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--User|-u <username>] [--Passphrase|-p <passphrase>]"
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

$root_dir/ssh/assert_service_account.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG") \
    --Password "$PASSWORD" \
    --Username "$USERNAME"

