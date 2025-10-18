#!/usr/bin/bash

# Kibana API initializations are based of "Getting started with the Elastic Stack and Docker Compose: Part 1"
# See https://www.elastic.co/blog/getting-started-with-the-elastic-stack-and-docker-compose
#
# exit the script immediately if any command fails
set -e

echo "=== INIT-KIBANA DIAGNOSTICS ==="
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo "User: $(whoami)"
echo "Working Directory: $(pwd)"
echo "Environment Variables:"
echo "  KIBANA_HOST: ${KIBANA_HOST:-NOT_SET}"
echo "  KIBANA_PORT: ${KIBANA_PORT:-NOT_SET}"
echo "  KIBANA_PASSWORD: ${KIBANA_PASSWORD:-NOT_SET}"
echo "  ELASTIC_USER: ${ELASTIC_USER:-NOT_SET}"
echo "  CA_CERT: ${CA_CERT:-NOT_SET}"
echo "================================="

if [ ! -v CA_CERT ] || [ ! -f "$CA_CERT" ]; then
  echo "CA_CERT not in environmen or not a file"
  exit 1
fi

# this is the Spark on Elastic utility bin directory
PATH="${PATH}:/opt/shared/bin"

# Test Kibana health before proceeding
echo "=== TESTING KIBANA HEALTH ==="
KIBANA_URL="http://${KIBANA_HOST}:${KIBANA_PORT}"
echo "Testing Kibana at: $KIBANA_URL"

# Wait for Kibana to be ready with retries
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Health check attempt $((RETRY_COUNT + 1))/$MAX_RETRIES"
  if curl -k -s -u "${ELASTIC_USER}:${KIBANA_PASSWORD}" "$KIBANA_URL/api/status" > /dev/null 2>&1; then
    echo "✅ Kibana is healthy and ready"
    break
  else
    echo "⏳ Kibana not ready yet, waiting 2 seconds..."
    sleep 2
    RETRY_COUNT=$((RETRY_COUNT + 1))
  fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "❌ Kibana health check failed after $MAX_RETRIES attempts"
  exit 1
fi

# Test basic API connectivity
echo "=== TESTING KIBANA API CONNECTIVITY ==="
curl -k -s -u "${ELASTIC_USER}:${KIBANA_PASSWORD}" "$KIBANA_URL/api/status" | head -5
echo ""

# Create a simple test data view first
echo "=== CREATING TEST DATA VIEW ==="
TEST_JSON='{"override": true, "refresh_fields": true, "data_view": {"title": "test-debug-*", "id": "test-debug", "name": "Test Debug View", "allowNoIndex": true}}'
echo "Test JSON: $TEST_JSON"

# Create test data view
curl -k -s -u "${ELASTIC_USER}:${KIBANA_PASSWORD}" -X POST "$KIBANA_URL/api/data_views/data_view" \
  -H "Content-Type: application/json" \
  -H "kbn-xsrf: true" \
  -d "$TEST_JSON" > /tmp/test-dataview-response.json

echo "Test data view creation response:"
cat /tmp/test-dataview-response.json
echo ""

# Verify test data view was created
echo "=== VERIFYING TEST DATA VIEW ==="
curl -k -s -u "${ELASTIC_USER}:${KIBANA_PASSWORD}" "$KIBANA_URL/api/data_views" > /tmp/current-dataviews.json
echo "Current data views:"
cat /tmp/current-dataviews.json
echo ""

# Check if our test view exists
if grep -q "test-debug" /tmp/current-dataviews.json; then
  echo "✅ Test data view created successfully"
else
  echo "❌ Test data view was not created or not found"
fi

echo "=== STARTING MAIN DATA VIEW CREATION ==="

# The dataview output is too voliminous in some cases so we redirect to files.
# this also helps facilitate debugging

# wW force failed API calls to error out under the principle of "fail fast"
# Failed initializations can take an inordinate amount of time to detect downstream of the error

echo "=== CREATING SPARK LOGS DATA VIEW ==="
kapi POST /api/data_views/data_view elasticsearch/spark/spark-logs.dataview.json \
  > elasticsearch/outputs/spark-logs.dataview.out.json 
echo "Spark logs data view creation completed. Checking current data views..."
curl -k -s -u "${ELASTIC_USER}:${KIBANA_PASSWORD}" "$KIBANA_URL/api/data_views" | jq '.data_view | length' || echo "Failed to get data view count"

# Enable watcher dataview
echo "=== CREATING WATCHER DATA VIEW ==="
kapi POST /api/data_views/data_view elasticsearch/batch-events/watcher.dataview.json \
  > elasticsearch/outputs/watcher.dataview.out.json  
echo "Watcher data view creation completed. Checking current data views..."
curl -k -s -u "${ELASTIC_USER}:${KIBANA_PASSWORD}" "$KIBANA_URL/api/data_views" | jq '.data_view | length' || echo "Failed to get data view count"

kapi POST /api/saved_objects/search/match-mustache-watcher-runs?overwrite=true elasticsearch/batch-events/match-mustache.watcher-runs.search.json 
kapi POST /api/saved_objects/search/match-join-watcher-runs?overwrite=true \
  elasticsearch/batch-events/match-join.watcher-runs.search.json 

# List out the batch start and end events that still exist
echo "=== CREATING BATCH EVENTS DATA VIEW ==="
kapi POST /api/data_views/data_view elasticsearch/batch-events/batch-events.dataview.json \
  > elasticsearch/outputs/batch-events.dataview.out.json 
echo "Batch events data view creation completed. Checking current data views..."
curl -k -s -u "${ELASTIC_USER}:${KIBANA_PASSWORD}" "$KIBANA_URL/api/data_views" | jq '.data_view | length' || echo "Failed to get data view count"

kapi POST /api/saved_objects/search/batch-events-events?overwrite=true elasticsearch/batch-events/batch-events.search.json 
kapi POST /api/saved_objects/search/active-batches?overwrite=true elasticsearch/batch-events/active-batches.search.json 
  
# show the count of different types of batch jobs at different points in time
echo "=== CREATING BATCH METRICS DATA VIEW ==="
kapi POST /api/data_views/data_view elasticsearch/batch-metrics/batch-metrics.dataview.json \
  > elasticsearch/outputs/batch-metrics.dataview.out.json 
echo "Batch metrics data view creation completed. Checking current data views..."
curl -k -s -u "${ELASTIC_USER}:${KIBANA_PASSWORD}" "$KIBANA_URL/api/data_views" | jq '.data_view | length' || echo "Failed to get data view count"

kapi POST /api/saved_objects/search/batch-events-counts?overwrite=true \
  elasticsearch/batch-metrics/batch-counts.search.json 

# view the completed batch jobs in the batch-traces datastream
echo "=== CREATING BATCH TRACES DATA VIEW ==="
kapi POST /api/data_views/data_view elasticsearch/batch-traces/batch-traces.dataview.json \
  > elasticsearch/outputs/batch-traces.dataview.out.json 
echo "Batch traces data view creation completed. Checking current data views..."
curl -k -s -u "${ELASTIC_USER}:${KIBANA_PASSWORD}" "$KIBANA_URL/api/data_views" | jq '.data_view | length' || echo "Failed to get data view count"

kapi POST /api/saved_objects/search/completed-batch-jobs?overwrite=true \
  elasticsearch/batch-traces/batch-traces.search.json

# Spark GC views
echo "=== CREATING SPARK GC DATA VIEW ==="
kapi POST /api/data_views/data_view elasticsearch/spark-gc/spark-gc.dataview.json \
  > elasticsearch/outputs/spark-gc.dataview.out.json 
echo "Spark GC data view creation completed. Checking current data views..."
curl -k -s -u "${ELASTIC_USER}:${KIBANA_PASSWORD}" "$KIBANA_URL/api/data_views" | jq '.data_view | length' || echo "Failed to get data view count"

# strict dynamic mapping is preventing filter string in search.
#   "filters": [{"query": {"match_phrase": {"gc.stats": "paused"}}}],
kapi POST /api/saved_objects/search/spark-gc-search?overwrite=true elasticsearch/spark-gc/spark-gc.search.json \
    > elasticsearch/outputs/spark-gc.search.out.json

# OpenTelemetry traces views
echo "=== CREATING OTEL TRACES DATA VIEW ==="
kapi POST /api/data_views/data_view elasticsearch/otel-traces/otel-traces.dataview.json \
  > elasticsearch/outputs/otel-traces.dataview.out.json 
echo "OTel traces data view creation completed. Checking current data views..."
curl -k -s -u "${ELASTIC_USER}:${KIBANA_PASSWORD}" "$KIBANA_URL/api/data_views" | jq '.data_view | length' || echo "Failed to get data view count"

echo "=== FINAL DATA VIEW VERIFICATION ==="
echo "All data view creation completed. Final verification:"
curl -k -s -u "${ELASTIC_USER}:${KIBANA_PASSWORD}" "$KIBANA_URL/api/data_views" > /tmp/final-dataviews.json
echo "Final data views count:"
cat /tmp/final-dataviews.json | jq '.data_view | length' || echo "Failed to get final count"
echo "Final data views list:"
cat /tmp/final-dataviews.json | jq '.data_view[] | {id: .id, title: .title, name: .name}' || echo "Failed to get data view details"







  