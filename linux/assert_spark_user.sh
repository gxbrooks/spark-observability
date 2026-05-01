#!/bin/bash

# Assert the spark user and group exist and add the calling user to the spark group
# This script follows the pattern of other initialization scripts with --Debug and --Check flags


# The Spark user exists to:
#   - To run Spark daemons (master, worker, history server) as a dedicated, unprivileged user 
#   rather than root, following the principle of least privilege.
#   - To own Spark's installation directories, log files, and PID files.
#   - To provide process isolation and security boundaries between Spark and other services on the same host.

#
# Spark UID/GID: 185/185
# This MUST match the Kubernetes pod securityContext for proper file ownership

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
    $DEBUG && echo "Debug   : Checking if spark group exists..."
    
    if check_spark_group; then
        # Verify the GID is correct
        CURRENT_GID=$(getent group spark | cut -d: -f3)
        if [ "$CURRENT_GID" != "$SPARK_GID" ]; then
            if $CHECK; then
                echo "Check   : spark group exists with GID $CURRENT_GID - would change to $SPARK_GID"
            else
                echo "Info    : spark group exists with GID $CURRENT_GID - changing to $SPARK_GID..."
                sudo groupmod -g "$SPARK_GID" spark
                if [ $? -eq 0 ]; then
                    echo "Success : spark group GID changed to $SPARK_GID"
                else
                    echo "Error   : Failed to change spark group GID"
                    return 1
                fi
            fi
        else
            $DEBUG && echo "Debug   : spark group already exists with correct GID $SPARK_GID"
            if $CHECK; then
                echo "Check   : spark group already exists with correct GID - no change needed"
            else
                echo "Info    : spark group already exists with correct GID - no change needed"
            fi
        fi
    else
        if $CHECK; then
            echo "Check   : spark group does not exist - would create with GID $SPARK_GID"
        else
            echo "Info    : Creating spark group with GID $SPARK_GID..."
            sudo groupadd -g "$SPARK_GID" spark
            if [ $? -eq 0 ]; then
                echo "Success : spark group created with GID $SPARK_GID"
            else
                echo "Error   : Failed to create spark group"
                return 1
            fi
        fi
    fi
}

# Function to create spark user
create_spark_user() {
    $DEBUG && echo "Debug   : Checking if spark user exists..."
    
    if check_spark_user; then
        $DEBUG && echo "Debug   : spark user already exists"
        if $CHECK; then
            echo "Check   : spark user already exists - no change needed"
        else
            echo "Info    : spark user already exists - no change needed"
        fi
    else
        if $CHECK; then
            echo "Check   : spark user does not exist - would create with UID $SPARK_UID"
        else
            echo "Info    : Creating spark user with UID $SPARK_UID..."
            sudo useradd -u "$SPARK_UID" -g "$SPARK_GID" -m -s /bin/bash spark
            if [ $? -eq 0 ]; then
                echo "Success : spark user created with UID $SPARK_UID"
            else
                echo "Error   : Failed to create spark user"
                return 1
            fi
        fi
    fi
}

# Function to add user to spark group
add_user_to_spark_group() {
    local username=$1
    $DEBUG && echo "Debug   : Checking if user '$username' is in spark group..."
    
    if check_user_in_spark_group "$username"; then
        $DEBUG && echo "Debug   : User '$username' is already in spark group"
        if $CHECK; then
            echo "Check   : User '$username' is already in spark group - no change needed"
        else
            echo "Info    : User '$username' is already in spark group - no change needed"
        fi
    else
        if $CHECK; then
            echo "Check   : User '$username' is not in spark group - would add to spark group"
        else
            echo "Info    : Adding user '$username' to spark group..."
            sudo usermod -a -G spark "$username"
            if [ $? -eq 0 ]; then
                echo "Success : User '$username' added to spark group"
                echo "Info    : User may need to log out and back in for group changes to take effect"
            else
                echo "Error   : Failed to add user '$username' to spark group"
                return 1
            fi
        fi
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
$DEBUG && echo "Debug   : Starting spark user and group setup..."

# Create spark group
create_spark_group

# Create spark user
create_spark_user

# Add current user to spark group
add_user_to_spark_group "$USER"

# Add elastic-agent user to spark group if it exists (for file access to Spark logs)
if getent passwd elastic-agent >/dev/null 2>&1; then
    $DEBUG && echo "Debug   : elastic-agent user exists, adding to spark group..."
    add_user_to_spark_group "elastic-agent"
else
    $DEBUG && echo "Debug   : elastic-agent user does not exist, skipping..."
fi

# Verify setup
if ! $CHECK; then
    verify_spark_setup
fi

echo "Result  : Spark user and group setup completed successfully"
