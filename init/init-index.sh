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
  --request PUT "https://es01:9200/_index_template/batch-active-index"\
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -H "Content-Type: application/json"\
  -d '@init/batch-active-index.template.json'
status=$?
echo -e "\nstatus is $status"
if [ $status -ne 0 ]; then
    echo "Error: curl failed with code $?" >&2
    exit $status
  fi

echo "PUT _index_template/logs-spark-spark init/logs-spark-spark.template.json"
curl --no-progress-meter \
  --request PUT "https://es01:9200/_index_template/logs-spark-spark"\
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -H "Content-Type: application/json"\
  -d '@init/logs-spark-spark.template.json'
status=$?
echo -e "\nstatus is $status"
if [ $status -ne 0 ]; then
    echo "Error: curl failed with code $?" >&2
    exit $status
  fi

echo "api PUT _index_template/spark-log-ds init/data-pipeline-ds.template.json"
curl --no-progress-meter \
  --request PUT "https://es01:9200/_index_template/data-pipeline-ds"\
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -H "Content-Type: application/json"\
  -d '@init/data-pipeline-ds.template.json'
status=$?
echo -e "\nstatus is $status"
if [ $status -ne 0 ]; then
    echo "Error: curl failed with code $?" >&2
    exit $status
  fi

echo "POST _license/start_trial?acknowledge=true"
curl --no-progress-meter \
  --request POST "https://es01:9200/_license/start_trial?acknowledge=true"\
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -H "Content-Type: application/json"
status=$?
echo -e "\nstatus is $status"
if [ $status -ne 0 ]; then
    echo "Error: curl failed with code $?" >&2
    exit $status
  fi


# Need full license to run watchers
init/bin/rapi.sh POST _license/start_trial?acknowledge=true

# init/bin/rapi.sh PUT _ingest/pipeline/spark-pipeline init/spark-pipeline.json

# init/bin/rapi.sh PUT _watcher/watch/spark_batch_watcher init/spark.batch_info.watcher.json
