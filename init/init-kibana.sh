#!/usr/bin/bash

# Elasticsearch API initializations are based of "Getting started with the Elastic Stack and Docker Compose: Part 1"
# See https://www.elastic.co/blog/getting-started-with-the-elastic-stack-and-docker-compose
#
# Instead of initializing Elasticsearch via th setup Docker service, we build an image with the equisite certficates. 
# This allows partial building of data streams required to avoide errors in the dynamic mappings resulting 
# from a poorly structured JSON schema for Spark events.
#

if [ x${ELASTIC_PASSWORD} == x ]; then
  echo "Set the ELASTIC_PASSWORD environment variable in the .env file"; 
  exit 1; 
fi;

if [ x${KIBANA_PASSWORD} == x ]; then 
  echo "Set the KIBANA_PASSWORD environment variable in the .env file"; 
  exit 1; 
fi;

echo "Waiting for Elasticsearch availability";
# This readiness test was from the original 
until curl --no-progress-meter --cacert config/certs/ca/ca.crt https://es01:9200 | grep -q "missing authentication credentials"; do sleep 30; done;

echo "Setting kibana_system password"
until curl --no-progress-meter -X POST --cacert config/certs/ca/ca.crt -u "elastic:${ELASTIC_PASSWORD}" -H "Content-Type: application/json" https://es01:9200/_security/user/kibana_system/_password -d "{\"password\":\"${KIBANA_PASSWORD}\"}" | grep -q "^{}"; do sleep 10; done;

echo "Security initialization all done!"
