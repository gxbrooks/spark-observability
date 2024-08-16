#!/usr/bin/bash

# tests

# good format 
# curl --no-progress-meter -X PUT "https://es01:9200/_index_template/spark-template" --cacert config/certs/ca/ca.crt -u "elastic:${ELASTIC_PASSWORD}" -H "Content-Type: application/json" -d "@init/cannot-merge-a-non-object-mapping-with-an-object-mapping.json"

echo "Waiting for Elasticsearch availability";
# This readiness test was from the original 
until curl --no-progress-meter --cacert config/certs/ca/ca.crt https://es01:9200 | grep -q "missing authentication credentials"; do sleep 30; done;

# In spark the depth of the query plans can exceed the index default limit of 20 levels. 
# The sparkUnproccessedIndexTemplate.json file assumes the namespace of the index and the dataset are both
# named 'spark'. These names are specified in the logstash.conf file. 

init/bin/rapi.sh PUT _ilm/policy/batch-active init/batch-active/batch-active.ilm.json
init/bin/rapi.sh PUT _index_template/batch-active-index init/batch-active/batch-active-index.template.json
init/bin/rapi.sh PUT batch-active-index-000001 init/batch-active/batch-active-index.index.json


init/bin/rapi.sh PUT _ilm/policy/spark-logs init/spark/spark-logs.ilm.json
init/bin/rapi.sh PUT _index_template/logs-spark-spark init/spark/logs-spark-spark.template.json

init/bin/rapi.sh PUT _ilm/policy/data-pipeline init/data-pipeline/data-pipeline.ilm.json
init/bin/rapi.sh PUT _index_template/data-pipeline-ds init/data-pipeline/data-pipeline-ds.template.json

# Need full license to run watchers
init/bin/rapi.sh POST _license/start_trial?acknowledge=true

init/bin/rapi.sh PUT _watcher/watch/batch-match init/batch-active/match.watcher.json 
init/bin/rapi.sh PUT _watcher/watch/delete-matched init/batch-active/delete-matched.watcher.json

# init/bin/rapi.sh PUT _ingest/pipeline/spark-pipeline init/spark-pipeline.json

# init/bin/rapi.sh PUT _watcher/watch/spark_batch_watcher init/spark.match.watcher.json
