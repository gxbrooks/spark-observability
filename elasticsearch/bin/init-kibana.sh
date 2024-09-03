#!/usr/bin/bash

# Elasticsearch API initializations are based of "Getting started with the Elastic Stack and Docker Compose: Part 1"
# See https://www.elastic.co/blog/getting-started-with-the-elastic-stack-and-docker-compose
#


# this is the Spark on Elastic utility bin director and not Elasticsearch's bin directory
PATH="/usr/share/elasticsearch/elasticsearch/bin:${PATH}"

# Kibana availability is enforced via depenencies in the docker-compose file.

# the dataview output is too voliminous so we redirect to files

kapi POST /api/data_views/data_view elasticsearch/spark/spark-logs.dataview.json \
  > elasticsearch/outputs/spark-logs.dataview.out.json

# Enable watcher dataview
kapi POST /api/data_views/data_view elasticsearch/batch-active/watcher.dataview.json \
  > elasticsearch/outputs/watcher.dataview.out.json
kapi POST /api/saved_objects/search/batch-active-watcher-runs?overwrite=true elasticsearch/batch-active/batch-active-watcher.search.json

# List out the batch start and end events that still exist
kapi POST /api/data_views/data_view elasticsearch/batch-active/batch-active.dataview.json \
  > elasticsearch/outputs/batch-active.dataview.out.json
kapi POST /api/saved_objects/search/batch-active-events?overwrite=true elasticsearch/batch-active/batch-active-events.search.json
  
# show the count of different types of batch jobs at different points in time
kapi POST /api/data_views/data_view elasticsearch/batch-metrics/batch-metrics.dataview.json \
  > elasticsearch/outputs/batch-metrics.dataview.out.json  
kapi POST /api/saved_objects/search/batch-active-counts?overwrite=true elasticsearch/batch-metrics/batch-counts.search.json

# view the completed batch jobs in the data-pipeline datastream
kapi POST /api/data_views/data_view elasticsearch/data-pipeline/data-pipeline-ds.dataview.json \
  > elasticsearch/outputs/data-pipeline.dataview.out.json
kapi POST /api/saved_objects/search/completed-batch-jobs?overwrite=true elasticsearch/data-pipeline/data-pipeline-completed-jobs.search.json






  