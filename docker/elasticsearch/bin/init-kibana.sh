#!/usr/bin/bash

# Kibana API initializations are based of "Getting started with the Elastic Stack and Docker Compose: Part 1"
# See https://www.elastic.co/blog/getting-started-with-the-elastic-stack-and-docker-compose
#
# exit the script immediately if any command fails
set -e

if [ [ ! -v CA_CERT ] || [! -f $CA_CERT] ]; then
  echo "CA_CERT not in environmen or not a file"
  exit 1
fi

# this is the Spark on Elastic utility bin directory
PATH="${PATH}:/opt/shared/bin"

# Kibana availability is enforced via depenencies in the docker-compose file.

# The dataview output is too voliminous in some cases so we redirect to files.
# this also helps facilitate debugging

# wW force failed API calls to error out under the principle of "fail fast"
# Failed initializations can take an inordinate amount of time to detect downstream of the error

kapi POST /api/data_views/data_view elasticsearch/spark/spark-logs.dataview.json \
  > elasticsearch/outputs/spark-logs.dataview.out.json 

# Enable watcher dataview
kapi POST /api/data_views/data_view elasticsearch/batch-events/watcher.dataview.json \
  > elasticsearch/outputs/watcher.dataview.out.json  
kapi POST /api/saved_objects/search/match-mustache-watcher-runs?overwrite=true elasticsearch/batch-events/match-mustache.watcher-runs.search.json 
kapi POST /api/saved_objects/search/match-join-watcher-runs?overwrite=true \
  elasticsearch/batch-events/match-join.watcher-runs.search.json 


# List out the batch start and end events that still exist
kapi POST /api/data_views/data_view elasticsearch/batch-events/batch-events.dataview.json \
  > elasticsearch/outputs/batch-events.dataview.out.json 
kapi POST /api/saved_objects/search/batch-events-events?overwrite=true elasticsearch/batch-events/batch-events.search.json 
kapi POST /api/saved_objects/search/active-batches?overwrite=true elasticsearch/batch-events/active-batches.search.json 
  
# show the count of different types of batch jobs at different points in time
kapi POST /api/data_views/data_view elasticsearch/batch-metrics/batch-metrics.dataview.json \
  > elasticsearch/outputs/batch-metrics.dataview.out.json 
kapi POST /api/saved_objects/search/batch-events-counts?overwrite=true \
  elasticsearch/batch-metrics/batch-counts.search.json 

# view the completed batch jobs in the batch-traces datastream
kapi POST /api/data_views/data_view elasticsearch/batch-traces/batch-traces.dataview.json \
  > elasticsearch/outputs/batch-traces.dataview.out.json 
kapi POST /api/saved_objects/search/completed-batch-jobs?overwrite=true \
  elasticsearch/batch-traces/batch-traces.search.json

# Spark GC views
kapi POST /api/data_views/data_view elasticsearch/spark-gc/spark-gc.dataview.json \
  > elasticsearch/outputs/spark-gc.dataview.out.json 
# strict dynamic mapping is preventing filter string in search.
#   "filters": [{"query": {"match_phrase": {"gc.stats": "paused"}}}],
kapi POST /api/saved_objects/search/spark-gc-search?overwrite=true elasticsearch/spark-gc/spark-gc.search.json \
    > elasticsearch/outputs/spark-gc.search.out.json







  