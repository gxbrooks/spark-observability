#!/bin/bash

# Parse arguments
DEBUG=false
CHECK=false
USERNAME="ansible"
PASSWORD=""
SERVICE_UID=""    # Optional: specify UID for service account
SERVICE_GID=""    # Optional: specify GID for service account

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

# Load standard IDs
if [[ -f "$script_dir/standard_ids.sh" ]]; then
    source "$script_dir/standard_ids.sh"
    $DEBUG && echo "Debug   : Loaded standard IDs from standard_ids.sh"
fi

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
        --UID)
            SERVICE_UID=$2
            shift
            ;;
        --GID)
            SERVICE_GID=$2
            shift
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--User|-u <username>] [--Password|-p <password>] [--UID <uid>] [--GID <gid>]"
            exit 1
            ;;
    esac
    shift
done

# Set default UID/GID based on username if not specified
if [[ -z "$SERVICE_UID" ]] || [[ -z "$SERVICE_GID" ]]; then
    if [[ "$USERNAME" == "ansible" ]]; then
        SERVICE_UID="${ANSIBLE_UID:-1001}"
        SERVICE_GID="${ANSIBLE_GID:-1001}"
    else
        # For other service accounts, let system assign
        SERVICE_UID=""
        SERVICE_GID=""
    fi
fi

$DEBUG && [[ -n "$SERVICE_UID" ]] && echo "Debug   : Target UID for $USERNAME: $SERVICE_UID"
$DEBUG && [[ -n "$SERVICE_GID" ]] && echo "Debug   : Target GID for $USERNAME: $SERVICE_GID"

append_flag() {
    local flag=$1
    local condition=$2
    [[ $condition == true ]] && echo "$flag"
}

$DEBUG && echo "Starting: $script_name: root_dir = $root_dir"

# Call the SSH service account script with UID/GID parameters
SSH_ARGS="$(append_flag "--Check" "$CHECK") $(append_flag "--Debug" "$DEBUG") --Password $PASSWORD --Username $USERNAME"
[[ -n "$SERVICE_UID" ]] && SSH_ARGS="$SSH_ARGS --UID $SERVICE_UID"
[[ -n "$SERVICE_GID" ]] && SSH_ARGS="$SSH_ARGS --GID $SERVICE_GID"

$root_dir/ssh/assert_service_account.sh $SSH_ARGS

# Ensure /etc/sudoers.d/ansible exists with correct permissions and content
SUDOERS_FILE="/etc/sudoers.d/$USERNAME"
SUDOERS_LINE="$USERNAME ALL=(ALL) NOPASSWD: ALL"

if $CHECK; then
    if sudo test -f "$SUDOERS_FILE" && sudo grep -Fxq "$SUDOERS_LINE" "$SUDOERS_FILE"; then
        echo "Check    : $SUDOERS_FILE exists with correct content"
    else
        echo "Check    : $SUDOERS_FILE needs to be created or updated"
    fi
else
    if sudo test ! -f "$SUDOERS_FILE"; then
        echo "Info    : Creating $SUDOERS_FILE for passwordless sudo for $USERNAME user."
        echo "$SUDOERS_LINE" | sudo tee "$SUDOERS_FILE" > /dev/null
        sudo chmod 0440 "$SUDOERS_FILE"
    else
        # Ensure the correct line is present (idempotent)
        if ! sudo grep -Fxq "$SUDOERS_LINE" "$SUDOERS_FILE"; then
            echo "Info    : Appending sudoers line for $USERNAME user to $SUDOERS_FILE."
            echo "$SUDOERS_LINE" | sudo tee -a "$SUDOERS_FILE" > /dev/null
            sudo chmod 0440 "$SUDOERS_FILE"
        else
            $DEBUG && echo "Debug    : $SUDOERS_FILE already has correct content"
        fi
    fi
fi
