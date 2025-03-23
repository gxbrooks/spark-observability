#!/bin/bash

FIX=false
DEBUG=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --fix|-f) FIX=true ;;
        --debug|-d) DEBUG=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Define directories to check
WINRM_DIR="$HOME/.winrm"
SSH_DIR="$HOME/.ssh"

# Function to check and optionally create a directory
check_and_create_dir() {
    local dir_path=$1
    local dir_name=$2
    local expected_permissions="700"

    if [ -d "$dir_path" ]; then
        $DEBUG && echo "Check: $dir_name directory exists at $dir_path."

        # Check permissions of the existing directory
        actual_permissions=$(stat -c "%a" "$dir_path" 2>/dev/null)
        if [ "$actual_permissions" == "$expected_permissions" ]; then
            $DEBUG && echo "Check: $dir_name directory at $dir_path has correct permissions ($expected_permissions)."
            echo "$dir_name directory has correct permissions."
        else
            echo "Error: $dir_name directory at $dir_path has incorrect permissions ($actual_permissions)."
            if $FIX; then
                $DEBUG && echo "Fix: Setting correct permissions ($expected_permissions) for $dir_name directory at $dir_path."
                chmod 700 "$dir_path"
                echo "Set correct permissions ($expected_permissions) for $dir_name directory at $dir_path."
            fi
        fi
    else
        echo "Error: $dir_name directory does not exist at $dir_path."
        if $FIX; then
            $DEBUG && echo "Fix: Creating $dir_name directory at $dir_path with secure permissions."
            mkdir -p "$dir_path"
            chmod 700 "$dir_path"
            echo "Created $dir_name directory at $dir_path with secure permissions."
        fi
    fi
}

# Check and optionally create the .winrm directory
check_and_create_dir "$WINRM_DIR" ".winrm"

# Check and optionally create the .ssh directory
check_and_create_dir "$SSH_DIR" ".ssh"
