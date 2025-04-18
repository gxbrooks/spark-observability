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
PUBLIC_CERT_PATH="$WINRM_DIR/ansible_client_cert.pem"

# Check if the public certificate exists
if [ ! -f "$PUBLIC_CERT_PATH" ]; then
    echo "Error: Public certificate not found at $PUBLIC_CERT_PATH. Run createWinRmClientCert.sh to create it."
    exit 1
fi

# Define the remote path where the certificate will be copied (Windows path)
# REMOTE_PATH="/C/Users/${TARGET%@*}/.winrm/"
# Despite what you might read in some circles, the drive letter *must* be used in the path.
# Either slashes or backslashes can be used as path separators.
# Add .lan to the hostname to make it a FQDN. This FQDN is used in the Ansible inventory.yml file.
# The rational is that a FQDN will force the use of the DNS server for name resolution. This will 
# avoid subtle ssh behavior that will map a plain WSL hostname to the loop back address.
REMOTE_PATH="C:\\Users\\${TARGET%@*}\\.winrm\\ansible_client_cert@${HOSTNAME}.lan.pem"

# Copy the certificate using scp
thumbprint=$(openssl x509 -in $PUBLIC_CERT_PATH -noout -fingerprint -sha1 | sed 's/sha1 Fingerprint=//g' | tr -d ':')
echo "Copying certificate ($thumbprint)"
scp -q "$PUBLIC_CERT_PATH" $TARGET:"$REMOTE_PATH" 
if [ $? -eq 0 ]; then
    echo "Certificate successfully copied to $TARGET:$REMOTE_PATH"
else
    echo "Error: Failed to copy the certificate."
    exit 1
fi