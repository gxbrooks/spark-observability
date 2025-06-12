#!/usr/bin/bash

# Elasticsearch API initializations are based of "Getting started with the Elastic Stack and Docker Compose: Part 1"
# See https://www.elastic.co/blog/getting-started-with-the-elastic-stack-and-docker-compose
#

# Need to update Kibana password via Elastisearch
if [ x${CA_CERT} == x ] || [ x${ELASTIC_HOST} == x ] || [ x${ELASTIC_PASSWORD} == x ] || [ x${ELASTIC_PORT} == x ] || [ x${ELASTIC_USER} == x ] || [ x${KIBANA_PASSWORD} == x ]; then
  echo "One or more required environment variables are not set"; 
  exit 1; 
fi;

if [[ ! -v CA_CERT ]]; then
  echo "CA_CERT not set in environment"
  exit 1
fi

echo "Waiting for Elasticsearch availability";
# This readiness test was from the original 
until curl --no-progress-meter --cacert ${CA_CERT} https://${ELASTIC_HOST}:${ELASTIC_PORT} | grep -q "missing authentication credentials"; do sleep 30; done;

echo "Setting kibana_system password"
until curl --no-progress-meter -X POST --cacert ${CA_CERT} -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" -H "Content-Type: application/json" https://${ELASTIC_HOST}:${ELASTIC_PORT}/_security/user/kibana_system/_password -d "{\"password\":\"${KIBANA_PASSWORD}\"}" | grep -q "^{}"; do sleep 10; done;
status=$?

echo "kibana_system password updated. Status = $status"
