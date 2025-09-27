#!/bin/bash

# Assert the spark user and group exist and add the calling user to the spark group
# This script follows the pattern of other initialization scripts with --Debug and --Check flags

# Parse arguments
DEBUG=false
CHECK=false
SPARK_UID=185
SPARK_GID=185

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
        --SparkUID|-u)
            SPARK_UID=$2
            shift
            ;;
        --SparkGID|-g)
            SPARK_GID=$2
            shift
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--SparkUID|-u <uid>] [--SparkGID|-g <gid>]"
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Starting: $script_name: root_dir = $root_dir"
$DEBUG && echo "Target Spark UID: $SPARK_UID, GID: $SPARK_GID"

# Function to check if spark group exists
check_spark_group() {
    if getent group spark >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to check if spark user exists
check_spark_user() {
    if getent passwd spark >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to check if current user is in spark group
check_user_in_spark_group() {
    local username=$1
    if groups "$username" | grep -q "\bspark\b"; then
        return 0
    else
        return 1
    fi
}

# Function to create spark group
create_spark_group() {
    echo "Info    : Creating spark group with GID $SPARK_GID..."
    
    if ! $CHECK; then
        if ! check_spark_group; then
            sudo groupadd -g "$SPARK_GID" spark
            if [ $? -eq 0 ]; then
                echo "Success : spark group created with GID $SPARK_GID"
            else
                echo "Error   : Failed to create spark group"
                return 1
            fi
        else
            echo "Info    : spark group already exists"
        fi
    else
        echo "Check   : Would create spark group with GID $SPARK_GID"
    fi
}

# Function to create spark user
create_spark_user() {
    echo "Info    : Creating spark user with UID $SPARK_UID..."
    
    if ! $CHECK; then
        if ! check_spark_user; then
            sudo useradd -u "$SPARK_UID" -g "$SPARK_GID" -m -s /bin/bash spark
            if [ $? -eq 0 ]; then
                echo "Success : spark user created with UID $SPARK_UID"
            else
                echo "Error   : Failed to create spark user"
                return 1
            fi
        else
            echo "Info    : spark user already exists"
        fi
    else
        echo "Check   : Would create spark user with UID $SPARK_UID"
    fi
}

# Function to add user to spark group
add_user_to_spark_group() {
    local username=$1
    echo "Info    : Adding user '$username' to spark group..."
    
    if ! $CHECK; then
        if ! check_user_in_spark_group "$username"; then
            sudo usermod -a -G spark "$username"
            if [ $? -eq 0 ]; then
                echo "Success : User '$username' added to spark group"
                echo "Info    : User may need to log out and back in for group changes to take effect"
            else
                echo "Error   : Failed to add user '$username' to spark group"
                return 1
            fi
        else
            echo "Info    : User '$username' is already in spark group"
        fi
    else
        echo "Check   : Would add user '$username' to spark group"
    fi
}

# Function to verify spark user setup
verify_spark_setup() {
    echo "Info    : Verifying spark user and group setup..."
    
    if check_spark_group; then
        local group_info=$(getent group spark)
        echo "Success : spark group exists: $group_info"
    else
        echo "Error   : spark group does not exist"
        return 1
    fi
    
    if check_spark_user; then
        local user_info=$(getent passwd spark)
        echo "Success : spark user exists: $user_info"
    else
        echo "Error   : spark user does not exist"
        return 1
    fi
    
    if check_user_in_spark_group "$USER"; then
        echo "Success : Current user '$USER' is in spark group"
    else
        echo "Warning : Current user '$USER' is not in spark group"
        echo "Info    : User may need to log out and back in for group changes to take effect"
    fi
}

# Main execution
echo "Info    : Setting up spark user and group..."

# Create spark group
create_spark_group

# Create spark user
create_spark_user

# Add current user to spark group
add_user_to_spark_group "$USER"

# Verify setup
if ! $CHECK; then
    verify_spark_setup
fi

echo "Result  : Spark user and group setup completed successfully"
