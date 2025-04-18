#!/usr/bin/bash

# -----------------------------------------------------------------------------
# Script Name: newWinRmClientCert.sh
#
# Description: This script checks for the existence of a private key and public
#              certificate required for client authentication by WinRM servers.
#              It can also generate them if they are missing and the --check flag is 
#              provided. 
#              Once the public key is generated, it can be copied to winRM servers 
#              (managed nodes)
#              and then imported into the trusted root certificate store.
#
# Author:      Gary Brooks
# Usage:       ./newWinRmClientcert.sh [--check|-c] [--debug|-d] [--force|-f] [--user|-u <username>]
# Options:
#   --check, -c  Automatically check and create missing files or directories.
#   --debug, -d  Enable debug mode to display detailed output.
#   --force, -f  Force the creation of the certificates even if they exist.
# -----------------------------------------------------------------------------

# Global parameters that define the operating mode
CHECK=false
DEBUG=false
FORCE=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --check|-c) CHECK=true ;;
        --debug|-d) DEBUG=true ;;
        --force|-f) FORCE=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Global constansts (aka class-like) that define paths and naming conventions
USER="ansible" # The local account for WinRM on the Windows managed hosts
HOSTNAME=$(hostname -s) # Short hostname (e.g., "garypc")
CERT_DIR="$HOME/.winrm"
PRIVATE_KEY_PATH="$CERT_DIR/ansible_client_private_key.pem"
PUBLIC_CSR_PATH="$CERT_DIR/ansible_client_csr.pem"
PUBLIC_CERT_PATH="$CERT_DIR/ansible_client_cert.pem"


new_client_cert() {

    # in case there are multiple Ansible control nodes, the CN of the client certificate must
    # be different across each Ansible isntance. 
    username="$USER-$HOSTNAME"

    # The SAN attributes cannot be defined directly on the command line, hence the use of openssl.conf.
    # from https://docs.ansible.com/ansible/latest/os_guide/windows_winrm_certificate.html
    # The UPN is used to identify the client certificate. It must be unique across all Ansible control nodes.
    # UPN="ansible@${HOSTNAME}.lan"  # Machine-specific UPN
    UPN="ansible@localhost"  # Machine-specific UPN
    DAYS_VALID=365

    if [[ -n "$DEBUG" ]]; then
        echo "Action  : Generating self-signed public certificate at '$PUBLIC_CERT_PATH'."
    fi

    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "$PRIVATE_KEY_PATH" \
        -out "$PUBLIC_CERT_PATH" \
        -days "$DAYS_VALID" \
        -subj "/CN=Ansible Client" \
        -addext "subjectAltName=otherName:1.3.6.1.4.1.311.20.2.3;UTF8:$UPN" \
        -addext "keyUsage=digitalSignature,keyEncipherment" \
        -addext "extendedKeyUsage=clientAuth" >& /dev/null
    if [ $? -ne 0 ]; then
        echo "Error   : Failed to generate the self-signed public certificate."
        exit 1
    fi
    chmod 600 "$PRIVATE_KEY_PATH"
    chmod 644 "$PUBLIC_CERT_PATH"
        
    thumbprint=$(openssl x509 -in $PUBLIC_CERT_PATH -noout -fingerprint -sha1 | sed 's/sha1 Fingerprint=//g' | tr -d ':')
    echo "Result  : Created the private key and a certificate with thumbprint '$thumbprint'."
}

# Ensure the .winrm directory exists
$DEBUG && echo "Checking: directory: '$CERT_DIR'"
if [ -d "$CERT_DIR" ]; then
    echo "Result  : Directory '$CERT_DIR' exists."
    CURRENT_PERMS=$(stat -c "%a" "$CERT_DIR")
    if [ "$CURRENT_PERMS" != "700" ]; then
        if ! $CHECK; then
            chmod 700 "$CERT_DIR"
            echo "Result  : Set permissions for '$CERT_DIR' set to 700."
        else 
            echo "Result  : Permissions for '$CERT_DIR' are incorrect. Expected 700, found '$CURRENT_PERMS'."
        fi
    else
        $DEBUG && echo "Result  : Permissions for '$CERT_DIR' are already set to 700."
    fi
else 
    if ! $CHECK; then
        mkdir -p "$CERT_DIR"
        chmod 700 "$CERT_DIR"
        $DEBUG && echo "Fixing  : Created directory: '$CERT_DIR' with permissions set to 700."
    else
        echo "Result  : Directory '$CERT_DIR' does not exist."
    fi
fi

# Check for private key and public certificate
PRIVATE_KEY_EXISTS=false
PUBLIC_CERT_EXISTS=false

if [ -f "$PRIVATE_KEY_PATH" ]; then
    PRIVATE_KEY_EXISTS=true
fi

if [ -f "$PUBLIC_CERT_PATH" ]; then
    PUBLIC_CERT_EXISTS=true
fi

# Decision tree to ensure synchronization of private key and public certificate generation
if $PRIVATE_KEY_EXISTS; then
    if $PUBLIC_CERT_EXISTS; then
        if $FORCE; then
            if $CHECK; then
                thumbprint=$(openssl x509 -in $PUBLIC_CERT_PATH -noout -fingerprint -sha1 | sed 's/sha1 Fingerprint=//g' | tr -d ':')
                echo "Result  : Private key and public certificate ($thumbprint) exist. "
                echo "Result  : Omit the --check flag to recreate."
            else
                echo "Result  : Private key and public certificate exist. Will be recreated."
                new_client_cert
            fi
        else
            thumbprint=$(openssl x509 -in $PUBLIC_CERT_PATH -noout -fingerprint -sha1 | sed 's/sha1 Fingerprint=//g' | tr -d ':')
            echo "Result  : Private key and public certificate ($thumbprint) exist."
        fi
    else
        echo "Result  : Private key exists but public certificate is missing."
        if $CHECK; then
            echo "Result  : Public certificate is missing. Elide the --check option to generate it."
        else
            echo "Result  : Regenerating both private and public keys."
            new_client_cert 
        fi
    fi
elif $PUBLIC_CERT_EXISTS; then
    echo "Result  : Public certificate exists but private key is missing."
    if $CHECK; then
        echo "Result  : Private key is missing. Elide the --check option to generate it."
    else
        echo "Result  : Private key is missing. Will be recreated."
        new_client_cert
    fi
elif $CHECK; then
    echo "Result  : Private key and public certificate are missing."
else 
    echo "Result  : Private key and public certificate do not exist. Will be recreated."
    new_client_cert 
fi
