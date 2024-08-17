#!/usr/bin/bash

# Elasticsearch API initializations are based of "Getting started with the Elastic Stack and Docker Compose: Part 1"
# See https://www.elastic.co/blog/getting-started-with-the-elastic-stack-and-docker-compose
#
# Instead of initializing Elasticsearch via th setup Docker service, we build an image with the equisite certficates. 
# This allows partial building of data streams required to avoide errors in the dynamic mappings resulting 
# from a poorly structured JSON schema for Spark events.
#


# Kibana availability is enforced via depenencies in the docker-compose file.

# the dataview output is too voliminous so we redirect to files
init/bin/kapi.sh POST /api/data_views/data_view init/batch-active/batch-active.dataview.json \
  > init/outputs/batch-active.dataview.out.json
init/bin/kapi.sh POST /api/data_views/data_view init/spark/spark-logs.dataview.json \
  > init/outputs/spark-logs.dataview.out.json
init/bin/kapi.sh POST /api/data_views/data_view init/data-pipeline/data-pipeline-ds.dataview.json \
  > init/outputs/data-pipeline.dataview.out.json
  

  