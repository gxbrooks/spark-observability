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
#       - Creates a group called "sshusers" for SSH access.
#       - Configures firewall rules for SSH access.
#       - Optionally reinstalls the OpenSSH server under --Reinstall flag control.
#       - Provides debug output under --Debug flag control.
#       - Checks the current configuration under --Check flag control.
#       - Backs up the original sshd_config file if it hasn't been backed up yet.
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

# Parse flags
CHECK=false
DEBUG=false
REINSTALL=false
SSHD_CONFIG_SRC=""
script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Check|-c) CHECK=true ;;
        --Debug|-d) DEBUG=true ;;
        --Reinstall|-r) REINSTALL=true ;;
        --Config|-cf)
            SSHD_CONFIG_SRC=$2
            shift 2
            continue
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name."
            echo "Usage   : $script_name [--Check|-c] [--Debug|-d] [--Reinstall|-r] [--Config|-cf <path>]"
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

# Check if OpenSSH server is installed
echo "Checking: Is OpenSSH server is installed?"
if ! dpkg -l | grep -q openssh-server; then
    if [ "$CHECK" = true ]; then
        echo "Result  : OpenSSH server is not installed."
    else
        echo "Checking: Installing OpenSSH server..."
        sudo apt update
        sudo apt install -y openssh-server
        echo "Result  : OpenSSH server installed."
    fi
else
    echo "Result  : OpenSSH server is already installed."
    if [ "$REINSTALL" = true ]; then
        echo "Checking: Reinstalling OpenSSH server..."
        sudo apt install --reinstall -y openssh-server
        echo "Result  : OpenSSH server reinstalled."
    fi
fi

# assert that the sshusers group exists
$script_dir/assert_group.sh \
    --Group "sshusers" \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG") 

# Backup and replace sshd_config
echo "Checking: Preparing to configure sshd_config."
if [[ -z "$SSHD_CONFIG_SRC" ]]; then
    SSHD_CONFIG_SRC="$script_dir/sshd_config.linux.cfg"
    $DEBUG && echo "Debug   : Using sshd template: $SSHD_CONFIG_SRC"
fi
SSHD_CONFIG_DEST="/etc/ssh/sshd_config"
SSHD_CONFIG_BACKUP="/etc/ssh/sshd_config.original"

if [ ! -f "$SSHD_CONFIG_BACKUP" ]; then
    if [ -f "$SSHD_CONFIG_DEST" ]; then
        if [ "$CHECK" != true ]; then
            echo "Starting: Backing up original sshd_config to $SSHD_CONFIG_BACKUP."
            sudo cp "$SSHD_CONFIG_DEST" "$SSHD_CONFIG_BACKUP"
        else
            echo "Result  : Original sshd_config exists, but not backed up."
        fi
    else
        echo "Result  : No existing sshd_config to back up."
    fi
else
    echo "Result  : Original sshd_config backup already exists."
fi

# Process sshd_config file
if [ -f "$SSHD_CONFIG_SRC" ]; then
    echo "Checking: Processing $SSHD_CONFIG_SRC."

    # cmp returns 0 if identical, 1 if different, 2 on error (e.g. missing dest).
    if cmp -s "$SSHD_CONFIG_SRC" "$SSHD_CONFIG_DEST" 2>/dev/null; then
        IS_CONFIG_SAME=true
        echo "Result  : '$SSHD_CONFIG_DEST' and '$SSHD_CONFIG_SRC' are the same."
    else
        IS_CONFIG_SAME=false
        echo "Result  : '$SSHD_CONFIG_DEST' and '$SSHD_CONFIG_SRC' are different."
    fi

    if [ "$IS_CONFIG_SAME" = false ]; then
        if [ "$CHECK" = true ]; then
            echo "Result  : '$SSHD_CONFIG_DEST' needs to be updated."
        else
            
            sudo cp "$SSHD_CONFIG_SRC" "$SSHD_CONFIG_DEST"
            echo "Result  : '$SSHD_CONFIG_DEST' updated."
        fi
    else
        echo "Result  : '$SSHD_CONFIG_DEST' is already up to date."
    fi
    # TODO: enable rm, but for now, keep it for debugging
    # rm "$SSHD_CONFIG_SRC"
else
    echo "Error: $SSHD_CONFIG_SRC not found."
    exit 1
fi

# Enable and start SSH service (systemd)
echo "Checking: Is the SSH service is running?"
if ! systemctl is-active --quiet ssh; then
    if [ "$CHECK" = true ]; then
        echo "Result  : SSH service is not running."
    else
        $DEBUG && echo "Starting: SSH service with systemctl."
        sudo systemctl enable ssh
        sudo systemctl start ssh
        echo "Result  : SSH service was enabled and started."
    fi
elif [ "$IS_CONFIG_SAME" = false ]; then
    if [ "$CHECK" = true ]; then
        echo "Result  : SSH service needs to be restarted."
    else
        $DEBUG && echo "Starting: '$SSHD_CONFIG_DEST' changed, restarting SSH service."
        sudo systemctl restart ssh
        echo "Result  : SSH service restarted."
    fi
else
    echo "Result  : SSH service is already running."
fi

# Configure firewall rules
echo "Checking: Configuring firewall rules."
if ! command -v ufw > /dev/null; then
    if [ "$CHECK" != true ]; then
        echo "Starting: Installing ufw..."
        sudo apt install -y ufw
        echo "Result  : ufw installed."
    else
        echo "Result  : ufw is not installed."
    fi
else
    echo "Result  : ufw is already installed."
    if [ "$REINSTALL" = true ] && [ "$CHECK" != true ]; then
        $DEBUG && echo "Starting: Reinstalling ufw..."
        sudo apt install --reinstall -y ufw
        echo "Result  : ufw reinstalled."
    fi
fi

if ! sudo ufw status | grep -q "Status: active"; then
    if [ "$CHECK" != true ]; then
        $DEBUG && echo "Starting: Enabling ufw..."
        sudo ufw enable
        echo "Result  : ufw enabled."
    else
        echo "Result  : ufw is not enabled."
    fi
else
    echo "Result  : ufw is already enabled."
fi
# Check again in case ufw was just enabled
echo "Checking: ssh rule"
if sudo ufw status | grep -q "Status: active"; then
    if ! sudo ufw status | grep -q "22/tcp"; then
        if [ "$CHECK" != true ]; then
            $DEBUG && echo "Starting: Allowing SSH through ufw..."
            sudo ufw allow ssh
            echo "Result  : SSH rule added to ufw."
        else
            echo "Result  : SSH rule is not configured in ufw."
        fi
    else
        echo "Result  : SSH rule is already configured in ufw."
    fi
else
    echo "Result  : ufw is not active and cannot check ssh rule."
fi
