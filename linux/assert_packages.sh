#!/bin/bash

# Assert Packages Installation
#
# Ensures specified packages are installed on the system.
# This script is idempotent and only installs missing packages.

# Parse arguments
DEBUG=false
CHECK=false
PACKAGES=()

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d)
            DEBUG=true
            ;;
        --Check|-c)
            CHECK=true
            ;;
        --Packages|-p)
            shift
            # Read space-separated package list
            PACKAGES=($1)
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] --Packages|-p \"package1 package2 ...\""
            exit 1
            ;;
    esac
    shift
done

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    echo "Error   : No packages specified. Use --Packages to provide a list."
    echo "Usage   : $script_name [--Debug|-d] [--Check|-c] --Packages|-p \"package1 package2 ...\""
    exit 1
fi

$DEBUG && echo "Debug   : Checking installation status for ${#PACKAGES[@]} package(s)..."

# Build list of packages that need installation
TO_INSTALL=()

for pkg in "${PACKAGES[@]}"; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        $DEBUG && echo "Debug   : Package '$pkg' is already installed."
    else
        $DEBUG && echo "Debug   : Package '$pkg' is NOT installed."
        TO_INSTALL+=("$pkg")
    fi
done

# Install missing packages
if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
    if $CHECK; then
        echo "Check   : ${#TO_INSTALL[@]} package(s) would be installed: ${TO_INSTALL[*]}"
    else
        echo "Info    : Installing ${#TO_INSTALL[@]} missing package(s): ${TO_INSTALL[*]}"
        sudo apt update -qq
        sudo apt install -y "${TO_INSTALL[@]}"
        
        if [[ $? -eq 0 ]]; then
            echo "Result  : Successfully installed ${#TO_INSTALL[@]} package(s)."
        else
            echo "Error   : Failed to install some packages."
            exit 1
        fi
    fi
else
    echo "Result  : All ${#PACKAGES[@]} package(s) already installed."
fi

