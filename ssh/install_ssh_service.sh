#!/usr/bin/bash

# -----------------------------------------------------------------------------
# SYNOPSIS
#     A script to install and configure the OpenSSH server on Ubuntu.
#
# DESCRIPTION
#     This script ensures that the OpenSSH server is installed, configured, 
#     and running on an Ubuntu system. It performs the following tasks:
#       - Verifies the script is run as root or with sudo.
#       - Installs the OpenSSH server if not already installed.
#       - Configures the SSH service to start at boot.
#       - Creates a group called "sshuser" for SSH access.
#       - Configures firewall rules for SSH access.
#       - Optionally reinstalls the OpenSSH server under --Reinstall flag control.
#       - Provides debug output under --Debug flag control.
#       - Checks the current configuration under --Check flag control.
#       - Backs up the original sshd_config file if it hasn't been backed up yet.
#       - Replaces the sshd_config file with a modified version of 
#         sshd_config.linux.cfg, setting the port to 2222 for WSL or 22 otherwise.
#       - Only updates the sshd_config file if the modified version differs 
#         from the existing one.
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
#         If specified, the script will reinstall the OpenSSH server.
#
# EXAMPLES
#     ./install_ssh_service.sh --Check
#         Checks the current SSH server configuration without making any changes.
#
#     ./install_ssh_service.sh --Debug
#         Runs the script with detailed debug output.
#
#     ./install_ssh_service.sh --Reinstall
#         Reinstalls the OpenSSH server and reconfigures it.
#
#     ./install_ssh_service.sh
#         Installs and configures the OpenSSH server, including updating the 
#         sshd_config file.
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
        --Check|-c) CHECK=true ;;
        --Debug|-d) DEBUG=true ;;
        --Reinstall|-r) REINSTALL=true ;;
    esac
done

# Check if OpenSSH server is installed
echo "Checking: Is OpenSSH server is installed?"
if ! dpkg -l | grep -q openssh-server; then
    if [ "$CHECK" = true ]; then
        echo "Result  : OpenSSH server is not installed."
    else
        echo "Checking: Installing OpenSSH server..."
        apt update
        apt install -y openssh-server
        echo "Result  : OpenSSH server installed."
    fi
else
    echo "Result  : OpenSSH server is already installed."
    if [ "$REINSTALL" = true ]; then
        echo "Checking: Reinstalling OpenSSH server..."
        apt install --reinstall -y openssh-server
        echo "Result  : OpenSSH server reinstalled."
    fi
fi

# Enable and start SSH service
echo "Checking: Checking if SSH service is running."
if [ -n "$WSL_DISTRO_NAME" ]; then
    # Running on WSL
    if ! service ssh status > /dev/null 2>&1; then
        echo "Starting: SSH service via 'service' commands as SSH service is not running."
        # enable won't really do anything on WSL, but it's here for clarity
        # An administrative user must manually start the service after a reboot of WSL
        service ssh enable
        service ssh start
        echo "Result  : SSH service is enabled and running (WSL)."
    else
        echo "Result  : SSH service is already running (WSL)."
    fi
else
    # Non-WSL environment
    if ! systemctl is-active --quiet ssh; then
        echo "Starting: SSH service via 'systemctl' commands as SSH service is not running."
        systemctl enable ssh
        systemctl start ssh
        echo "Result  : SSH service is enabled and running."
    else
        echo "Result  : SSH service is already running."
    fi
fi

# Create the sshuser group
echo "Checking: Checking if 'sshuser' group exists."
if ! getent group sshuser > /dev/null; then
    if [ "$CHECK" = true ]; then
        echo "Result  : Group 'sshuser' does not exist."
    else
        echo "Checking: Creating group 'sshuser'..."
        groupadd sshuser
        echo "Result  : Group 'sshuser' created."
    fi
else
    echo "Result  : Group 'sshuser' already exists."
fi

# Configure firewall rules
if [ uname -r | grep -qi "microsoft"; ]; then
    echo "Checking: Configuring firewall rules for non-WSL environment."
    if ! command -v ufw > /dev/null; then
        if [ "$CHECK" != true ]; then
            echo "Starting: Installing ufw..."
            apt install -y ufw
            echo "Result  : ufw installed."
        else
            echo "Result  : ufw is not installed."
        fi
    else
        echo "Result  : ufw is already installed."
        if [ "$REINSTALL" = true ] && [ "$CHECK" != true ]; then
            echo "Starting: Reinstalling ufw..."
            apt install --reinstall -y ufw
            echo "Result  : ufw reinstalled."
        fi
    fi

    if [ "$CHECK" != true ]; then
        if ! ufw status | grep -q "Status: active"; then
            echo "Starting: Enabling ufw..."
            ufw enable
            echo "Result  : ufw enabled."
        else
            echo "Result  : ufw is already enabled."
        fi

        if ! ufw status | grep -q "22/tcp"; then
            echo "Starting: Allowing SSH through ufw..."
            ufw allow ssh
            echo "Result  : SSH rule added to ufw."
        else
            echo "Result  : SSH rule is already configured in ufw."
        fi
    else
        echo "Result  : Skipping firewall configuration due to --Check flag."
    fi
else
    echo "Result  : Running on WSL: Use Windows Defender for firewall configuration."
fi

# Backup and replace sshd_config
echo "Checking: Preparing to configure sshd_config."
SSHD_CONFIG_SRC="sshd_config.linux.cfg"
SSHD_CONFIG_DEST="/etc/ssh/sshd_config"
SSHD_CONFIG_BACKUP="/etc/ssh/sshd_config.original"

if [ ! -f "$SSHD_CONFIG_BACKUP" ]; then
    if [ -f "$SSHD_CONFIG_DEST" ]; then
        cp "$SSHD_CONFIG_DEST" "$SSHD_CONFIG_BACKUP"
        echo "Result  : Original sshd_config backed up to $SSHD_CONFIG_BACKUP."
    else
        echo "Result  : No existing sshd_config to back up."
    fi
else
    echo "Result  : Original sshd_config backup already exists."
fi

if [ -f "$SSHD_CONFIG_SRC" ]; then
    echo "Checking: Processing $SSHD_CONFIG_SRC."
    PORT="22"
    if [ -n "$WSL_DISTRO_NAME" ]; then
        PORT="2222"
        echo "Result  : Detected WSL environment. Setting PORT to $PORT."
    else
        echo "Result  : Non-WSL environment detected. Setting PORT to $PORT."
    fi

    TEMP_CONFIG=$(mktemp)
    sed "s/<PORT>/$PORT/g" "$SSHD_CONFIG_SRC" > "$TEMP_CONFIG"

    if ! cmp -s "$TEMP_CONFIG" "$SSHD_CONFIG_DEST"; then
        if [ "$CHECK" = true ]; then
            echo "Result  : sshd_config needs to be updated."
        else
            cp "$TEMP_CONFIG" "$SSHD_CONFIG_DEST"
            echo "Result  : sshd_config updated."
        fi
    else
        echo "Result  : sshd_config is already up to date."
    fi

    rm "$TEMP_CONFIG"
else
    echo "Error: $SSHD_CONFIG_SRC not found."
    exit 1
fi
