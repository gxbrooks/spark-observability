#!/bin/bash

# Usage: ./create_user.sh --Username <username> [--Password <password>] [--Debug | -d] [--Check | -c]

# Parse arguments
DEBUG=false
CHECK=false
USERNAME=""
PASSWORD=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --Debug|-d) DEBUG=true ;;
        --Check|-c) CHECK=true ;;
        --Username|-u) USERNAME="$2"; shift ;;
        --Password|-p) PASSWORD="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Validate username
if [[ -z "$USERNAME" ]]; then
    echo "Error: --Username or -u parameter is required."
    exit 1
fi

# Debug function
debug_log() {
    if $DEBUG; then
        echo "[DEBUG] $1"
    fi
}

# Check if the user exists
if id "$USERNAME" &>/dev/null; then
    echo "User '$USERNAME' already exists."
    if [[ -z "$PASSWORD" ]]; then
        echo "No password provided. Skipping password update."
    else
        if $CHECK; then
            echo "Check mode enabled. Password will not be updated."
        else
            debug_log "Updating password for user '$USERNAME'..."
            echo "$USERNAME:$PASSWORD" | sudo chpasswd
            echo "Password for user '$USERNAME' updated."
        fi
    fi
else
    if $CHECK; then
        echo "User '$USERNAME' does not exist. Check mode enabled. No changes will be made."
        exit 0
    fi

    # Prompt for password if not provided
    if [[ -z "$PASSWORD" ]]; then
        read -sp "Enter password for new user '$USERNAME': " PASSWORD
        echo
    fi

    # Create the user
    debug_log "Creating user '$USERNAME'..."
    sudo useradd -m -s /bin/bash "$USERNAME"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create user '$USERNAME'."
        exit 1
    fi
    echo "User '$USERNAME' created successfully."

    # Set the password
    debug_log "Setting password for user '$USERNAME'..."
    echo "$USERNAME:$PASSWORD" | sudo chpasswd
    echo "Password for user '$USERNAME' set successfully."
fi

# Ensure the home directory exists
if [[ ! -d "/home/$USERNAME" ]]; then
    if $CHECK; then
        echo "Home directory needs to be created."
    else
        debug_log "Creating home directory for '$USERNAME'..."
        sudo mkdir -p "/home/$USERNAME"
        sudo chown "$USERNAME:$USERNAME" "/home/$USERNAME"
        echo "Home directory for '$USERNAME' created."
    fi
else
    echo "Home directory for '$USERNAME' already exists."
fi

# Add the user to groups
SERVICE_GROUPS=("sudo" "docker" "users")
for group in "${SERVICE_GROUPS[@]}"; do
    if groups "$USERNAME" | grep -qw "$group"; then
        echo "User '$USERNAME' is already a member of the group '$group'."
    else
        if $CHECK; then
            echo "User '$USERNAME' needs to be added to the group '$group'."
        else
            debug_log "Adding user '$USERNAME' to the group '$group'..."
            sudo usermod -aG "$group" "$USERNAME"
            echo "User '$USERNAME' added to the group '$group'."
        fi
    fi
done

echo "Script completed successfully."