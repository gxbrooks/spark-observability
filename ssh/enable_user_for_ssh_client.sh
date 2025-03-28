#!/bin/bash

# Enable SSH client access for a user by configuring their .ssh directory and SSH keys.

# Parse arguments
DEBUG=false
CHECK=false
USERNAME=$(whoami)

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d)
            DEBUG=true
            shift
            ;;
        --Check|-c)
            CHECK=true
            shift
            ;;
        --User|-u)
            USERNAME=$2
            shift 2
            ;;
        -*)
            echo "Error: Unrecognized flag $1"
            exit 1
            ;;
        *)
            echo "Error: Unrecognized argument $1"
            exit 1
            ;;
    esac
done

# Define colors for the future
# Define color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Define paths
HOME_DIR=$(eval echo "~$USERNAME")
SSH_DIR="$HOME_DIR/.ssh"
PRIVATE_KEY="$SSH_DIR/id_rsa"
PUBLIC_KEY="$SSH_DIR/id_rsa.pub"

# Check and create .ssh directory
$CHECK && echo "Checking: if .ssh directory exists for user '$USERNAME'."
if [[ -d $SSH_DIR ]]; then
    echo "Result  : .ssh directory exists for user '$USERNAME'."
else
    if $CHECK; then
        echo "Result  : .ssh directory does not exist for user '$USERNAME'."
    else
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        chown "$USERNAME:$USERNAME" "$SSH_DIR"
        echo "Result  : .ssh directory created for user '$USERNAME'."
    fi
fi

# Check and generate SSH key pair
$CHECK && echo "Checking: if SSH key pair exists for user '$USERNAME'."
if [[ -f $PRIVATE_KEY && -f $PUBLIC_KEY ]]; then
    echo "Result  : SSH key pair exists for user '$USERNAME'."
else
    if $CHECK; then
        echo "Result  : SSH key pair does not exist for user '$USERNAME'."
    else
        ssh-keygen -t rsa -b 2048 -f "$PRIVATE_KEY" -q -N ""
        chmod 600 "$PRIVATE_KEY" "$PUBLIC_KEY"
        chown "$USERNAME:$USERNAME" "$PRIVATE_KEY" "$PUBLIC_KEY"
        echo "Result  : SSH key pair generated for user '$USERNAME'."
    fi
fi

# Check permissions for private key
$CHECK && echo "Checking: permissions for private key for user '$USERNAME'."
if [[ -f $PRIVATE_KEY && $(stat -c "%a" "$PRIVATE_KEY") -ne 600 ]]; then
    if $CHECK; then
        echo "Result  : Permissions for private key are incorrect."
    else
        chmod 600 "$PRIVATE_KEY"
        chown "$USERNAME:$USERNAME" "$PRIVATE_KEY"
        echo "Result  : Permissions for private key fixed."
    fi
else
    echo "Result  : Permissions for private key are correct."
fi

# Check permissions for public key
$CHECK && echo "Checking: permissions for public key for user '$USERNAME'."
if [[ -f $PUBLIC_KEY && $(stat -c "%a" "$PUBLIC_KEY") -ne 644 ]]; then
    if $CHECK; then
        echo "Result  : Permissions for public key are incorrect."
    else
        chmod 600 "$PUBLIC_KEY"
        chown "$USERNAME:$USERNAME" "$PUBLIC_KEY"
        echo "Result  : Permissions for public key fixed."
    fi
else
    echo "Result  : Permissions for public key are correct."
fi

$CHECK && echo "Next    : Copy the public key to the remote server's authorized_keys file."
$CHECK && echo "Next    : Use ssh-copy-id-windows.sh to copy to a Windows ssh server" 
$CHECK && echo "Next    : Use /usr/bin/ssh-copy-id to copy to a standalone linux ssh server"
$CHECK && echo "Next    : Use /usr/bin/ssh-copy-id -p 2222 to copy to a WSL ssh server"  
