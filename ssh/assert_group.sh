#!/usr/bin/bash

CHECK=false
DEBUG=false

# script_path="${BASH_SOURCE[0]}"
# script_name="$(basename "$script_path")"
# script_dir="$(cd "$(dirname "$script_path")" && pwd)"
# root_dir="$(cd "$script_dir/.." && pwd)"

for arg in "$@"; do
    case $arg in
        --Group|-g)
            GROUP_NAME=$2
            shift
            ;;
        --Check|-c) CHECK=true ;;
        --Debug|-d) DEBUG=true ;;
    esac
done

if [[ -z "$GROUP_NAME" ]]; then
    echo "Error   : --Group or -g parameter is required."
    exit 1
fi

# Check if the group exists
$DEBUG && echo "Checking: Does group '$GROUP_NAME' exist?"
if ! getent group "$GROUP_NAME" > /dev/null; then
    if $CHECK; then
        echo  "Result  : Group '$GROUP_NAME' does not exist."
    else
        sudo groupadd "$GROUP_NAME"
        echo  "Result  : Group '$GROUP_NAME' created successfully."
    fi
else
    echo  "Result  : Group '$GROUP_NAME' already exists."
fi