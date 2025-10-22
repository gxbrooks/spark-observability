#!/usr/bin/bash

# Create all the private keys and public certificates needed for Spark Observability. 

# Elasticsearch's Xpack requires that any Xpack attribute configurations are rooted
# at /usr/share/elasticsearch/config. 

# This file needs to run as root

# The elasticsearch certificate utility (elasticsearch-certutil) creates a zip file bsed
# on the ./certs/instances.yml file with the following structure:
#
#     certs
#     ├── ca
#     │   ├── ca.crt
#     │   ├── ca.key
#     │   └── ca.srl
#     ├── certs.zip
#     ├── es01
#     │   ├── es01.crt
#     │   └── es01.key
#     └── kibana
#         ├── kibana.crt
#         └── kibana.key
#
# Docker certificate best practices place the certificates in a directory that is mounted as a volume:
#
# /etc/ssl/
# ├── private/         # 700 permissions
#     ├── server.key   # 600 permissions  
# │   └── ca.key       # 600 permissions
# └── certs/           # 755 permissions
#     ├── server.crt   # 644 permissions
#     ├── ca.crt       # 644 permissions
#     └── chain.crt    # 644 permissions
#
# This represents a significant impedence mispatch with the way that the Elastic Stack expects 
# certificates to be stored. To handle
# host-level instlalations of Elastic Agent we will copy out just the Elasticsearch certficates
# to /etc/ssl. Also, we will store the whole Elasticsearch certs directory in /etc/ss/private, to 
# be used by Elasticsearch in its native structure. 
# 
# ----------------------| ------------------------------------ | --------------------------------------|
#  Service              | Host Mount Point                     |  ContainerMount Point                 | 
# ----------------------| ------------------------------------ | --------------------------------------|
#  init-cert            | certs:                               | /usr/share/elasticsearch/config/certs |     
#  init-cert            | /etc/ssl/certs/elastic               | /etc/ssl/certs/elastic                |
#  elasticsearch        | certs:                               | /usr/share/elasticsearch/config/certs |
#  kibana               | /mnt/c/Volumes/certs/Elastic         | /etc/ssl/certs/elastic                |
#  init-kibana          | /mnt/c/Volumes/certs/Elastic         | /etc/ssl/certs/elastic                |
#  init-kibana-password | /mnt/c/Volumes/certs/Elastic         | /etc/ssl/certs/elastic                |
#  init-index           | /mnt/c/Volumes/certs/Elastic         | /etc/ssl/certs/elastic                |
#  logstash             | /mnt/c/Volumes/certs/Elastic         | /etc/ssl/certs/elastic                |
# ----------------------| ------------------------------------ | --------------------------------------|

# Container directory structure for certificates
#
# /usr/share/elasticsearch/config/certs
#  ├── ca
#  ├── certs.zip
#  ├── es01
#  ├── kibana
#  └── grafana     

# /etc/ssl/certs/elastic 
# └── certs/
#     └── elastic
#         └── ca.crt


# exit the script immediately if any command fails
set -e

# Parse arguments for --force
FORCE=0
for arg in "$@"; do
  if [[ "$arg" == "--force" ]]; then
    FORCE=1
  fi
done

# Follows the Linux convention of storing the CA certs in /etc/ssl/public
# $CA_CERT is where the public version of the CA cert is stored
# it is passed into the environment by the docker-compose.yml file
if [ ! -v CA_CERT ] ; then
  echo "CA_CERT ('$CA_CERT') not defined in the environment"
  exit 1
fi

mkdir -p $(dirname "$CA_CERT")

# Follows the Elasticsearch convention (mandate) of storing the CA certs in 
# /usr/share/elasticsearch/config
CA_BASE_DIR="/usr/share/elasticsearch/config" 
CERTS_DIR="$CA_BASE_DIR/certs"
CA_CERT_DIR="$CERTS_DIR/ca"
CA_CERT_PATH="$CA_CERT_DIR/ca.crt"
CA_KEY_PATH="$CA_CERT_DIR/ca.key"
CA_VERSION_FILE="$CA_CERT_DIR/.certs_version"


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
# Copy CA cert for distribution
cp "$CA_CERT_PATH" "$CA_CERT"
chmod 644 "$CA_CERT_PATH"
echo "[init-certs] CA cert distributed to $CA_CERT"
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