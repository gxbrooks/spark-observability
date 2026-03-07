#!/usr/bin/bash

# Create all the private keys and public certificates needed for Spark Observability.
#
# For comprehensive architecture documentation, see:
#   docs/CA_CERTIFICATE_ARCHITECTURE.md
#
# This script implements the certificate generation and publishing layer of the pull-based
# certificate distribution architecture.

# Elasticsearch X-Pack Requirement:
# X-Pack requires all certificates to be rooted at /usr/share/elasticsearch/config/certs.
# This path is hardcoded in this script (CA_BASE_DIR) as it's a mandatory X-Pack requirement.

# This file needs to run as root

# Certificate Structure:
# The elasticsearch-certutil creates a zip file based on ./certs/instances.yml with:
#
#     certs/
#     ├── ca/
#     │   ├── ca.crt          # CA certificate (public)
#     │   ├── ca.key          # CA private key
#     │   └── ca.srl         # Serial number file
#     ├── certs.zip          # Archive of all certificates
#     ├── es01/
#     │   ├── es01.crt
#     │   └── es01.key
#     └── kibana/
#         ├── kibana.crt
#         └── kibana.key

# Certificate Paths:
# - Internal (Elasticsearch): /usr/share/elasticsearch/config/certs/ca/ca.crt
#   (Hardcoded X-Pack requirement - see CA_BASE_DIR below)
# - Published (CA_CERT): /etc/ssl/certs/elastic/ca.crt
#   (Standard path for all services - defined in vars/variables.yaml)
#
# The CA certificate is published to CA_CERT for distribution to:
# - Docker containers (via mount in docker-compose.yml)
# - Linux hosts (via Ansible fetch from Docker volume)
# - Windows hosts (if needed, via WSL mount)

# Environment Variable:
# CA_CERT: Path where the public CA certificate should be published
#          Default: /etc/ssl/certs/elastic/ca.crt (from vars/variables.yaml)
#          This is the single source of truth path used by all services.

# exit the script immediately if any command fails
set -e

# Parse arguments for --force
FORCE=0
for arg in "$@"; do
  if [[ "$arg" == "--force" ]]; then
    FORCE=1
  fi
done

# CA_CERT environment variable is required (set by docker-compose.yml from vars/variables.yaml)
# This is the standard path where all services expect to find the CA certificate
if [ ! -v CA_CERT ] ; then
  echo "❌ Error: CA_CERT environment variable not defined"
  echo "   CA_CERT should be set to /etc/ssl/certs/elastic/ca.crt (from vars/variables.yaml)"
  exit 1
fi

# Create the published certificate directory
mkdir -p $(dirname "$CA_CERT")

# Certificate store policy:
# Only the Elastic CA certificate and Grafana SSL certificate (and the Elasticsearch/Kibana
# identity certs required for the stack) are created and stored in the Elasticsearch
# filesystem (certs volume). Any other agent or service that communicates with
# Elasticsearch must obtain the CA certificate from the published path (CA_CERT) during
# install/start—e.g. by copying from the certs volume or from a host path populated
# by Ansible. A more holistic certificate strategy for other services may be adopted later.
#
# Elasticsearch X-Pack Requirement (hardcoded - cannot be parameterized):
# X-Pack requires all certificates to be in /usr/share/elasticsearch/config/certs
# This is a mandatory requirement and cannot be changed.
CA_BASE_DIR="/usr/share/elasticsearch/config" 
CERTS_DIR="$CA_BASE_DIR/certs"
CA_CERT_DIR="$CERTS_DIR/ca"
CA_CERT_PATH="$CA_CERT_DIR/ca.crt"      # Internal path (X-Pack requirement)
CA_KEY_PATH="$CA_CERT_DIR/ca.key"       # Internal path (private key)
CA_VERSION_FILE="$CA_CERT_DIR/.certs_version"  # Version tracking file


# Helper: get CA cert hash
get_ca_hash() {
  if [ -f "$CA_CERT_PATH" ]; then
    sha256sum "$CA_CERT_PATH" | awk '{print $1}'
  else
    echo ""
  fi
}

# check if the script has already run, unless --force is given
if ! [ -f "$CERTS_DIR/done" ]; then
  # cert generation has not executed successfully
  echo "[init-certs] init-certs has not run successfully, proceeding"
# --Force forces regeneration
elif [ $FORCE -eq 1 ]; then
  echo "[init-certs] Force regeneration of certificates."
# Must regenerate if there is no private CA key or no version
elif [ ! -f "$CA_CERT_PATH" ] || [ ! -f "$CA_VERSION_FILE" ]; then
  echo "[init-certs] CA certificate or version file not found, regenerating certificates."
else
  CA_HASH=$(get_ca_hash)
  MARKER_HASH=$(cat "$CA_VERSION_FILE" 2>/dev/null || echo "")
  if [ "$CA_HASH" != "$MARKER_HASH" ]; then
    echo "[init-certs] CA certificate hash does not match version marker, regenerating certificates."
  else 
    echo "[init-certs] CA certificate hash matches version marker, no regeneration needed."
    # Ensure CA at volume root for containers that mount certs at /etc/ssl/certs/elastic and expect ca.crt there
    cp "$CA_CERT_PATH" "$CERTS_DIR/ca.crt" 2>/dev/null && chmod 644 "$CERTS_DIR/ca.crt" && echo "[init-certs] CA cert at volume root: $CERTS_DIR/ca.crt"
    exit 0
  fi
fi

echo "[init-certs] Generating new CA and service certificates..."
echo "[init-certs] Certificates & keys will be stored in CERTS_DIR='$CERTS_DIR'"
echo "[init-certs] CA cert will be stored in CA_CERT_PATH='$CA_CERT_PATH'"
echo "[init-certs] CA cert will be distributed to  CA_CERT='$CA_CERT'"

# Clean old certs (idempotent)
rm -rf "$CERTS_DIR"/*
# add other service dirs as needed
mkdir -p "$CERTS_DIR/ca" # "$CERTS_DIR/es01" "$CERTS_DIR/logstash01" 
chmod -R 755 "$CERTS_DIR/ca"
echo "[init-certs] Creating self-signed certificat authority"
# elasticsearch-certutil ca --silent \
#   --pem \
#   --out "$CERTS_DIR/ca.zip
# Generate CA
openssl req -x509 -newkey rsa:4096 \
  -days 3650 -nodes \
  -keyout "$CA_KEY_PATH" \
  -out "$CA_CERT_PATH" \
  -subj "/CN=Elastic-Stack-CA"
chmod 600 "$CA_KEY_PATH" 
chmod 644 "$CA_CERT_PATH"
# Save CA cert hash as version marker
get_ca_hash > "$CA_VERSION_FILE"
chmod 644 "$CA_VERSION_FILE"
# Copy CA cert for distribution (published path used by Ansible/hosts)
cp "$CA_CERT_PATH" "$CA_CERT"
# Also copy to volume root so containers mounting certs at /etc/ssl/certs/elastic get ca.crt there
cp "$CA_CERT_PATH" "$CERTS_DIR/ca.crt"
chmod 644 "$CA_CERT_PATH" "$CERTS_DIR/ca.crt"
echo "[init-certs] CA cert distributed to $CA_CERT and $CERTS_DIR/ca.crt"
# Verify CA certificate was created correctly
if openssl x509 -in "$CA_CERT_PATH" -noout -text > /dev/null 2>&1; then
  echo "[init-certs] ✅ CA certificate verified successfully"
  echo "[init-certs] CA Issuer: $(openssl x509 -in "$CA_CERT_PATH" -noout -issuer)"
  echo "[init-certs] CA Validity: $(openssl x509 -in "$CA_CERT_PATH" -noout -dates)"
  echo "[init-certs] CA Serial: $(openssl x509 -in "$CA_CERT_PATH" -noout -serial)"
  echo "[init-certs] CA Fingerprint: $(openssl x509 -in "$CA_CERT_PATH" -noout -fingerprint -sha256)"
else
  echo "[init-certs] ❌ CA certificate verification failed!"
  exit 1
fi

# Certificate published to standard location for pull-based distribution.
# Services fetch certificates from this location during install/start.
# Docker Compose does not orchestrate distribution (layered architecture).
echo "[init-certs] ✅ CA cert published to standard location: $CA_CERT"
echo "[init-certs] Services will fetch certificate from this location during install/start."


echo "[init-certs] Creating Elastic Stack certs"
# what is init for (now) in instance.yml?
# Remove any existing certs zip to avoid errors
rm -f "$CERTS_DIR/certs.zip"

elasticsearch-certutil cert --silent \
  --pem \
  --out "$CERTS_DIR/certs.zip" \
  --in ./certs/instances.yml \
  --ca-cert "$CA_CERT_PATH" \
  --ca-key "$CA_KEY_PATH" 
# chmod 600 "$CERTS_DIR/certs.zip"
unzip -o -q "$CERTS_DIR/certs.zip" -d "$CERTS_DIR"

echo "[init-certs] Creating Grafana key"
mkdir -p "$CERTS_DIR/grafana"

GF_COUNTRY=${GF_COUNTRY:-US}
GF_STATE=${GF_STATE:-TX}
GF_LOCALITY=${GF_LOCALITY:-Frisco}
GF_ORG=${GF_ORG:-Self}
GF_ORGF_UNIT=${GF_ORGF_UNIT:-Self}
GF_COMMON_NAME=${GF_COMMON_NAME:-grafana}
GF_EMAIL=${GF_EMAIL:-gxbrooks@gmail.com}

echo "/C=$GF_COUNTRY/ST=$GF_STATE/L=$GF_LOCALITY/O=$GF_ORG/OU=$GF_ORGF_UNIT/CN=$GF_COMMON_NAME/emailAddress=$GF_EMAIL"
# Silence openssl key generation progress
openssl genrsa -out "$CERTS_DIR/grafana/grafana.key" 2048 2>/dev/null
echo "[init-certs] Created Grafana private key at $CERTS_DIR/grafana/grafana.key"
openssl req -new \
  -key "$CERTS_DIR/grafana/grafana.key" \
  -subj "/C=$GF_COUNTRY/ST=$GF_STATE/L=$GF_LOCALITY/O=$GF_ORG/OU=$GF_ORGF_UNIT/CN=$GF_COMMON_NAME/emailAddress=$GF_EMAIL" \
  -out "$CERTS_DIR/grafana/grafana.csr" \
  -sha256 \
  -batch
echo "[init-certs] Created Grafana certificate signing request at $CERTS_DIR/grafana/grafana.csr"
# use Elastic Stack CA as the CA 
openssl x509 -req \
  -in "$CERTS_DIR/grafana/grafana.csr" \
  -CA "$CERTS_DIR/ca/ca.crt" \
  -CAkey "$CERTS_DIR/ca/ca.key" \
  -CAcreateserial \
  -out "$CERTS_DIR/grafana/grafana.crt" \
  -days 365 
echo "Created Grafana certificate at $CERTS_DIR/grafana/grafana.crt"

# openssl x509 -in "$CERTS_DIR/ca/ca.crt" -noout -text
# openssl x509 -in "$CERTS_DIR/grafana/grafana.crt" -noout -text
# openssl req -in "$CERTS_DIR/grafana/grafana.csr" -noout -text

# 
echo "[init-certs] Setting certificate file permissions" 
# Directories need to be readable by all
find "$CERTS_DIR" -type d -exec chmod 755 {} \;
echo "[init-certs] Set directory permissions to 755"

# Keys must be readable by owner/group but not world (Elasticsearch runs as UID 1000)
find "$CERTS_DIR" -type f -name "*.key" -exec chmod 640 {} \;
echo "[init-certs] Set key permissions to 640 (owner:rw group:r world:none)"

# Certs readable by all (public keys)
find "$CERTS_DIR" -type f -name "*.crt" -exec chmod 644 {} \;
echo "[init-certs] Set certificate permissions to 644"

# CSR files can be more permissive
find "$CERTS_DIR" -type f -name "*.csr" -exec chmod 644 {} \;

# Remove world-writable permissions from all files (safety)
find "$CERTS_DIR" -type f -exec chmod o-w {} \;

touch "$CERTS_DIR/done"
chmod 644 "$CERTS_DIR/done"

echo "[init-certs] init-certs done!!!"
echo "[init-certs] Make sure to run ansible-playbook to distribute the CA cert to other nodes if needed."
exit 0
