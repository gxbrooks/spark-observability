#!/usr/bin/env bash
# Verify that a PEM certificate and RSA private key match (modulus comparison).
# Usage: verify_certs.sh /path/to/cert.pem /path/to/key.pem

set -euo pipefail

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
  cert_public_key=$(openssl x509 -noout -modulus -in "$cert_file")
  key_public_key=$(openssl rsa -noout -modulus -in "$key_file")
  if [[ "$cert_public_key" == "$key_public_key" ]]; then
    echo "Certificate and private key match."
    return 0
  fi
  echo "Certificate and private key DO NOT match."
  return 1
}

certificate_file="${1:-}"
private_key_file="${2:-}"

if [[ -z "$certificate_file" || -z "$private_key_file" ]]; then
  echo "Usage: $0 <cert.pem> <key.pem>" >&2
  exit 2
fi

if verify_cert_key "$certificate_file" "$private_key_file"; then
  echo "Verification successful."
else
  echo "Verification failed."
  exit 1
fi
