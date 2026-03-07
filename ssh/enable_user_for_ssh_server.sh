#!/bin/bash

# Enable SSH server access for a user by configuring their .ssh directory, authorized_keys file, and group membership.
# Run on managed nodes (e.g. via assert_managed_node.sh → assert_service_account.sh) to set up the ansible
# operations user so the control node can SSH in. After this runs, the control node's public key must be
# added to this user's authorized_keys (e.g. ssh-copy-id -p <port> ansible@<host> from the control node).

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
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            exit 1
            ;;
    esac
    shift
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

# Check if sshusers group exists (created by assert_ssh_server.sh)
echo "Checking: if sshusers group exists."
if ! getent group sshusers > /dev/null; then
    echo "Error: sshusers group does not exist. Run assert_ssh_server.sh (or assert_managed_node.sh) first."
    exit 1
fi

# Check and add user to sshusers group
echo "Checking: if user $USERNAME is in sshusers group."
if id -nG "$USERNAME" | grep -qw "sshusers"; then
    echo "Result  : User $USERNAME is already in sshusers group."
else
    if $CHECK; then
        echo "Result  : User $USERNAME is not in sshusers group."
    else
        sudo usermod -aG sshusers "$USERNAME"
        echo "Result  : User $USERNAME added to sshusers group."
    fi
fi