#!/usr/bin/bash

# tests

# good format 
# curl --no-progress-meter -X PUT "https://es01:9200/_index_template/spark-template" --cacert config/certs/ca/ca.crt -u "elastic:${ELASTIC_PASSWORD}" -H "Content-Type: application/json" -d "@init/cannot-merge-a-non-object-mapping-with-an-object-mapping.json"

<<Comment
echo "Creating Index Template"
curl --no-progress-meter \
  --request PUT "https://es01:9200/_index_template/spark"\
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -H "Content-Type: application/json" \
  -d "@init/Accumulables-mapping.json"
result = $?
echo -e "\nResult is $result"
if [ $result -ne 0 ]; then
    echo "Error: curl failed with code $?" >&2
    exit $result
  fi

echo "Creating Data Stream Template"
curl --no-progress-meter \
  --request PUT "https://es01:9200/_data_stream/logs-spark-spark"\
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -H "Content-Type: application/json" 
result = $?
echo -e "\nResult is $result"
if [ $result -ne 0 ]; then
    echo "Error: curl failed with code $?" >&2
    exit $result
  fi
Comment

echo -n No initialization for now