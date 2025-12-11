#!/bin/bash

# Assert Grafana Build Utilities
#
# Ensures all components needed for Grafana plugin development are installed.
# This includes Go and Node.js for building Grafana plugins.
#
# This script is idempotent and can be run multiple times safely.

# Parse arguments
DEBUG=false
CHECK=false

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
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c]"
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Debug   : Starting: $script_name"
$DEBUG && echo "Debug   : root_dir = $root_dir"
$DEBUG && echo "Debug   : CHECK = $CHECK"
$DEBUG && echo "Debug   : DEBUG = $DEBUG"

append_flag() {
    local flag=$1
    local condition=$2
    [[ $condition == true ]] && echo "$flag"
}

# Define packages required for Grafana plugin development
GRAFANA_BUILD_PACKAGES=(golang-go nodejs)

# Install required packages
$root_dir/linux/assert_packages.sh \
    --Packages "${GRAFANA_BUILD_PACKAGES[*]}" \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

# Verify installations
if ! $CHECK; then
    if command -v go >/dev/null 2>&1; then
        GO_VERSION=$(go version 2>&1 | awk '{print $3}')
        echo "Info    : Go is installed: $GO_VERSION"
        $DEBUG && echo "Debug   : Go binary: $(command -v go)"
    else
        echo "Warning : Go not found in PATH after installation"
    fi
    
    if command -v node >/dev/null 2>&1; then
        NODE_VERSION=$(node --version 2>&1)
        echo "Info    : Node.js is installed: $NODE_VERSION"
        $DEBUG && echo "Debug   : Node.js binary: $(command -v node)"
    else
        echo "Warning : Node.js not found in PATH after installation"
    fi
else
    echo "Check   : Would verify Go and Node.js installations"
fi

echo "Result  : Grafana build utilities configured successfully"

