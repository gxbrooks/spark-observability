#!/usr/bin/bash

# This files runs as root
set -x
# start clean
rm -rf ./certs/ca ./certs/es01 ./certs/kibana ./certs/init ./certs/grafana ./certs/certs.zip ./certs/ca.zip

echo "Creating Elastic Stack keys"
mkdir ./certs/ca
ls -lR ./certs

echo "Creating CA"
./bin/elasticsearch-certutil ca --silent \
  --pem \
  --out ./certs/ca.zip

ls -lR ./certs

unzip ./certs/ca.zip -d ./certs
	
echo "Creating Elastic certs"
# what is init for (now) in instance.yml?
./bin/elasticsearch-certutil cert --silent \
  --pem \
  --out ./certs/certs.zip \
  --in ./certs/instances.yml \
  --ca-cert ./certs/ca/ca.crt \
  --ca-key ./certs/ca/ca.key
unzip ./certs/certs.zip -d ./certs

echo "Creating Grafana key"
mkdir ./certs/grafana

GF_COUNTRY=${GF_COUNTRY:-US}
GF_STATE=${GF_STATE:-TX}
GF_LOCALITY=${GF_LOCALITY:-Frisco}
GF_ORG=${GF_ORG:-Self}
GF_ORGF_UNIT=${GF_ORGF_UNIT:-Self}
GF_COMMON_NAME=${GF_COMMON_NAME:-grafana}
GF_EMAIL=${GF_EMAIL:-gxbrooks@gmail.com}

echo "/C=$GF_COUNTRY/ST=$GF_STATE/L=$GF_LOCALITY/O=$GF_ORG/OU=$GF_ORGF_UNIT/CN=$GF_COMMON_NAME/emailAddress=$GF_EMAIL"
openssl genrsa -out ./certs/grafana/grafana.key 2048
openssl req -new \
  -key ./certs/grafana/grafana.key \
  -subj "/C=$GF_COUNTRY/ST=$GF_STATE/L=$GF_LOCALITY/O=$GF_ORG/OU=$GF_ORGF_UNIT/CN=$GF_COMMON_NAME/emailAddress=$GF_EMAIL" \
  -out ./certs/grafana/grafana.csr

# openssl x509 -req \
  # -days 365 \
  # -in ./certs/grafana/grafana.csr \
  # -signkey ./certs/grafana/grafana.key \
  # -out ./certs/grafana/grafana.crt

# use Elastic Stack CA as the CA 
openssl x509 -req \
  -in ./certs/grafana/grafana.csr \
  -CA ./certs/ca/ca.crt \
  -CAkey ./certs/ca/ca.key \
  -CAcreateserial \
  -out ./certs/grafana/grafana.crt \
  -days 365

# openssl x509 -in ./certs/ca/ca.crt -noout -text
# openssl x509 -in ./certs/grafana/grafana.crt -noout -text
# openssl req -in ./certs/grafana/grafana.csr -noout -text

echo "Setting file permissions" 
chown -R root:root certs
# Keys need to be kept private, but certificates need to be public
# directories need to be readable by all
find ./certs -type d -exec chmod a+rx {} \;
# Keys must be private
find ./certs -type f -name \*.key -exec chmod o-rwx,u=rw,g=r {} \;
# As well as the zip files in which they appear
find ./certs -type f -name \*.zip -exec chmod o-rwx,u=rw,g=r {} \;
# Make certs readable by all
find ./certs -type f -name \*.crt -exec chmod a+r {} \;
# For testing open up all files
find ./certs -type f -exec chmod a+wr {} \;
