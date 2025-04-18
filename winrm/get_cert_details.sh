#!/bin/bash

# Function to extract certificate information
extract_cert_info() {
  local cert_file="$1"
  local cert_name=$(basename "$cert_file")

  if [[ ! -f "$cert_file" ]]; then
    echo "Error: Certificate file '$cert_file' not found."
    return 1
  fi

  echo "--------------------------------------------------------"
  echo "Certificate: $cert_name"
  echo ""

  # Extract Subject (CN)
  subject=$(openssl x509 -noout -subject -in "$cert_file" | sed 's/subject=//')
  printf "%-20s: %s\n" "Subject" "${subject:-Not Found}"

  # Extract Issuer
  issuer=$(openssl x509 -noout -issuer -in "$cert_file" | sed 's/issuer=//')
  printf "%-20s: %s\n" "Issuer" "${issuer:-Not Found}"

  # Extract Thumbprint (SHA-1)
  thumbprint=$(openssl x509 -noout -fingerprint -sha1 -in "$cert_file" | cut -d'=' -f2 | tr -d ':')
  printf "%-20s: %s\n" "Thumbprint (SHA-1)" "${thumbprint:-Not Found}"

  # Extract Validity Dates
  valid_before=$(openssl x509 -noout -startdate -in "$cert_file" | sed 's/notBefore=//')
  valid_after=$(openssl x509 -noout -enddate -in "$cert_file" | sed 's/notAfter=//')
  printf "%-20s: %s\n" "Valid Before" "${valid_before:-Not Found}"
  printf "%-20s: %s\n" "Valid After" "${valid_after:-Not Found}"

  # Extract Serial Number
  serial=$(openssl x509 -noout -serial -in "$cert_file" | sed 's/serial=//')
  printf "%-20s: %s\n" "Serial Number" "${serial:-Not Found}"

  # Extract Public Key Algorithm
  rawpubkeyalg=$(openssl x509 -noout -text -in "$cert_file" | grep "Public Key Algorithm" | head -n 1 | sed 's/^[[:space:]]*//')
  printf "%-20s: %s\n" "Public Key Algorithm" "${rawpubkeyalg:-Not Found}"

  # Extract DNS Names and Subject Alternative Names (SANs)
  san=$(openssl x509 -noout -text -in "$cert_file" | grep -A 1 "Subject Alternative Name" | tail -n 1 | sed 's/^[[:space:]]*//')
  printf "%-20s: %s\n" "SAN" "${san:-Not Found}"

  # Extract UPN (if present)
  upn=$(openssl x509 -noout -ext subjectAltName -in "$cert_file" | grep "othername" | sed -E 's/.*UPN::([^,]+).*/\1/' | sed 's/^[[:space:]]*//')
  printf "%-20s: %s\n" "UPN" "${upn:-Not Found}"

  # Extract Key Usage
  key_usage=$(openssl x509 -noout -text -in "$cert_file" | grep -A 1 "Key Usage" | tail -n 1 | sed 's/^[[:space:]]*//')
  printf "%-20s: %s\n" "Key Usage" "${key_usage:-Not Found}"

  # Extract Extended Key Usage (EKU)
  eku=$(openssl x509 -noout -text -in "$cert_file" | grep -A 1 "Extended Key Usage" | tail -n 1 | sed 's/^[[:space:]]*//')
  printf "%-20s: %s\n" "Extended Key Usage" "${eku:-Not Found}"

  echo "" # Add a blank line for readability
}

# Check if a certificate file is provided as an argument
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <certificate_file>"
  exit 1
fi

# Extract information from the provided certificate file
extract_cert_info "$1"