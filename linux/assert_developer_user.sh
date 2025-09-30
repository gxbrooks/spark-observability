#!/bin/bash

# Parse arguments
DEBUG=false
CHECK=false
USERNAME=""

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

# Default to current user if not specified
USERNAME="${USERNAME:-$USER}"

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
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--User|-u <username>]"
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Starting: $script_name: root_dir = $root_dir"
$DEBUG && echo "Configuring developer user: $USERNAME"

# Add user to docker group for Docker daemon access
$DEBUG && echo "Checking: Docker group membership for $USERNAME"
if $CHECK; then
    if groups "$USERNAME" | grep -q docker; then
        echo "Check    : $USERNAME is already in docker group"
    else
        echo "Check    : $USERNAME needs to be added to docker group"
    fi
else
    # Add user to docker group
    if ! groups "$USERNAME" | grep -q docker; then
        echo "Info    : Adding $USERNAME to docker group"
        sudo usermod -aG docker "$USERNAME"
        echo "Info    : Docker group changes require logout/login or 'newgrp docker' to take effect"
    else
        $DEBUG && echo "Debug    : $USERNAME is already in docker group"
    fi
fi

# Add user to spark group for Spark access
$DEBUG && echo "Checking: Spark group membership for $USERNAME"
if $CHECK; then
    if groups "$USERNAME" | grep -q spark; then
        echo "Check    : $USERNAME is already in spark group"
    else
        echo "Check    : $USERNAME needs to be added to spark group"
    fi
else
    # Add user to spark group
    if ! groups "$USERNAME" | grep -q spark; then
        echo "Info    : Adding $USERNAME to spark group"
        sudo usermod -aG spark "$USERNAME"
    else
        $DEBUG && echo "Debug    : $USERNAME is already in spark group"
    fi
fi

# Setup a Volumes partition that can be used across Windows and Linux
# This is needed for Docker container paths with Elastic Agent that
# can use the same pathnames (/mnt/c/Volumes) across Windows or Linux
# in one docker-compose.yml file.
$DEBUG && echo "Setting up cross-platform volumes directory"
if $CHECK; then
    if [ -d "/mnt/c/Volumes" ] && [ -w "/mnt/c/Volumes" ]; then
        echo "Check    : /mnt/c/Volumes exists and is writable by $USERNAME"
    else
        echo "Check    : /mnt/c/Volumes needs to be created or permissions fixed"
    fi
else
    sudo mkdir -p /mnt/c/Volumes
    sudo chown "${USERNAME}:${USERNAME}" /mnt/c/Volumes
    sudo chmod 775 /mnt/c/Volumes   # rwxrwxr-x
    echo "Info    : /mnt/c/Volumes is ready with user-write permissions for $USERNAME"
fi
