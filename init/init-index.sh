#!/usr/bin/bash

# tests

# good format 
# curl --no-progress-meter -X PUT "https://es01:9200/_index_template/spark-template" --cacert config/certs/ca/ca.crt -u "elastic:${ELASTIC_PASSWORD}" -H "Content-Type: application/json" -d "@init/cannot-merge-a-non-object-mapping-with-an-object-mapping.json"

# In spark the depth of the query plans can exceed the index default limit of 20 levels. 
# The sparkUnproccessedIndexTemplate.json file assumes the namespace of the index and the dataset are both
# named 'spark'. These names are specified in the logstash.conf file. 
#
echo "Creating Index Template"
curl --no-progress-meter \
  --request PUT "https://es01:9200/_index_template/spark-logs"\
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -H "Content-Type: application/json"\
  -d '@init/sparkActiveIndexTemplate.json'
result=$?
echo -e "\nResult is $result"
if [ $result -ne 0 ]; then
    echo "Error: curl failed with code $?" >&2
    exit $result
  fi

