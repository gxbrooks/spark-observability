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
# certificates to be stored. For Docker Swarm we will need to move to Docker secrets. To handle
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
CA_DIST_DIR="/etc/ssl/certs/elastic" 
mkdir -p "$CA_DIST_DIR"
# Follows the Elasticsearch convention (mandate) of storing the CA certs in 
# /usr/share/elasticsearch/config
CA_BASE_DIR="/usr/share/elasticsearch/config" 
CERTS_DIR="$CA_BASE_DIR/certs"
CA_CERT_DIR="$CERTS_DIR/ca"
CA_CERT="$CERTS_DIR/ca/ca.crt"
CA_VERSION_FILE="$CERTS_DIR/.certs_version"


# Helper: get CA cert hash
get_ca_hash() {
  if [ -f "$CA_CERT_DIR/ca.crt" ]; then
    sha256sum "$CA_CERT_DIR/ca.crt" | awk '{print $1}'
  else
    echo ""
  fi
}

# check if the script has already run, unless --force is given
if [ -f "$CERTS_DIR/done" ] && [ $FORCE -eq 0 ]; then
  echo "[init-certs] init-certs has already run successfully, exiting"
  exit 0
# --Force forces regeneration
elif [ $FORCE -eq 1 ]; then
  echo "[init-certs] Force regeneration of certificates."
# Must regenerate if there is no private key or no version
elif [ ! -f "$CA_CERT_DIR/ca.crt" ] || [ ! -f "$CA_VERSION_FILE" ]; then
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
# Clean old certs (idempotent)
rm -rf "$CERTS_DIR"/*
# add other service dirs as needed
mkdir -p "$CERTS_DIR/ca" # "$CERTS_DIR/es01" "$CERTS_DIR/logstash01" 
chmod -R 755 "$CERTS_DIR/ca"
echo "[init-certs] Creating self-signed certificat authority (CA)"
# elasticsearch-certutil ca --silent \
#   --pem \
#   --out "$CERTS_DIR/ca.zip
# Generate CA
openssl req -x509 -newkey rsa:4096 \
  -days 3650 -nodes \
  -keyout "$CA_CERT_DIR/ca.key" \
  -out "$CA_CERT_DIR/ca.crt" \
  -subj "/CN=Elastic-Stack-CA"
chmod 600 "$CA_CERT_DIR/ca.key" 
chmod 644 "$CA_CERT_DIR/ca.crt" 
# Save CA cert hash as version marker
get_ca_hash > "$CA_VERSION_FILE"
chmod 644 "$CA_VERSION_FILE"
# Copy CA cert for distribution
mkdir -p "$CA_DIST_DIR"
cp "$CA_CERT_DIR/ca.crt" "$CA_DIST_DIR/ca.crt"
chmod 644 "$CA_DIST_DIR/ca.crt"
echo "[init-certs] CA cert distributed to $CA_DIST_DIR"
# Optionally trigger Ansible playbook for CA cert distribution
if [ -n "${TRIGGER_ANSIBLE:-}" ]; then
  echo "[init-certs] Triggering Ansible playbook for CA cert distribution..."
  ansible-playbook /path/to/distribute_ca_cert.yml || echo "[init-certs] Ansible playbook failed or not configured."
fi


echo "[init-certs] Creating Elastic certs"
# what is init for (now) in instance.yml?
# Remove any existing certs zip to avoid errors
rm -f "$CERTS_DIR/certs.zip"

elasticsearch-certutil cert --silent \
  --pem \
  --out "$CERTS_DIR/certs.zip" \
  --in ./certs/instances.yml \
  --ca-cert "$CERTS_DIR/ca/ca.crt" \
  --ca-key "$CERTS_DIR/ca/ca.key" 
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
echo "[init-certs] Created Grafana certificate signing request (CSR) at $CERTS_DIR/grafana/grafana.csr"
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
# chown -R root:root "$CERTS_DIR"
# Keys need to be kept private, but certificates need to be public
# directories need to be readable by all
find "$CERTS_DIR" -type d -exec chmod 755 {} \;
echo "S[init-certs] et directory permissions to 755"
# Keys must be private (read/write for owner only)
find "$CERTS_DIR" -type f -name "*.key" -exec chmod 644 {} \;
echo "[init-certs] Set key permissions to 600"
# Certs readable by all
find "$CERTS_DIR" -type f -name "*.crt" -exec chmod 644 {} \;
echo "[init-certs] Set certificate permissions to 644"

# Remove world-writable permissions from all files (undo previous a+wr for testing)
find "$CERTS_DIR" -type f -exec chmod o-w,g-w {} \;

touch "$CERTS_DIR/done"
chmod 644 "$CERTS_DIR/done"

echo "[init-certs] init-certs done!!!"
echo "[init-certs] Make sure to run ansible-playbook to distribute the CA cert to other nodes if needed."
exit 0