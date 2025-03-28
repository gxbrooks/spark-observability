#!/bin/bash

# Enable SSH access for a user by configuring their .ssh directory, authorized_keys file, and SSH keys.

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

# Define paths
HOME_DIR=$(eval echo "~$USERNAME")
SSH_DIR="$HOME_DIR/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
PRIVATE_KEY="$SSH_DIR/id_rsa"
PUBLIC_KEY="$SSH_DIR/id_rsa.pub"

# Check and create .ssh directory
echo "Checking: if .ssh directory exists for user $USERNAME."
if [[ -d $SSH_DIR ]]; then
    echo "Result  : .ssh directory exists for user $USERNAME."
else
    if $CHECK; then
        echo "Result  : .ssh directory does not exist for user $USERNAME."
    else
        mkdir -p "$SSH_DIR"
        echo "Result  : .ssh directory created for user $USERNAME."
    fi
fi

# Check permissions for .ssh directory
echo "Checking: permissions for .ssh directory for user $USERNAME."
if [[ $(stat -c "%a" "$SSH_DIR") -ne 700 ]]; then
    if $CHECK; then
        echo "Result  : Permissions for .ssh directory are incorrect."
    else
        chmod 700 "$SSH_DIR"
        chown "$USERNAME:$USERNAME" "$SSH_DIR"
        echo "Result  : Permissions for .ssh directory fixed."
    fi
else
    echo "Result  : Permissions for .ssh directory are correct."
fi

# Check and create authorized_keys file
echo "Checking: if authorized_keys file exists for user $USERNAME."
if [[ -f $AUTHORIZED_KEYS ]]; then
    echo "Result  : authorized_keys file exists for user $USERNAME."
else
    if $CHECK; then
        echo "Result  : authorized_keys file does not exist for user $USERNAME."
    else
        touch "$AUTHORIZED_KEYS"
        echo "Result  : authorized_keys file created for user $USERNAME."
    fi
fi

# Check permissions for authorized_keys file
echo "Checking: permissions for authorized_keys file for user $USERNAME."
if [[ -f $AUTHORIZED_KEYS && $(stat -c "%a" "$AUTHORIZED_KEYS") -ne 600 ]]; then
    if $CHECK; then
        echo "Result  : Permissions for authorized_keys file are incorrect."
    else
        chmod 600 "$AUTHORIZED_KEYS"
        chown "$USERNAME:$USERNAME" "$AUTHORIZED_KEYS"
        echo "Result  : Permissions for authorized_keys file fixed."
    fi
else
    echo "Result  : Permissions for authorized_keys file are correct."
fi

# Check and generate SSH key pair
echo "Checking: if SSH key pair exists for user $USERNAME."
if [[ -f $PRIVATE_KEY && -f $PUBLIC_KEY ]]; then
    echo "Result  : SSH key pair exists for user $USERNAME."
else
    if $CHECK; then
        echo "Result  : SSH key pair does not exist for user $USERNAME."
    else
        ssh-keygen -t rsa -b 2048 -f "$PRIVATE_KEY" -q -N ""
        echo "Result  : SSH key pair generated for user $USERNAME."
    fi
fi

# Check permissions for private key
echo "Checking: permissions for private key for user $USERNAME."
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
echo "Checking: permissions for public key for user $USERNAME."
if [[ -f $PUBLIC_KEY && $(stat -c "%a" "$PUBLIC_KEY") -ne 600 ]]; then
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

# Check if sshuser group exists
echo "Checking: if sshuser group exists."
if ! getent group sshuser > /dev/null; then
    echo "Error: sshuser group does not exist. Please run install_ssh_service.sh to set up the SSH service."
    exit 1
fi

# Check and add user to sshuser group
echo "Checking: if user $USERNAME is in sshuser group."
if id -nG "$USERNAME" | grep -qw "sshuser"; then
    echo "Result  : User $USERNAME is already in sshuser group."
else
    if $CHECK; then
        echo "Result  : User $USERNAME is not in sshuser group."
    else
        sudo usermod -aG sshuser "$USERNAME"
        echo "Result  : User $USERNAME added to sshuser group."
    fi
fi