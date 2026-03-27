#!/bin/bash

# Assert Developer User Environment
#
# Context : Run on the developer's own workstation (client node), NOT on
#           managed nodes. Called by assert_client_node.sh.
#
# Purpose : Configures the human developer account on the client node:
#             - Docker group membership (for Docker daemon access)
#             - Spark group membership (for Spark process access)
#             - Elastic-Agent group membership
#
# This script is idempotent and can be run multiple times safely.

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

# Add user to elastic-agent group for Elastic Agent access
$DEBUG && echo "Checking: Elastic Agent group membership for $USERNAME"
if $CHECK; then
    if groups "$USERNAME" | grep -q elastic-agent; then
        echo "Check    : $USERNAME is already in elastic-agent group"
    else
        echo "Check    : $USERNAME needs to be added to elastic-agent group"
    fi
else
    # Add user to elastic-agent group
    if ! groups "$USERNAME" | grep -q elastic-agent; then
        echo "Info    : Adding $USERNAME to elastic-agent group"
        sudo usermod -aG elastic-agent "$USERNAME"
    else
        $DEBUG && echo "Debug    : $USERNAME is already in elastic-agent group"
    fi
fi

