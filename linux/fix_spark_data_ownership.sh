#!/bin/bash

# Fix ownership of spark data files to spark:spark with group permissions
# This script changes ownership and sets appropriate permissions for NFS sharing

# Parse arguments
DEBUG=false
CHECK=false
DATA_DIR="/srv/nfs/spark/data"

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
        --DataDir|-D)
            DATA_DIR=$2
            shift
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--DataDir|-D <path>]"
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Starting: $script_name: root_dir = $root_dir"
$DEBUG && echo "Data directory: $DATA_DIR"

# Function to check if spark user exists
check_spark_user() {
    if getent passwd spark >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to check if spark group exists
check_spark_group() {
    if getent group spark >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to fix ownership and permissions
fix_ownership_and_permissions() {
    echo "Info    : Fixing ownership and permissions for $DATA_DIR..."
    
    if ! $CHECK; then
        # Check if spark user and group exist
        if ! check_spark_user; then
            echo "Error   : spark user does not exist. Run assert_spark_user.sh first."
            return 1
        fi
        
        if ! check_spark_group; then
            echo "Error   : spark group does not exist. Run assert_spark_user.sh first."
            return 1
        fi
        
        # Change ownership to spark:spark
        echo "Info    : Changing ownership to spark:spark..."
        sudo chown -R spark:spark "$DATA_DIR"
        if [ $? -eq 0 ]; then
            echo "Success : Ownership changed to spark:spark"
        else
            echo "Error   : Failed to change ownership"
            return 1
        fi
        
        # Set group permissions to read/write for group members
        echo "Info    : Setting group permissions to rw..."
        sudo chmod -R g+rw "$DATA_DIR"
        if [ $? -eq 0 ]; then
            echo "Success : Group permissions set to rw"
        else
            echo "Error   : Failed to set group permissions"
            return 1
        fi
        
        # Set directory permissions to allow group access
        echo "Info    : Setting directory permissions for group access..."
        sudo find "$DATA_DIR" -type d -exec chmod g+x {} \;
        if [ $? -eq 0 ]; then
            echo "Success : Directory permissions set for group access"
        else
            echo "Error   : Failed to set directory permissions"
            return 1
        fi
        
    else
        echo "Check   : Would change ownership of $DATA_DIR to spark:spark"
        echo "Check   : Would set group permissions to rw"
        echo "Check   : Would set directory permissions for group access"
    fi
}

# Function to verify ownership and permissions
verify_ownership_and_permissions() {
    echo "Info    : Verifying ownership and permissions..."
    
    if [ -d "$DATA_DIR" ]; then
        local owner=$(stat -c '%U:%G' "$DATA_DIR")
        local permissions=$(stat -c '%a' "$DATA_DIR")
        echo "Info    : $DATA_DIR owner: $owner, permissions: $permissions"
        
        # Check a sample file
        local sample_file=$(find "$DATA_DIR" -type f | head -1)
        if [ -n "$sample_file" ]; then
            local file_owner=$(stat -c '%U:%G' "$sample_file")
            local file_permissions=$(stat -c '%a' "$sample_file")
            echo "Info    : Sample file $sample_file owner: $file_owner, permissions: $file_permissions"
        fi
    else
        echo "Error   : Data directory $DATA_DIR does not exist"
        return 1
    fi
}

# Main execution
echo "Info    : Fixing spark data ownership and permissions..."

# Fix ownership and permissions
fix_ownership_and_permissions

# Verify changes
if ! $CHECK; then
    verify_ownership_and_permissions
fi

echo "Result  : Spark data ownership and permissions fixed successfully"
