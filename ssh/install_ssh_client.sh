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

# Check if OpenSSH client is installed
$DEBUG && echo "Checking  : Is OpenSSH client is installed?"
if ! dpkg -l | grep -q openssh-client; then
    if [ "$CHECK" = true ]; then
        echo "Result    : OpenSSH client is not installed."
    else
        $DEBUG && echo "Installing: OpenSSH client..."
        sudo apt update
        sudo apt install -y openssh-client
        echo "Result    : OpenSSH client installed."
    fi
else
    $DEBUG && echo "Result  : OpenSSH client is already installed."
    if [ "$REINSTALL" = true ]; then
        $DEBUG && echo "Installing: OpenSSH client..."
        sudo apt install --reinstall -y openssh-client
        echo "Result    : OpenSSH client reinstalled."
    fi
fi
$DEBUG && echo "Result    :  OpenSSH Installation checked."
