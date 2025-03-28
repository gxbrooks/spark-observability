#!/usr/bin/bash

# -----------------------------------------------------------------------------
# Script Name: checkWinRmClient.sh
#
# Description: This script checks for the existence of a private key and public
#              certificate required for client authentication by WinRM servers.
#              It can also generate them if they are missing and the --fix flag is 
#              provided. 
#              Once the public key is generated, it can be copied to winRM servers 
#              (managed nodes)
#              and then imported into the trusted root certificate store.
#
# Author:      Gary Brooks
# Usage:       ./checkWinRmClient.sh [--fix|-f] [--debug|-d]
# Options:
#   --fix, -f    Automatically fix issues by creating missing files or directories.
#   --debug, -d  Enable debug mode to display detailed output.
# -----------------------------------------------------------------------------

FIX=false
DEBUG=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --fix|-f) FIX=true ;;
        --debug|-d) DEBUG=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Define paths and naming conventions
HOSTNAME=$(hostname)
WINRM_DIR="$HOME/.winrm"
PRIVATE_KEY_PATH="$WINRM_DIR/ansible_client_private_key.pem"
PUBLIC_CERT_PATH="$WINRM_DIR/ansible_client_cert_${HOSTNAME}.cer"

# Ensure the .winrm directory exists
$DEBUG && echo "Checking: directory: $WINRM_DIR"
if [ -d "$WINRM_DIR" ]; then
    CURRENT_PERMS=$(stat -c "%a" "$WINRM_DIR")
    if [ "$CURRENT_PERMS" != "700" ]; then
        chmod 700 "$WINRM_DIR"
        $DEBUG && echo "Fixing  : Permissions for $WINRM_DIR set to 700."
    else
        $DEBUG && echo "Result  : Permissions for $WINRM_DIR are already set to 700."
    fi
else 
    if $FIX; then
        mkdir -p "$WINRM_DIR"
        chmod 700 "$WINRM_DIR"
        $DEBUG && echo "Fixing  : Created directory: $WINRM_DIR with permissions set to 700."
    else
        echo "Result  : Directory $WINRM_DIR does not exist."
    fi
fi

# Check for private key
if $DEBUG; then echo "Checking: private key at $PRIVATE_KEY_PATH"; fi
if [ -f "$PRIVATE_KEY_PATH" ]; then
    echo "Result  : Private key exists at $PRIVATE_KEY_PATH."
else
    if $FIX; then
        openssl genrsa -out "$PRIVATE_KEY_PATH" 2048
        chmod 600 "$PRIVATE_KEY_PATH"
        $DEBUG && echo "Generated new private key at $PRIVATE_KEY_PATH."
    else
        echo "Result  : Private key not found at $PRIVATE_KEY_PATH."
    fi
fi

# Check for public certificate
if $DEBUG; then echo "Checking: Public certificate at $PUBLIC_CERT_PATH..."; fi
if [ -f "$PUBLIC_CERT_PATH" ]; then
    echo "Result  : Public certificate exists at $PUBLIC_CERT_PATH."
else
    if $FIX; then
        openssl req -new -x509 -key "$PRIVATE_KEY_PATH" -out "$PUBLIC_CERT_PATH" -days 365 -subj "/CN=$HOSTNAME"
        chmod 644 "$PUBLIC_CERT_PATH"
        $DEBUG && echo "Result  : Generated new public certificate at $PUBLIC_CERT_PATH."
    else
        echo "Result  : Public certificate not found at $PUBLIC_CERT_PATH."
    fi
fi
