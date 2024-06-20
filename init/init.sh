#!/usr/bin/bash


if [ x${ELASTIC_PASSWORD} == x ]; then
  echo "Set the ELASTIC_PASSWORD environment variable in the .env file"; 
  exit 1; 
fi;

if [ x${KIBANA_PASSWORD} == x ]; then 
  echo "Set the KIBANA_PASSWORD environment variable in the .env file"; 
  exit 1; 
fi;

echo "Waiting for Elasticsearch availability";
# until curl -s --cacert config/certs/ca/ca.crt https://es01:9200; do sleep 30; done;
until curl --no-progress-meter --cacert config/certs/ca/ca.crt https://es01:9200 | grep -q "missing authentication credentials"; do sleep 30; done;

echo "Setting kibana_system password";
# until curl -s -X POST --cacert config/certs/ca/ca.crt -u "elastic:${ELASTIC_PASSWORD}" -H "Content-Type: application/json" https://es01:9200/_security/user/kibana_system/_password -d "{\"password\":\"${KIBANA_PASSWORD}\"}" | grep -q "^{}"; do sleep 10; done;
until curl --no-progress-meter -X POST --cacert config/certs/ca/ca.crt -u "elastic:${ELASTIC_PASSWORD}" -H "Content-Type: application/json" https://es01:9200/_security/user/kibana_system/_password -d "{\"password\":\"${KIBANA_PASSWORD}\"}" | grep -q "^{}"; do sleep 10; done;

echo "Initialization all done!";


