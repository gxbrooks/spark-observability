#!/usr/bin/bash

# -----------------------------------------------------------------------------
# SYNOPSIS
#     A script to install and configure the OpenSSH client on Ubuntu.
#
# DESCRIPTION
#     This script ensures that the OpenSSH client is installed and optionally 
#     reinstalls it. It performs the following tasks:
#       - Verifies the script is run as root or with sudo.
#       - Installs the OpenSSH client if not already installed.
#       - Optionally reinstalls the OpenSSH client under --Reinstall flag control.
#       - Provides debug output under --Debug flag control.
#       - Checks the current configuration under --Check flag control.
#
# PARAMETERS
#     --Check
#         If specified, the script will only check the current configuration 
#         without making any changes.
#
#     --Debug
#         If specified, the script will output detailed debug information 
#         for each step.
#
#     --Reinstall
#         If specified, the script will reinstall the OpenSSH client.
#
# EXAMPLES
#     ./install_ssh_client.sh --Check
#         Checks if the OpenSSH client is installed without making any changes.
#
#     ./install_ssh_client.sh --Debug
#         Runs the script with detailed debug output.
#
#     ./install_ssh_client.sh --Reinstall
#         Reinstalls the OpenSSH client.
#
#     ./install_ssh_client.sh
#         Installs the OpenSSH client if not already installed.
# -----------------------------------------------------------------------------

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root or with sudo."
    exit 1
fi

# Parse flags
CHECK=false
DEBUG=false
REINSTALL=false

for arg in "$@"; do
    case $arg in
        --Check) CHECK=true ;;
        --Debug) DEBUG=true ;;
        --Reinstall) REINSTALL=true ;;
    esac
done

# Debug output
debug() {
    if [ "$DEBUG" = true ]; then
        echo "DEBUG: $1"
    fi
}

# Check if OpenSSH client is installed
debug "Checking if OpenSSH client is installed."
if ! dpkg -l | grep -q openssh-client; then
    if [ "$CHECK" = true ]; then
        echo "OpenSSH client is not installed."
    else
        echo "Installing OpenSSH client..."
        apt update
        apt install -y openssh-client
        echo "OpenSSH client installed."
    fi
else
    echo "OpenSSH client is already installed."
    if [ "$REINSTALL" = true ]; then
        echo "Reinstalling OpenSSH client..."
        apt install --reinstall -y openssh-client
        echo "OpenSSH client reinstalled."
    fi
fi