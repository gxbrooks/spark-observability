#!/bin/bash

# Usage: ./create_user.sh --Username <username> [--Password <password>] [--Debug | -d] [--Check | -c]

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"

# Parse arguments
DEBUG=false
CHECK=false
USERNAME=""
PASSWORD=""
USER_UID=""
USER_GID=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --Debug|-d) DEBUG=true ;;
        --Check|-c) CHECK=true ;;
        --Username|-u) USERNAME="$2"; shift ;;
        --Password|-p) PASSWORD="$2"; shift ;;
        --UID) USER_UID="$2"; shift ;;
        --GID) USER_GID="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

$debug && echo "Starting: $script_name in $script_dir"

# Validate username
if [[ -z "$USERNAME" ]]; then
    echo "Error  : --Username or -u parameter is required."
    exit 1
fi

append_flag() {
    local flag=$1
    local condition=$2
    [[ $condition == true ]] && echo "$flag"
}

# assert that the sshuser group exists
$script_dir/assert_group.sh \
    --Group "sshusers" \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG") 

# Create group with specific GID if provided
if [[ -n "$USER_GID" ]]; then
    if getent group "$USERNAME" >/dev/null 2>&1; then
        CURRENT_GROUP_GID=$(getent group "$USERNAME" | cut -d: -f3)
        if [[ "$CURRENT_GROUP_GID" != "$USER_GID" ]]; then
            if $CHECK; then
                echo "Check   : Group '$USERNAME' has GID $CURRENT_GROUP_GID - would change to $USER_GID"
            else
                echo "Info    : Changing GID for group '$USERNAME' from $CURRENT_GROUP_GID to $USER_GID..."
                sudo groupmod -g "$USER_GID" "$USERNAME"
            fi
        fi
    else
        $script_dir/assert_group.sh \
            --Group "$USERNAME" \
            --GID "$USER_GID" \
            $(append_flag "--Check" "$CHECK") \
            $(append_flag "--Debug" "$DEBUG")
    fi
else
    $script_dir/assert_group.sh \
        --Group "$USERNAME" \
        $(append_flag "--Check" "$CHECK") \
        $(append_flag "--Debug" "$DEBUG")
fi 

# Check if the user exists
$DEBUG && echo "Checking  : if user '$USERNAME' exists..."
if id "$USERNAME" &>/dev/null; then
    echo  "Result  : User '$USERNAME' already exists."
    
    # Verify and fix UID/GID if specified
    if [[ -n "$USER_UID" ]] || [[ -n "$USER_GID" ]]; then
        CURRENT_UID=$(id -u "$USERNAME")
        CURRENT_GID=$(id -g "$USERNAME")
        
        if [[ -n "$USER_UID" ]] && [[ "$CURRENT_UID" != "$USER_UID" ]]; then
            if $CHECK; then
                echo  "Check   : User '$USERNAME' has UID $CURRENT_UID - would change to $USER_UID"
            else
                echo  "Info    : Changing UID for '$USERNAME' from $CURRENT_UID to $USER_UID..."
                sudo usermod -u "$USER_UID" "$USERNAME"
                echo  "Success : UID updated to $USER_UID"
            fi
        fi
        
        if [[ -n "$USER_GID" ]] && [[ "$CURRENT_GID" != "$USER_GID" ]]; then
            if $CHECK; then
                echo  "Check   : User '$USERNAME' has GID $CURRENT_GID - would change to $USER_GID"
            else
                # First check if the group needs GID change
                if getent group "$USERNAME" >/dev/null 2>&1; then
                    GROUP_GID=$(getent group "$USERNAME" | cut -d: -f3)
                    if [[ "$GROUP_GID" != "$USER_GID" ]]; then
                        echo  "Info    : Changing GID for group '$USERNAME' from $GROUP_GID to $USER_GID..."
                        sudo groupmod -g "$USER_GID" "$USERNAME"
                    fi
                fi
                echo  "Success : GID updated to $USER_GID"
            fi
        fi
    fi
    
    if [[ -z "$PASSWORD" ]]; then
        echo  "Result  : No password provided. Skipping password update."
    else
        if $CHECK; then
            echo  "Result  : Check mode enabled. Password will not be updated."
        else
            $DEBUG && echo "Updating password for user '$USERNAME'..."
            echo "$USERNAME:$PASSWORD" | sudo chpasswd
            echo  "Result  : Password for user '$USERNAME' updated."
        fi
    fi
else
    if $CHECK; then
        echo  "Result  : User '$USERNAME' does not exist."
        exit 0
    fi

    # Prompt for password if not provided
    if [[ -z "$PASSWORD" ]]; then
        read -sp "Enter password for new user '$USERNAME': " PASSWORD
        echo
    fi

    # Create the user with optional UID/GID
    $DEBUG && echo "Creating user '$USERNAME'..."
    USERADD_ARGS="-m -s /bin/bash -g $USERNAME -d /home/$USERNAME -c ${USERNAME^} Service Account"
    [[ -n "$USER_UID" ]] && USERADD_ARGS="$USERADD_ARGS -u $USER_UID"
    [[ -n "$USER_GID" ]] && {
        # Ensure group exists with correct GID first
        if ! getent group "$USERNAME" >/dev/null 2>&1; then
            $DEBUG && echo "Creating group '$USERNAME' with GID $USER_GID..."
            sudo groupadd -g "$USER_GID" "$USERNAME"
        fi
    }
    
    sudo useradd $USERADD_ARGS "$USERNAME"

    if [[ $? -ne 0 ]]; then
        echo  "Result  : Error: Failed to create user '$USERNAME'."
        exit 1
    fi
    echo "Result  : User '$USERNAME' service account created successfully."

    # Set the password
    $DEBUG && echo "Setting password for user '$USERNAME'..."
    echo "$USERNAME:$PASSWORD" | sudo chpasswd
    echo  "Result  : Password for user '$USERNAME' set successfully."
fi

# Ensure the home directory exists
if [[ ! -d "/home/$USERNAME" ]]; then
    if $CHECK; then
        echo  "Result  : Home directory needs to be created."
    else
        $DEBUG && echo "Creating home directory for '$USERNAME'..."
        sudo mkdir -p "/home/$USERNAME"
        sudo chown "$USERNAME:$USERNAME" "/home/$USERNAME"
        echo  "Result  : Home directory for '$USERNAME' created."
    fi
else
    echo  "Result  : Home directory for '$USERNAME' already exists."
fi

# Add the user to groups
SERVICE_GROUPS=("sudo" "docker" "users" "sshusers")
for group in "${SERVICE_GROUPS[@]}"; do
    if groups "$USERNAME" | grep -qw "$group"; then
        echo  "Result  : User '$USERNAME' is already a member of the group '$group'."
    else
        if $CHECK; then
            echo  "Result  : User '$USERNAME' needs to be added to the group '$group'."
        else
            $DEBUG && echo "Adding user '$USERNAME' to the group '$group'..."
            sudo usermod -aG "$group" "$USERNAME"
            echo  "Result  : User '$USERNAME' added to the group '$group'."
        fi
    fi
done

echo "Result  : assert_service_account.sh completed successfully."
