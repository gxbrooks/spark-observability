#!/bin/bash

# Enable SSH client access for a user by configuring their .ssh directory and SSH keys.

# Define colors for the future
# Define color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Parse arguments
DEBUG=false
CHECK=false
USERNAME=$(whoami)

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
        --User|-u)
            USERNAME=$2
            shift
            ;;
        --Passphrase|-p|-N)
            PASSPHRASE=$2
            shift
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            exit 1
            ;;
    esac
    shift
done

if [[ -z "$PASSPHRASE" ]]; then
  echo "Error: --Passphrase or -p is mandatory in ${script_name}. Use the -N option to specify it." >&2
  echo "Usage: $0 [--Check|-c] [--Debug|-c] [--Passphrase <passphrase>]"  >&2
  exit 1
fi

# Define paths
HOME_DIR=$(eval echo "~$USERNAME")
SSH_DIR="$HOME_DIR/.ssh"
PRIVATE_KEY="$SSH_DIR/id_rsa"
PUBLIC_KEY="$SSH_DIR/id_rsa.pub"

# Check and create .ssh directory
$DEBUG && echo "Checking: if .ssh directory exists for user '$USERNAME'."
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

# FIXME: If keys don't exist their permissions will still be checked.
#        Use a full decision tree to differentiate use cases.
$DEBUG && echo "Checking: if SSH key pair exists for user '$USERNAME'."
if [[ -f $PRIVATE_KEY && -f $PUBLIC_KEY ]]; then
    echo "Result  : SSH key pair exists for user '$USERNAME'."
else
    if $CHECK; then
        echo "Result  : SSH key pair does not exist for user '$USERNAME'."
    else
        ssh-keygen -t rsa -b 2048 -f "$PRIVATE_KEY" -q -N "$PASSPHRASE"
        chmod 600 "$PRIVATE_KEY" "$PUBLIC_KEY"
        chown "$USERNAME:$USERNAME" "$PRIVATE_KEY" "$PUBLIC_KEY"
        echo "Result  : SSH key pair generated for user '$USERNAME'."
    fi
fi

# Check permissions for private key
$DEBUG && echo "Checking: permissions for private key for user '$USERNAME'."
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
$DEBUG && echo "Checking: permissions for public key for user '$USERNAME'."
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

$DEBUG && echo "Next    : Copy the public key in ~/.ssh/id_rsa.pub to the remote server's authorized_keys file."
$DEBUG && echo "Next    : Use ssh/ssh-copy-id-windows.sh <user>@<host> to copy to a Windows ssh server" 
$DEBUG && echo "Next    : Use /usr/bin/ssh-copy-id <user>@<host> to copy to a standalone Linux ssh server"
$DEBUG && echo "Next    : Use /usr/bin/ssh-copy-id -p 2222 <user>@<host> to copy to a WSL ssh server"  
