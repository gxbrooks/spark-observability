#!/usr/bin/bash

# This file runs as root

# exit the script immediately if any command fails
set -e

# start clean
rm -rf ./config/certs/ca ./config/certs/es01 ./config/certs/kibana ./config/certs/init ./config/certs/grafana ./config/certs/certs.zip ./config/certs/ca.zip

echo "Creating Elastic Stack keys"
mkdir ./config/certs/ca

echo "Creating CA"
elasticsearch-certutil ca --silent \
  --pem \
  --out ./config/certs/ca.zip

unzip ./config/certs/ca.zip -d ./config/certs
	
echo "Creating Elastic certs"
# what is init for (now) in instance.yml?
elasticsearch-certutil cert --silent \
  --pem \
  --out ./config/certs/certs.zip \
  --in ./config/certs/instances.yml \
  --ca-cert ./config/certs/ca/ca.crt \
  --ca-key ./config/certs/ca/ca.key 
unzip ./config/certs/certs.zip -d ./config/certs

echo "Creating Grafana key"
mkdir ./config/certs/grafana

GF_COUNTRY=${GF_COUNTRY:-US}
GF_STATE=${GF_STATE:-TX}
GF_LOCALITY=${GF_LOCALITY:-Frisco}
GF_ORG=${GF_ORG:-Self}
GF_ORGF_UNIT=${GF_ORGF_UNIT:-Self}
GF_COMMON_NAME=${GF_COMMON_NAME:-grafana}
GF_EMAIL=${GF_EMAIL:-gxbrooks@gmail.com}

echo "/C=$GF_COUNTRY/ST=$GF_STATE/L=$GF_LOCALITY/O=$GF_ORG/OU=$GF_ORGF_UNIT/CN=$GF_COMMON_NAME/emailAddress=$GF_EMAIL"
openssl genrsa -out ./config/certs/grafana/grafana.key 2048
openssl req -new \
  -key ./config/certs/grafana/grafana.key \
  -subj "/C=$GF_COUNTRY/ST=$GF_STATE/L=$GF_LOCALITY/O=$GF_ORG/OU=$GF_ORGF_UNIT/CN=$GF_COMMON_NAME/emailAddress=$GF_EMAIL" \
  -out ./config/certs/grafana/grafana.csr

# openssl x509 -req \
  # -days 365 \
  # -in ./config/certs/grafana/grafana.csr \
  # -signkey ./config/certs/grafana/grafana.key \
  # -out ./config/certs/grafana/grafana.crt

# use Elastic Stack CA as the CA 
openssl x509 -req \
  -in ./config/certs/grafana/grafana.csr \
  -CA ./config/certs/ca/ca.crt \
  -CAkey ./config/certs/ca/ca.key \
  -CAcreateserial \
  -out ./config/certs/grafana/grafana.crt \
  -days 365 

# openssl x509 -in ./config/certs/ca/ca.crt -noout -text
# openssl x509 -in ./config/certs/grafana/grafana.crt -noout -text
# openssl req -in ./config/certs/grafana/grafana.csr -noout -text

echo "Setting file permissions" 
chown -R root:root ./config/certs
# Keys need to be kept private, but certificates need to be public
# directories need to be readable by all
find ./config/certs -type d -exec chmod a+rx {} \;
# Keys must be private
find ./config/certs -type f -name \*.key -exec chmod o-rwx,u=rw,g=r {} \;
# As well as the zip files in which they appear
find ./config/certs -type f -name \*.zip -exec chmod o-rwx,u=rw,g=r {} \;
# Make certs readable by all
find ./config/certs -type f -name \*.crt -exec chmod a+r {} \;
# For testing open up all files
find ./config/certs -type f -exec chmod a+wr {} \;

echo "init-certs done!!!" 
