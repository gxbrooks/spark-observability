#!/usr/bin/bash

# Ensure the script is called with the required argument
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <username>@<hostname>"
    exit 1
fi

TARGET=$1

# Define paths and naming conventions
HOSTNAME=$(hostname)
WINRM_DIR="$HOME/.winrm"
PUBLIC_CERT_PATH="$WINRM_DIR/ansible_client_cert_${HOSTNAME}.cer"

# Check if the public certificate exists
if [ ! -f "$PUBLIC_CERT_PATH" ]; then
    echo "Error: Public certificate not found at $PUBLIC_CERT_PATH. Ensure it exists before running this script."
    exit 1
fi

# Define the remote path where the certificate will be copied
REMOTE_PATH="/home/${TARGET%@*}/.winrm/"

# Copy the certificate using scp
echo "Copying public certificate to $TARGET:$REMOTE_PATH"
scp "$PUBLIC_CERT_PATH" "$TARGET:$REMOTE_PATH"
if [ $? -eq 0 ]; then
    echo "Certificate successfully copied to $TARGET:$REMOTE_PATH"
else
    echo "Error: Failed to copy the certificate."
    exit 1
fi