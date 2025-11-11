#!/bin/bash

# Assert service account exists with proper configuration for Ansible control
# This script creates a service account and enables it for SSH server access

# Parse arguments
DEBUG=false
CHECK=false
USERNAME="ansible"
PASSWORD=""

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

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
        --Password|-p)
            PASSWORD=$2
            shift
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--User|-u <username>] [--Password|-p <password>]"
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Starting: $script_name: root_dir = $root_dir"

append_flag() {
    local flag=$1
    local condition=$2
    [[ $condition == true ]] && echo "$flag"
}

# Ensure sshusers group exists
$DEBUG && echo "Debug   : Ensuring sshusers group exists..."
$root_dir/ssh/assert_group.sh \
    --Group "sshusers" \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

# Check if the user exists
$DEBUG && echo "Checking: if user '$USERNAME' exists..."
if id "$USERNAME" &>/dev/null; then
    echo "Result  : User '$USERNAME' already exists."
    
    # Update password if provided
    if [[ -z "$PASSWORD" ]]; then
        echo "Result  : No password provided. Skipping password update."
    else
        if $CHECK; then
            echo "Check   : Password would be updated for user '$USERNAME'."
        else
            $DEBUG && echo "Debug   : Updating password for user '$USERNAME'..."
            echo "$USERNAME:$PASSWORD" | sudo chpasswd
            echo "Result  : Password for user '$USERNAME' updated."
        fi
    fi
else
    if $CHECK; then
        echo "Check   : User '$USERNAME' does not exist - would be created."
    else
        # Prompt for password if not provided
        if [[ -z "$PASSWORD" ]]; then
            read -sp "Enter password for new user '$USERNAME': " PASSWORD
            echo
        fi

        # Create the user (let system assign UID/GID)
        $DEBUG && echo "Debug   : Creating user '$USERNAME'..."
        sudo useradd -m -s /bin/bash -d /home/$USERNAME -c "${USERNAME^} Service Account" "$USERNAME"

        if [[ $? -ne 0 ]]; then
            echo "Error   : Failed to create user '$USERNAME'."
            exit 1
        fi
        echo "Result  : User '$USERNAME' service account created successfully."

        # Set the password
        $DEBUG && echo "Debug   : Setting password for user '$USERNAME'..."
        echo "$USERNAME:$PASSWORD" | sudo chpasswd
        echo "Result  : Password for user '$USERNAME' set successfully."
    fi
fi

# Ensure the home directory exists
if [[ ! -d "/home/$USERNAME" ]]; then
    if $CHECK; then
        echo "Check   : Home directory would be created for '$USERNAME'."
    else
        $DEBUG && echo "Debug   : Creating home directory for '$USERNAME'..."
        sudo mkdir -p "/home/$USERNAME"
        sudo chown "$USERNAME:$USERNAME" "/home/$USERNAME"
        echo "Result  : Home directory for '$USERNAME' created."
    fi
else
    $DEBUG && echo "Debug   : Home directory for '$USERNAME' already exists."
fi

# Add the user to required groups
SERVICE_GROUPS=("sudo" "docker" "users" "sshusers")
for group in "${SERVICE_GROUPS[@]}"; do
    # Check if group exists first
    if ! getent group "$group" >/dev/null 2>&1; then
        $DEBUG && echo "Debug   : Group '$group' does not exist, skipping..."
        continue
    fi
    
    if groups "$USERNAME" 2>/dev/null | grep -qw "$group"; then
        $DEBUG && echo "Debug   : User '$USERNAME' is already a member of group '$group'."
    else
        if $CHECK; then
            echo "Check   : User '$USERNAME' would be added to group '$group'."
        else
            $DEBUG && echo "Debug   : Adding user '$USERNAME' to group '$group'..."
            sudo usermod -aG "$group" "$USERNAME"
            echo "Result  : User '$USERNAME' added to group '$group'."
        fi
    fi
done

# Enable SSH server access for the user
$DEBUG && echo "Debug   : Enabling SSH server access for '$USERNAME'..."
SSH_ARGS="$(append_flag "--Check" "$CHECK") $(append_flag "--Debug" "$DEBUG") --User \"$USERNAME\""
eval "$root_dir/ssh/enable_user_for_ssh_server.sh $SSH_ARGS"

# Ensure /etc/sudoers.d file exists with correct permissions and content
SUDOERS_FILE="/etc/sudoers.d/$USERNAME"
SUDOERS_LINE="$USERNAME ALL=(ALL) NOPASSWD: ALL"

if $CHECK; then
    if sudo test -f "$SUDOERS_FILE" && sudo grep -Fxq "$SUDOERS_LINE" "$SUDOERS_FILE"; then
        echo "Check   : $SUDOERS_FILE exists with correct content"
    else
        echo "Check   : $SUDOERS_FILE needs to be created or updated"
    fi
else
    if sudo test ! -f "$SUDOERS_FILE"; then
        echo "Info    : Creating $SUDOERS_FILE for passwordless sudo"
        echo "$SUDOERS_LINE" | sudo tee "$SUDOERS_FILE" > /dev/null
        sudo chmod 0440 "$SUDOERS_FILE"
        echo "Result  : $SUDOERS_FILE created successfully."
    else
        # Ensure the correct line is present (idempotent)
        if ! sudo grep -Fxq "$SUDOERS_LINE" "$SUDOERS_FILE"; then
            echo "Info    : Updating sudoers line for $USERNAME"
            echo "$SUDOERS_LINE" | sudo tee -a "$SUDOERS_FILE" > /dev/null
            sudo chmod 0440 "$SUDOERS_FILE"
            echo "Result  : $SUDOERS_FILE updated successfully."
        else
            $DEBUG && echo "Debug   : $SUDOERS_FILE already has correct content"
        fi
    fi
fi

echo "Result  : Service account setup completed successfully for '$USERNAME'."
