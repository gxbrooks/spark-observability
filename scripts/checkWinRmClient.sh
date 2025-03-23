#!/usr/bin/bash

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
if [ ! -d "$WINRM_DIR" ]; then
    if $FIX; then
        $DEBUG && echo "Creating directory: $WINRM_DIR"
        mkdir -p "$WINRM_DIR"
        echo "Created directory: $WINRM_DIR"
    else
        echo "Error: Directory $WINRM_DIR does not exist."
    fi
fi

# Check for private key
if $DEBUG; then echo "Checking for private key at $PRIVATE_KEY_PATH..."; fi
if [ -f "$PRIVATE_KEY_PATH" ]; then
    echo "Private key exists at $PRIVATE_KEY_PATH."
else
    echo "Error: Private key not found at $PRIVATE_KEY_PATH."
    if $FIX; then
        $DEBUG && echo "Generating new private key..."
        openssl genrsa -out "$PRIVATE_KEY_PATH" 2048
        chmod 600 "$PRIVATE_KEY_PATH"
        echo "Generated new private key at $PRIVATE_KEY_PATH."
    fi
fi

# Check for public certificate
if $DEBUG; then echo "Checking for public certificate at $PUBLIC_CERT_PATH..."; fi
if [ -f "$PUBLIC_CERT_PATH" ]; then
    echo "Public certificate exists at $PUBLIC_CERT_PATH."
else
    if $FIX; then
        $DEBUG && echo "Generating new public certificate..."
        openssl req -new -x509 -key "$PRIVATE_KEY_PATH" -out "$PUBLIC_CERT_PATH" -days 365 -subj "/CN=$HOSTNAME"
        chmod 644 "$PUBLIC_CERT_PATH"
        $DEBUG && echo "Generated new public certificate at $PUBLIC_CERT_PATH."
    else
        echo "Error: Public certificate not found at $PUBLIC_CERT_PATH."
    fi
fi
