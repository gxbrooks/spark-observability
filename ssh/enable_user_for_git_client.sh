#!/bin/bash

# DEPRECATED: Git/GitHub identity and ~/.ssh/id_ed25519_github are handled by myenv assert_git.sh.
# This script generated id_ed25519 (default name) and hard-coded spark-observability remotes — use
#   ~/repos/myenv/assert_git.sh
# instead. Retained only for reference or one-off recovery on legacy setups.

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
PASSPHRASE=""

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
        --Passphrase|-p)
            PASSPHRASE=$2
            shift
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--User|-u <username>] [--Passphrase|-p <passphrase>]"
            echo "        : Where passphrase is used to unlock the private keys in .ssh/"
            exit 1
            ;;
    esac
    shift
done

if [[ -z "$PASSPHRASE" ]]; then
  echo "Error: --Passphrase or -p is mandatory in ${script_name}. Use the -N option to specify it." >&2
  echo "Usage: $0 [--Check|-c] [--Debug|-c] [--Passphrase <passphrase>]"  >&2
  echo "        : Where passphrase is used to unlock the private keys in .ssh/" >&2
  exit 1
fi

$DEBUG && echo "Checking  : $script_name started."

# Define paths
HOME_DIR=$(eval echo "~$USERNAME")
SSH_DIR="$HOME_DIR/.ssh"
PRIVATE_KEY="$SSH_DIR/id_ed25519"
PUBLIC_KEY="$SSH_DIR/id_ed25519.pub"

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
# FIXME: If keys don't exist their permissions will still be checked.
#        Use a full decision tree to differentiate use cases.
# Check and generate Git key pair
$DEBUG && echo "Checking: if Git key pair exists for user '$USERNAME'."
if [[ -f $PRIVATE_KEY && -f $PUBLIC_KEY ]]; then
    echo "Result  : Git key pair exists for user '$USERNAME'."
else
    if $CHECK; then
        echo "Result  : Git key pair does not exist for user '$USERNAME'."
    else
        ssh-keygen -q -t ed25519 \
            -f "$PRIVATE_KEY" \
            -N "$PASSPHRASE" \
            -C "$USERNAME@$(hostname)" \
            &>> $SSH_DIR/id_ed25519.log 
        chmod 600 "$PRIVATE_KEY" "$PUBLIC_KEY"
        chown "$USERNAME:$USERNAME" "$PRIVATE_KEY" "$PUBLIC_KEY"
        echo "Result  : Git key pair generated for user '$USERNAME'."
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

$DEBUG && echo "Next    : Copy the public  in ~/.ssh/id_ed25519.pub to GitHub SSH "
$DEBUG && echo "Next    : and GPG keys page at:"
$DEBUG && echo "Next    :     https://github.com/settings/keys"
$DEBUG && echo "Next    : Then add the following to your ~/.bashrc file" 
$DEBUG && echo "Next    :     eval \$(keychain --eval --quiet id_ed25519)"

# change to SSH URL for GitHub
$DEBUG && echo "Checking: Is Git URL is in SSH format."
if $CHECK; then
    echo "Result  : Don't forget to change the git url."
else
    git remote set-url origin git@github.com:gxbrooks/spark-observability
    echo "Result  : Set the git url to SSH format."
fi

$DEBUG && echo "Result  : $script_name completed."