#!/bin/bash

# Function to check if a certificate and private key match
verify_cert_key() {
  local cert_file="$1"
  local key_file="$2"
  echo "verifying  : $cert_file"
  echo "private key: $key_file"
  if [[ ! -f "$cert_file" ]]; then
    echo "Error: Certificate file '$cert_file' not found."
    return 1
  fi

  if [[ ! -f "$key_file" ]]; then
    echo "Error: Private key file '$key_file' not found."
    return 1
  fi

  # Extract the public key from the certificate
  cert_public_key=$(openssl x509 -noout -modulus -in "$cert_file")

  # Extract the public key from the private key
  key_public_key=$(openssl rsa -noout -modulus -in "$key_file")

  # Compare the public keys
  if [[ "$cert_public_key" == "$key_public_key" ]]; then
    echo "Certificate and private key match."
    return 0
  else
    echo "Certificate and private key DO NOT match."
    return 1
  fi
}

# Example usage (replace with your certificate and key file paths)
certificate_file="/home/gxbrooks/.winrm/ansible_client_cert.pem"
private_key_file="/home/gxbrooks/.winrm/ansible_client_private_key.pem"

if verify_cert_key "$certificate_file" "$private_key_file"; then
  echo "Verification successful."
else
  echo "Verification failed."
fi
