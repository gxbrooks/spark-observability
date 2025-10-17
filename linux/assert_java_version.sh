#!/bin/bash

# Assert Java Version
#
# Ensures the specified Java version is installed and available.
# If the version is not installed, attempts to install it.
#
# This script is idempotent and can be run multiple times safely.

# Parse arguments
DEBUG=false
CHECK=false
JAVA_VERSION="17"

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
        --JavaVersion|-jv)
            JAVA_VERSION=$2
            shift
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name."
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--JavaVersion|-jv <version>]"
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Debug   : Requested Java version: $JAVA_VERSION"

# Check if Java is installed
if command -v java >/dev/null 2>&1; then
    current_version=$(java -version 2>&1 | head -n 1)
    $DEBUG && echo "Debug   : Current Java: $current_version"
    
    # Check if the right version is installed
    if echo "$current_version" | grep -q "openjdk version \"$JAVA_VERSION"; then
        echo "Info    : Java $JAVA_VERSION is already installed"
        if $CHECK; then
            exit 0
        fi
    fi
fi

# Install Java if not in check mode
if ! $CHECK; then
    echo "Info    : Installing OpenJDK $JAVA_VERSION..."
    if sudo apt update && sudo apt install -y openjdk-${JAVA_VERSION}-jdk-headless; then
        echo "Info    : OpenJDK $JAVA_VERSION installed successfully"
        
        # Verify installation
        if java -version 2>&1 | grep -q "openjdk version \"$JAVA_VERSION"; then
            echo "Result  : Java $JAVA_VERSION is now active"
        else
            echo "Warning : Java $JAVA_VERSION installed but may need to be selected"
            echo "Info    : Run 'sudo update-alternatives --config java' to select Java $JAVA_VERSION"
        fi
    else
        echo "Error   : Failed to install OpenJDK $JAVA_VERSION"
        exit 1
    fi
else
    echo "Info    : Check mode - would install Java $JAVA_VERSION"
fi

