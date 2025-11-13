#!/bin/bash

CERT_PATH=~/.winrm/ansible_client_cert.pem
KEY_PATH=~/.winrm/ansible_client_private_key.pem
SELF_SIGNED_CA_PATH=~/.winrm/WinRM_SSL_Cert@GaryPC.local.pem
WINRM_ENDPOINT=https://GaryPC.local:5986/wsman

# Extract certificate (if needed)
if [[ ! -f "$CERT_PATH" ]]; then
  openssl pkcs12 -in ~/.winrm/ansible_client_private_key.pem -clcerts -nokeys -out ~/.winrm/ansible_client_cert.pem
fi

# Test WinRM connection
# --insecure
curl \
    --cacert $SELF_SIGNED_CA_PATH \
    --cert "$CERT_PATH" \
    --key "$KEY_PATH" \
    "$WINRM_ENDPOINT"

# Verify certificate chain (optional)
# openssl verify -CAfile /path/to/ca.pem "$CERT_PATH"

# Error Handling
if [[ $? -ne 0 ]]; then
    echo "WinRM client certificate authentication test failed."
    exit 1
else
    echo "WinRM client certificate authentication test successful."
fi
