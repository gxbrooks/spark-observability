#!/usr/bin/bash

# tests

# good format 
# curl --no-progress-meter -X PUT "https://es01:9200/_index_template/spark-template" --cacert config/certs/ca/ca.crt -u "elastic:${ELASTIC_PASSWORD}" -H "Content-Type: application/json" -d "@elasticsearch/cannot-merge-a-non-object-mapping-with-an-object-mapping.json"

# this is the Spark on Elastic utility bin director and not Elasticsearch's bin directory
PATH="/usr/share/elasticsearch/elasticsearch/bin:${PATH}"

echo "Waiting for Elasticsearch availability";
# This readiness test was from the original 
until curl --no-progress-meter --cacert config/certs/ca/ca.crt https://es01:9200 | grep -q "missing authentication credentials"; do sleep 30; done;

# In spark the depth of the query plans can exceed the index default limit of 20 levels. 
# The sparkUnproccessedIndexTemplate.json file assumes the namespace of the index and the dataset are both
# named 'spark'. These names are specified in the logstash.conf file. 

rapi PUT /_ilm/policy/batch-active elasticsearch/batch-active/batch-active.ilm.json > elasticsearch/outputs/batch-active.ilm.out.json
rapi PUT /_index_template/batch-active-index elasticsearch/batch-active/batch-active-index.template.json > elasticsearch/outputs/batch-active.template.out.json
rapi PUT /batch-active-index-000001 elasticsearch/batch-active/batch-active-index.index.json > elasticsearch/outputs/batch-active.index.out.json


rapi PUT /_ilm/policy/spark-logs elasticsearch/spark/spark-logs.ilm.json
rapi PUT /_index_template/logs-spark-spark elasticsearch/spark/logs-spark-spark.template.json

rapi PUT /_ilm/policy/data-pipeline elasticsearch/data-pipeline/data-pipeline.ilm.json
rapi PUT /_index_template/data-pipeline-ds elasticsearch/data-pipeline/data-pipeline-ds.template.json

# Need full license to run watchers
rapi POST /_license/start_trial?acknowledge=true

# enable watcher to match start and end events and publish batch objects
# there are two algorithms: a mustache-expansion based and a join based algorithms
# only one can be active at time.

#rapi PUT /_watcher/watch/batch-match-mustache elasticsearch/batch-active/match-mustache.watcher.json
rapi PUT /_watcher/watch/batch-match-join elasticsearch/batch-active/match-join.watcher.json


# Hold on deletions until we can figure out why some end events are not matched
#rapi PUT /_watcher/watch/delete-matched elasticsearch/batch-active/delete-matched.watcher.json

# batch metrics
rapi PUT /_index_template/batch-metrics-ds elasticsearch/batch-metrics/batch-metrics.template.json
rapi PUT /_data_stream/batch-metrics-ds
rapi PUT /_watcher/watch/batch-metrics elasticsearch/batch-metrics/batch-metrics.watcher.json

