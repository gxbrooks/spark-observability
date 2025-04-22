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
SSHD_CONFIG_SRC="./ssh/sshd_config.linux.cfg"

for arg in "$@"; do
    case $arg in
        --Check|-c) CHECK=true ;;
        --Debug|-d) DEBUG=true ;;
        --Config|-cf) SSHD_CONFIG_SRC=$2; shift ;;
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


# Create the sshuser group
echo "Checking: Checking if 'sshuser' group exists."
if ! getent group sshuser > /dev/null; then
    if [ "$CHECK" = true ]; then
        echo "Result  : Group 'sshuser' does not exist."
    else
        echo "Checking: Creating group 'sshuser'..."
        sudo groupadd sshuser
        echo "Result  : Group 'sshuser' created."
    fi
else
    echo "Result  : Group 'sshuser' already exists."
fi

# Configure firewall rules
is_wsl() {
  # return success (0) if running on WSL
  # return failure (1) if running on native Linux
  if [[ -f /proc/version ]]; then
    if grep -q Microsoft /proc/version; then
      return 1 # Running on WSL
    else
      return 0 # Not running on WSL
    fi
  else
    return 0 # /proc/version not found (highly unlikely on a standard Linux system)
  fi
}

# Backup and replace sshd_config
echo "Checking: Preparing to configure sshd_config."
SSHD_CONFIG_SRC="./ssh/sshd_config.linux.cfg"
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

    cmp -s "$SSHD_CONFIG_SRC" "$SSHD_CONFIG_DEST"
    # cmp returns 0 if files are the same, 1 if different, and 2 if an error occurred
    if [ $? ]; then
        echo "Result  : '$SSHD_CONFIG_DEST' and '$SSHD_CONFIG_SRC' are different."
        IS_CONFIG_SAME=false
    else
        IS_CONFIG_SAME=true
        echo "Result  : '$SSHD_CONFIG_DEST' and '$SSHD_CONFIG_SRC' are the same."
    fi

    if [ "$IS_CONFIG_SAME" = false ]; then
        if [ "$CHECK" = true ]; then
            echo "Result  : '$SSHD_CONFIG_DEST' needs to be updated."
        else
            
            sudo cp "$SSHD_CONFIG_SRC" "$SSHD_CONFIG_DEST"
            echo "Result  : '$SSHD_CONFIG_DEST' updated."
        fi
    else
        echo "Result  : '$SSHD_CONFIG_DEST'' is already up to date."
    fi
    # TODO: enable rm, but for now, keep it for debugging
    # rm "$SSHD_CONFIG_SRC"
else
    echo "Error: $SSHD_CONFIG_SRC not found."
    exit 1
fi

# Enable and start SSH service
echo "Checking: Checking if SSH service is running."
if [ -n "$WSL_DISTRO_NAME" ]; then
    # Running on WSL: Use service commands
    if ! service ssh status > /dev/null 2>&1; then
        echo "Starting: SSH service via 'service' commands as SSH service is not running."
        # enable won't really do anything on WSL, but it's here for clarity
        # An administrative user must manually start the service after a reboot of WSL
        if [ "$CHECK" = true ]; then 
            echo "Result  : SSH service is not running (WSL)."
        else
            echo "Result  : Enabling SSH service..."
            # sudo service ssh enable
            sudo service ssh start
            echo "Result  : SSH service is enabled and running (WSL)."
        fi
    elif [ "$IS_CONFIG_SAME" = false ]; then
        if [ "$CHECK" = true ]; then 
            echo "Result  : SSH service needs to be restarted (WSL)."
        else
            echo "Result  : '$SSHD_CONFIG_DEST' changed, restarting SSH service..."
            sudo service ssh restart
            echo "Result  : SSH service restarted (WSL)."
        fi
    else  
        echo "Result  : SSH service is already running (WSL)."
    fi
else
    # Native Linux environment: Use systemctl commands
    if ! systemctl is-active --quiet ssh; then
        echo "Starting: SSH service via 'systemctl' commands as SSH service is not running."
        if [ "$CHECK" = true ]; then 
            echo "Result  : SSH service is not running (WSL)."
        else
            echo "Starting: Enabling SSH service (native Linux)..."
            sudo systemctl enable ssh
            sudo systemctl start ssh
            echo "Result  : SSH service was enabled and started (native Linux)."
        fi
    elif [ "$IS_CONFIG_SAME" = false ]; then
        if [ "$CHECK" = true ]; then 
            echo "Result  : SSH service needs to be restarted (WSL)."
        else
            echo "Starting: '$SSHD_CONFIG_DEST' changed, restarting SSH service (native Linux)..."
            sudo systemctl restart ssh 
            echo "Result  : SSH service restarted (native Linux)."
        fi
    else  
        echo "Result  : SSH service is already running (native Linux)."
    fi
fi

# Configure firewall rules
if ! is_wsl; then
    echo "Checking: Configuring firewall rules for non-WSL environment."
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
            echo "Starting: Reinstalling ufw..."
            sudo apt install --reinstall -y ufw
            echo "Result  : ufw reinstalled."
        fi
    fi
    
    if ! sudo ufw status | grep -q "Status: active"; then
        if [ "$CHECK" != true ]; then
            echo "Starting: Enabling ufw..."
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
                echo "Starting: Allowing SSH through ufw..."
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
else
    echo "Result  : Running on WSL: Use Windows Defender for firewall configuration."
fi
