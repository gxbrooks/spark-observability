#!/usr/bin/bash

# Elasticsearch API initializations are based of "Getting started with the Elastic Stack and Docker Compose: Part 1"
# See https://www.elastic.co/blog/getting-started-with-the-elastic-stack-and-docker-compose

# exit the script immediately if any command fails
set -e

# Add current directory to PATH for esapi script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="${PATH}:${SCRIPT_DIR}"

if [[ ! -v CA_CERT || ! -f "$CA_CERT" ]]; then
  echo "CA_CERT='$CA_CERT' not in the environment or not a file"
  exit 1
fi

echo "Waiting for Elasticsearch availability"
# Wait for Elasticsearch to be ready
MAX_RETRIES=20
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Health check attempt $((RETRY_COUNT + 1))/$MAX_RETRIES"
  if esapi GET / > /dev/null 2>&1; then
    echo "✅ Elasticsearch is available and accepting authenticated requests"
    break
  else
    echo "⏳ Elasticsearch not ready yet, waiting 5 seconds..."
    sleep 5
    RETRY_COUNT=$((RETRY_COUNT + 1))
  fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "❌ Elasticsearch health check failed after $MAX_RETRIES attempts"
  exit 1
fi

# Outputs directory should be created by ansible playbook with correct ownership
# Create it here as fallback if running manually
mkdir -p /usr/share/elasticsearch/elasticsearch/outputs 2>/dev/null || true

# In spark the depth of the query plans can exceed the index default limit of 20 levels. 
# The sparkUnproccessedIndexTemplate.json file assumes the namespace of the index and the dataset are both
# named 'spark'. These names are specified in the logstash.conf file. 

esapi PUT /_ilm/policy/batch-events elasticsearch/batch-events/batch-events.ilm.json > /usr/share/elasticsearch/elasticsearch/outputs/batch-events.ilm.out.json 
esapi PUT /_index_template/batch-events elasticsearch/batch-events/batch-events.template.json > /usr/share/elasticsearch/elasticsearch/outputs/batch-events.template.out.json 
# if the index already exists, don't create it or elastic will error out
! esapi GET /batch-events-000001 >& /dev/null \
  && esapi  PUT /batch-events-000001 elasticsearch/batch-events/batch-events.index.json > /usr/share/elasticsearch/elasticsearch/outputs/batch-events.index.out.json 


esapi PUT /_ilm/policy/spark-logs elasticsearch/spark/spark-logs.ilm.json 
esapi PUT /_index_template/logs-spark-spark elasticsearch/spark/logs-spark-spark.template.json 

esapi PUT /_ilm/policy/batch-traces elasticsearch/batch-traces/batch-traces.ilm.json 
esapi PUT /_index_template/batch-traces elasticsearch/batch-traces/batch-traces.template.json 

# Need full license to run watchers
# No error on license update as it fails if the license is already enabled. 
# TODO: test for license before updating it.
# don't fail if the licnese has already been updated
esapi POST /_license/start_trial?acknowledge=true || true

# enable watcher to match start and end events and publish batch objects
# there are two algorithms: a mustache-expansion based and a join based algorithms
# only one can be active at time.

#esapi PUT /_watcher/watch/batch-match-mustache elasticsearch/batch-events/match-mustache.watcher.json
esapi PUT /_watcher/watch/batch-match-join elasticsearch/batch-events/match-join.watcher.json 


# Hold on deletions until we can figure out why some end events are not matched
#esapi PUT /_watcher/watch/delete-matched elasticsearch/batch-events/delete-matched.watcher.json

# batch metrics
esapi PUT /_index_template/batch-metrics-ds elasticsearch/batch-metrics/batch-metrics.template.json 
# if the index already exists, don't create it or elastic will error out
! esapi GET /_data_stream/batch-metrics-ds >& /dev/null \
  && esapi PUT /_data_stream/batch-metrics-ds
esapi PUT /_watcher/watch/batch-metrics elasticsearch/batch-metrics/batch-metrics.watcher.json 

# Spark gc logs
esapi PUT /_ilm/policy/spark-gc elasticsearch/spark-gc/spark-gc.ilm.json > /usr/share/elasticsearch/elasticsearch/outputs/spark-gc.ilm.out.json 
esapi PUT /_index_template/spark-gc-ds elasticsearch/spark-gc/spark-gc.template.json 
# Spark GC ingest pipeline for parsing GC log fields
esapi PUT /_ingest/pipeline/logs-spark_gc-default elasticsearch/spark-gc/spark-gc-ingest-pipeline.json > /usr/share/elasticsearch/elasticsearch/outputs/spark-gc-ingest-pipeline.out.json

# OpenTelemetry traces
esapi PUT /_ilm/policy/otel-traces elasticsearch/otel-traces/otel-traces.ilm-policy.json > /usr/share/elasticsearch/elasticsearch/outputs/otel-traces.ilm.out.json 
esapi PUT /_index_template/otel-traces elasticsearch/otel-traces/otel-traces.template.json > /usr/share/elasticsearch/elasticsearch/outputs/otel-traces.template.out.json


