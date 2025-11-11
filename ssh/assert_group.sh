#!/usr/bin/bash

CHECK=false
DEBUG=false
GROUP_NAME=""
GROUP_GID=""

for arg in "$@"; do
    case $arg in
        --Group|-g)
            GROUP_NAME=$2
            shift
            ;;
        --GID)
            GROUP_GID=$2
            shift
            ;;
        --Check|-c) CHECK=true ;;
        --Debug|-d) DEBUG=true ;;
    esac
    shift
done

if [[ -z "$GROUP_NAME" ]]; then
    echo "Error   : --Group or -g parameter is required."
    exit 1
fi

# Check if the group exists
$DEBUG && echo "Checking: Does group '$GROUP_NAME' exist with GID $GROUP_GID?"
if ! getent group "$GROUP_NAME" > /dev/null; then
    if $CHECK; then
        if [[ -n "$GROUP_GID" ]]; then
            echo  "Result  : Group '$GROUP_NAME' does not exist - would create with GID $GROUP_GID"
        else
            echo  "Result  : Group '$GROUP_NAME' does not exist - would create"
        fi
    else
        if [[ -n "$GROUP_GID" ]]; then
            sudo groupadd -g "$GROUP_GID" "$GROUP_NAME"
            echo  "Result  : Group '$GROUP_NAME' created with GID $GROUP_GID"
        else
            sudo groupadd "$GROUP_NAME"
            echo  "Result  : Group '$GROUP_NAME' created successfully."
        fi
    fi
else
    # Group exists - verify GID if specified
    if [[ -n "$GROUP_GID" ]]; then
        CURRENT_GID=$(getent group "$GROUP_NAME" | cut -d: -f3)
        if [[ "$CURRENT_GID" != "$GROUP_GID" ]]; then
            if $CHECK; then
                echo  "Check   : Group '$GROUP_NAME' has GID $CURRENT_GID - would change to $GROUP_GID"
            else
                echo  "Info    : Changing GID for '$GROUP_NAME' from $CURRENT_GID to $GROUP_GID..."
                sudo groupmod -g "$GROUP_GID" "$GROUP_NAME"
                echo  "Result  : Group '$GROUP_NAME' GID updated to $GROUP_GID"
            fi
        else
            echo  "Result  : Group '$GROUP_NAME' already exists with correct GID $GROUP_GID"
        fi
    else
        echo  "Result  : Group '$GROUP_NAME' already exists."
    fi
fi