#!/bin/bash

# Enable SSH server access for a user by configuring their .ssh directory, authorized_keys file, and group membership.

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

# Check and create .ssh directory
echo "Checking: if .ssh directory exists for user $USERNAME."
if [[ -d $SSH_DIR ]]; then
    echo "Result  : .ssh directory exists for user $USERNAME."
else
    if $CHECK; then
        echo "Result  : .ssh directory does not exist for user $USERNAME."
    else
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        chown "$USERNAME:$USERNAME" "$SSH_DIR"
        echo "Result  : .ssh directory created for user $USERNAME."
    fi
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
        chmod 600 "$AUTHORIZED_KEYS"
        chown "$USERNAME:$USERNAME" "$AUTHORIZED_KEYS"
        echo "Result  : authorized_keys file created for user $USERNAME."
    fi
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