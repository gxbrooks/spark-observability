#!/bin/bash

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
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--User|-u <username>] [--Passphrase|-p <passphrase>]"
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

$DEBUG && echo "Starting: $script_name: root_dir = $root_dir"
$DEBUG && echo "Checking: Is the ssh server running?"
$root_dir/ssh/assert_ssh_server.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG") 

$root_dir/ssh/assert_service_account.sh \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG") \
    --Password "$PASSWORD" \
    --Username "$USERNAME"

# Ensure /etc/sudoers.d/ansible exists with correct permissions and content
SUDOERS_FILE="/etc/sudoers.d/ansible"
SUDOERS_LINE="ansible ALL=(ALL) NOPASSWD: ALL"

if sudo test ! -f "$SUDOERS_FILE"; then
    echo "Info    : Creating $SUDOERS_FILE for passwordless sudo for ansible user."
    echo "$SUDOERS_LINE" | sudo tee "$SUDOERS_FILE" > /dev/null
    sudo chmod 0440 "$SUDOERS_FILE"
else
    # Ensure the correct line is present (idempotent)
    if ! sudo grep -Fxq "$SUDOERS_LINE" "$SUDOERS_FILE"; then
        echo "Info    : Appending sudoers line for ansible user to $SUDOERS_FILE."
        echo "$SUDOERS_LINE" | sudo tee -a "$SUDOERS_FILE" > /dev/null
        sudo chmod 0440 "$SUDOERS_FILE"
    fi
fi

# Setup a Volumes partition that can be used across Windows and Linux
# This is needed for Docker container paths with Elastic Agent that
# can use the same pathnames (/mnt/c/Volumes) across Windows or Linux
# in one docker-compose.yml file.

# Adjust USERNAME if you need a specific owner
USERNAME="$USER"

sudo mkdir -p /mnt/c/Volumes
sudo chown "${USERNAME}:${USERNAME}" /mnt/c/Volumes
sudo chmod 775 /mnt/c/Volumes   # rwxrwxr-x

echo "/mnt/c/Volumes is ready with user-write permissions."