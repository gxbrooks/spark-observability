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
#     ├── ca.zip
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
#  init-cert            | /etc/ssl/private/elastic             | /etc/ssl/private/elastic              |     
#  init-cert            | /etc/ssl/certs/elastic               | /etc/ssl/certs/elastic                |
#  elasticsearch        | /etc/ssl/private/elasticsearch       | /usr/share/elasticsearch/config/certs |
#  kibana               | /etc/ssl/certs/elastic               | /etc/ssl/certs/elastic                |
#  init-kibana          | /etc/ssl/certs/elastic               | /etc/ssl/certs/elastic                |
#  init-kibana-password | /etc/ssl/certs/elastic               | /etc/ssl/certs/elastic                |
#  init-index           | /etc/ssl/certs/elastic               | /etc/ssl/certs/elastic                |
#  logstash             | /etc/ssl/certs/elastic               | /etc/ssl/certs/elastic                |
# ----------------------| ------------------------------------ | --------------------------------------|

# host directory structure for certificates
#
# /etc/ssl/
# ├── private/
# │   └── elastic
# │       └── certs/ # original strcture
# │           ├── ca
# │           ├── ca.zip
# │           ├── certs.zip
# │           ├── es01
# │           ├── kibana
# │           └── grafana     
# └── certs/
#     └── elastic
#         └── ca.crt

# exit the script immediately if any command fails
set -e

# check if the script has already run
if [ -f /etc/ssl/private/elastic/done ]; then
  echo "init-certs has already run, exiting"
  exit 0
fi

echo "Creating Elastic Stack keys"
mkdir -p /etc/ssl/private/elastic/certs
mkdir /etc/ssl/private/elastic/certs/ca

echo "Creating self-signed certificat authority (CA)"
elasticsearch-certutil ca --silent \
  --pem \
  --out /etc/ssl/private/elastic/certs/ca.zip

unzip /etc/ssl/private/elastic/certs/ca.zip -d /etc/ssl/private/elastic/certs
# copy out ca.cert for Elastic Agent on the host
cp /etc/ssl/private/elastic/certs/ca/ca.crt /etc/ssl/certs/elastic/ca.crt
chmod 644 /etc/ssl/certs/elastic/ca.crt
	
echo "Creating Elastic certs"
# what is init for (now) in instance.yml?
elasticsearch-certutil cert --silent \
  --pem \
  --out /etc/ssl/private/elastic/certs/certs.zip \
  --in ./certs/instances.yml \
  --ca-cert /etc/ssl/private/elastic/certs/ca/ca.crt \
  --ca-key /etc/ssl/private/elastic/certs/ca/ca.key 
unzip /etc/ssl/private/elastic/certs/certs.zip -d /etc/ssl/private/elastic/certs


echo "Creating Grafana key"
mkdir -p /etc/ssl/private/elastic/certs/grafana

GF_COUNTRY=${GF_COUNTRY:-US}
GF_STATE=${GF_STATE:-TX}
GF_LOCALITY=${GF_LOCALITY:-Frisco}
GF_ORG=${GF_ORG:-Self}
GF_ORGF_UNIT=${GF_ORGF_UNIT:-Self}
GF_COMMON_NAME=${GF_COMMON_NAME:-grafana}
GF_EMAIL=${GF_EMAIL:-gxbrooks@gmail.com}

echo "/C=$GF_COUNTRY/ST=$GF_STATE/L=$GF_LOCALITY/O=$GF_ORG/OU=$GF_ORGF_UNIT/CN=$GF_COMMON_NAME/emailAddress=$GF_EMAIL"
openssl genrsa -out /etc/ssl/private/elastic/certs/grafana/grafana.key 2048
openssl req -new \
  -key /etc/ssl/private/elastic/certs/grafana/grafana.key \
  -subj "/C=$GF_COUNTRY/ST=$GF_STATE/L=$GF_LOCALITY/O=$GF_ORG/OU=$GF_ORGF_UNIT/CN=$GF_COMMON_NAME/emailAddress=$GF_EMAIL" \
  -out /etc/ssl/private/elastic/certs/grafana/grafana.csr

# openssl x509 -req \
  # -days 365 \
  # -in /etc/ssl/private/elastic/certs/grafana/grafana.csr \
  # -signkey /etc/ssl/private/elastic/certs/grafana/grafana.key \
  # -out /etc/ssl/private/elastic/certs/grafana/grafana.crt

# use Elastic Stack CA as the CA 
openssl x509 -req \
  -in /etc/ssl/private/elastic/certs/grafana/grafana.csr \
  -CA /etc/ssl/private/elastic/certs/ca/ca.crt \
  -CAkey /etc/ssl/private/elastic/certs/ca/ca.key \
  -CAcreateserial \
  -out /etc/ssl/private/elastic/certs/grafana/grafana.crt \
  -days 365 

# openssl x509 -in /etc/ssl/private/elastic/certs/ca/ca.crt -noout -text
# openssl x509 -in /etc/ssl/private/elastic/certs/grafana/grafana.crt -noout -text
# openssl req -in /etc/ssl/private/elastic/certs/grafana/grafana.csr -noout -text

echo "Setting file permissions" 
chown -R root:root /etc/ssl/private/elastic/certs
# Keys need to be kept private, but certificates need to be public
# directories need to be readable by all
find /etc/ssl/private/elastic/certs -type d -exec chmod a+rx {} \;
# Keys must be private
find /etc/ssl/private/elastic/certs -type f -name \*.key -exec chmod o-rwx,u=rw,g=r {} \;
# As well as the zip files in which they appear
find /etc/ssl/private/elastic/certs -type f -name \*.zip -exec chmod o-rwx,u=rw,g=r {} \;
# Make certs readable by all
find /etc/ssl/private/elastic/certs -type f -name \*.crt -exec chmod a+r {} \;
# For testing open up all files
find /etc/ssl/private/elastic/certs -type f -exec chmod a+wr {} \;

touch /etc/ssl/private/elastic/done
chmod 644 /etc/ssl/private/elastic/done


echo "init-certs done!!!" 
