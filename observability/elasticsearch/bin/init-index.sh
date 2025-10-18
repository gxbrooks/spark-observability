#!/usr/bin/bash

# Combined Elasticsearch and Kibana initialization script
# This script initializes Elasticsearch indices, ILM policies, templates, and Kibana data views
# Based on "Getting started with the Elastic Stack and Docker Compose: Part 1"
# See https://www.elastic.co/blog/getting-started-with-the-elastic-stack-and-docker-compose

# exit the script immediately if any command fails
set -e

echo "=== INIT-INDEX DIAGNOSTICS ==="
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo "User: $(whoami)"
echo "Working Directory: $(pwd)"
echo "Environment Variables:"
echo "  ELASTIC_HOST: ${ELASTIC_HOST:-NOT_SET}"
echo "  ELASTIC_PORT: ${ELASTIC_PORT:-NOT_SET}"
echo "  ELASTIC_USER: ${ELASTIC_USER:-NOT_SET}"
echo "  KIBANA_HOST: ${KIBANA_HOST:-NOT_SET}"
echo "  KIBANA_PORT: ${KIBANA_PORT:-NOT_SET}"
echo "  CA_CERT: ${CA_CERT:-NOT_SET}"
echo "================================="

# Add current directory to PATH for esapi/kapi scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="${PATH}:${SCRIPT_DIR}"

# Verify required environment variables
if [[ ! -v CA_CERT || ! -f "$CA_CERT" ]]; then
  echo "❌ CA_CERT='$CA_CERT' not in the environment or not a file"
  exit 1
fi

if [[ -z "${ELASTIC_HOST}" || -z "${ELASTIC_PASSWORD}" || -z "${ELASTIC_PORT}" || -z "${ELASTIC_USER}" || -z "${KIBANA_PASSWORD}" ]]; then
  echo "❌ One or more required environment variables are not set"
  echo "Required: ELASTIC_HOST, ELASTIC_PASSWORD, ELASTIC_PORT, ELASTIC_USER, KIBANA_PASSWORD"
  exit 1
fi

# ============================================================================
# STEP 1: Wait for Elasticsearch availability
# ============================================================================
echo ""
echo "=== STEP 1: WAITING FOR ELASTICSEARCH AVAILABILITY ==="
MAX_RETRIES=20
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Elasticsearch health check attempt $((RETRY_COUNT + 1))/$MAX_RETRIES"
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

# ============================================================================
# STEP 2: Set Kibana system password
# ============================================================================
echo ""
echo "=== STEP 2: SETTING KIBANA SYSTEM PASSWORD ==="
echo "Setting kibana_system password..."

# Create JSON payload for password update
PASSWORD_JSON=$(mktemp)
cat > "$PASSWORD_JSON" <<EOF
{
  "password": "${KIBANA_PASSWORD}"
}
EOF

# Set the kibana_system password
MAX_RETRIES=10
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Password update attempt $((RETRY_COUNT + 1))/$MAX_RETRIES"
  if esapi POST /_security/user/kibana_system/_password "$PASSWORD_JSON" > /dev/null 2>&1; then
    echo "✅ kibana_system password updated successfully"
    rm -f "$PASSWORD_JSON"
    break
  else
    echo "⏳ Password update not ready, waiting 5 seconds..."
    sleep 5
    RETRY_COUNT=$((RETRY_COUNT + 1))
  fi
done

rm -f "$PASSWORD_JSON"

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "❌ Failed to set kibana_system password after $MAX_RETRIES attempts"
  exit 1
fi

# ============================================================================
# STEP 3: Wait for Kibana availability
# ============================================================================
echo ""
echo "=== STEP 3: WAITING FOR KIBANA AVAILABILITY ==="
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Kibana health check attempt $((RETRY_COUNT + 1))/$MAX_RETRIES"
  if kapi GET /api/status > /dev/null 2>&1; then
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

# ============================================================================
# STEP 4: Create outputs directory
# ============================================================================
echo ""
echo "=== STEP 4: PREPARING OUTPUT DIRECTORIES ==="
# Outputs directory should be created by ansible playbook with correct ownership
# Create it here as fallback if running manually
mkdir -p /usr/share/elasticsearch/elasticsearch/outputs 2>/dev/null || true
echo "✅ Output directories ready"

# ============================================================================
# STEP 5: Start Elasticsearch Trial License
# ============================================================================
echo ""
echo "=== STEP 5: ENABLING ELASTICSEARCH TRIAL LICENSE ==="
# Need full license to run watchers
# Check current license status first
LICENSE_STATUS=$(mktemp)
if esapi GET /_license > "$LICENSE_STATUS" 2>&1; then
  # Check if trial or higher license is already active
  if grep -q '"type".*:.*"trial"' "$LICENSE_STATUS" || \
     grep -q '"type".*:.*"platinum"' "$LICENSE_STATUS" || \
     grep -q '"type".*:.*"enterprise"' "$LICENSE_STATUS" || \
     grep -q '"type".*:.*"gold"' "$LICENSE_STATUS"; then
    echo "✅ License already active (trial or higher)"
  else
    # Basic license - try to start trial
    echo "Starting trial license..."
    if esapi POST /_license/start_trial?acknowledge=true > /dev/null 2>&1; then
      echo "✅ Trial license enabled successfully"
    else
      echo "⚠️  Trial license could not be enabled (may have already been used)"
    fi
  fi
else
  echo "⚠️  Could not check license status"
fi
rm -f "$LICENSE_STATUS"

# ============================================================================
# STEP 6: Initialize Batch Events (Index, ILM, Watchers, Data Views)
# ============================================================================
echo ""
echo "=== STEP 6: INITIALIZING BATCH EVENTS ==="

echo "Creating batch-events ILM policy..."
esapi PUT /_ilm/policy/batch-events elasticsearch/batch-events/batch-events.ilm.json \
  > /usr/share/elasticsearch/elasticsearch/outputs/batch-events.ilm.out.json

echo "Creating batch-events index template..."
esapi PUT /_index_template/batch-events elasticsearch/batch-events/batch-events.template.json \
  > /usr/share/elasticsearch/elasticsearch/outputs/batch-events.template.out.json

echo "Creating batch-events-000001 index if it doesn't exist..."
if ! esapi GET /batch-events-000001 >& /dev/null; then
  esapi PUT /batch-events-000001 elasticsearch/batch-events/batch-events.index.json \
    > /usr/share/elasticsearch/elasticsearch/outputs/batch-events.index.out.json
else
  echo "  (index already exists, skipping)"
fi

echo "Creating batch-match-join watcher..."
esapi PUT /_watcher/watch/batch-match-join elasticsearch/batch-events/match-join.watcher.json \
  > /dev/null 2>&1

echo "Creating batch-events data view..."
kapi POST /api/data_views/data_view elasticsearch/batch-events/batch-events.dataview.json \
  > /usr/share/elasticsearch/elasticsearch/outputs/batch-events.dataview.out.json

echo "Creating batch-events searches..."
kapi POST /api/saved_objects/search/batch-events-events?overwrite=true \
  elasticsearch/batch-events/batch-events.search.json > /dev/null 2>&1
kapi POST /api/saved_objects/search/active-batches?overwrite=true \
  elasticsearch/batch-events/active-batches.search.json > /dev/null 2>&1

echo "✅ Batch events initialized"

# ============================================================================
# STEP 7: Initialize Watcher Data View
# ============================================================================
echo ""
echo "=== STEP 7: INITIALIZING WATCHER DATA VIEW ==="

echo "Creating watcher data view..."
kapi POST /api/data_views/data_view elasticsearch/batch-events/watcher.dataview.json \
  > /usr/share/elasticsearch/elasticsearch/outputs/watcher.dataview.out.json

echo "Creating watcher searches..."
kapi POST /api/saved_objects/search/match-mustache-watcher-runs?overwrite=true \
  elasticsearch/batch-events/match-mustache.watcher-runs.search.json > /dev/null 2>&1
kapi POST /api/saved_objects/search/match-join-watcher-runs?overwrite=true \
  elasticsearch/batch-events/match-join.watcher-runs.search.json > /dev/null 2>&1

echo "✅ Watcher data view initialized"

# ============================================================================
# STEP 8: Initialize Spark Logs (ILM, Templates, Data Views)
# ============================================================================
echo ""
echo "=== STEP 8: INITIALIZING SPARK LOGS ==="

echo "Creating spark-logs ILM policy..."
esapi PUT /_ilm/policy/spark-logs elasticsearch/spark/spark-logs.ilm.json \
  > /dev/null 2>&1

echo "Creating logs-spark-spark index template..."
esapi PUT /_index_template/logs-spark-spark elasticsearch/spark/logs-spark-spark.template.json \
  > /dev/null 2>&1

echo "Creating spark-logs data view..."
kapi POST /api/data_views/data_view elasticsearch/spark/spark-logs.dataview.json \
  > /usr/share/elasticsearch/elasticsearch/outputs/spark-logs.dataview.out.json

echo "✅ Spark logs initialized"

# ============================================================================
# STEP 9: Initialize Batch Traces (ILM, Templates, Data Views)
# ============================================================================
echo ""
echo "=== STEP 9: INITIALIZING BATCH TRACES ==="

echo "Creating batch-traces ILM policy..."
esapi PUT /_ilm/policy/batch-traces elasticsearch/batch-traces/batch-traces.ilm.json \
  > /dev/null 2>&1

echo "Creating batch-traces index template..."
esapi PUT /_index_template/batch-traces elasticsearch/batch-traces/batch-traces.template.json \
  > /dev/null 2>&1

echo "Creating batch-traces data view..."
kapi POST /api/data_views/data_view elasticsearch/batch-traces/batch-traces.dataview.json \
  > /usr/share/elasticsearch/elasticsearch/outputs/batch-traces.dataview.out.json

echo "Creating batch-traces searches..."
kapi POST /api/saved_objects/search/completed-batch-jobs?overwrite=true \
  elasticsearch/batch-traces/batch-traces.search.json > /dev/null 2>&1

echo "✅ Batch traces initialized"

# ============================================================================
# STEP 10: Initialize Batch Metrics (Templates, Data Streams, Watchers, Data Views)
# ============================================================================
echo ""
echo "=== STEP 10: INITIALIZING BATCH METRICS ==="

echo "Creating batch-metrics index template..."
esapi PUT /_index_template/batch-metrics-ds elasticsearch/batch-metrics/batch-metrics.template.json \
  > /dev/null 2>&1

echo "Creating batch-metrics data stream if it doesn't exist..."
if ! esapi GET /_data_stream/batch-metrics-ds >& /dev/null; then
  esapi PUT /_data_stream/batch-metrics-ds > /dev/null 2>&1
else
  echo "  (data stream already exists, skipping)"
fi

echo "Creating batch-metrics watcher..."
esapi PUT /_watcher/watch/batch-metrics elasticsearch/batch-metrics/batch-metrics.watcher.json \
  > /dev/null 2>&1

echo "Creating batch-metrics data view..."
kapi POST /api/data_views/data_view elasticsearch/batch-metrics/batch-metrics.dataview.json \
  > /usr/share/elasticsearch/elasticsearch/outputs/batch-metrics.dataview.out.json

echo "Creating batch-metrics searches..."
kapi POST /api/saved_objects/search/batch-events-counts?overwrite=true \
  elasticsearch/batch-metrics/batch-counts.search.json > /dev/null 2>&1

echo "✅ Batch metrics initialized"

# ============================================================================
# STEP 11: Initialize Spark GC (ILM, Templates, Ingest Pipelines, Data Views)
# ============================================================================
echo ""
echo "=== STEP 11: INITIALIZING SPARK GC ==="

echo "Creating spark-gc ILM policy..."
esapi PUT /_ilm/policy/spark-gc elasticsearch/spark-gc/spark-gc.ilm.json \
  > /usr/share/elasticsearch/elasticsearch/outputs/spark-gc.ilm.out.json

echo "Creating spark-gc index template..."
esapi PUT /_index_template/spark-gc-ds elasticsearch/spark-gc/spark-gc.template.json \
  > /dev/null 2>&1

echo "Creating spark-gc ingest pipeline..."
esapi PUT /_ingest/pipeline/logs-spark_gc-default elasticsearch/spark-gc/spark-gc-ingest-pipeline.json \
  > /usr/share/elasticsearch/elasticsearch/outputs/spark-gc-ingest-pipeline.out.json

echo "Creating spark-gc data view..."
kapi POST /api/data_views/data_view elasticsearch/spark-gc/spark-gc.dataview.json \
  > /usr/share/elasticsearch/elasticsearch/outputs/spark-gc.dataview.out.json

echo "Creating spark-gc searches..."
kapi POST /api/saved_objects/search/spark-gc-search?overwrite=true \
  elasticsearch/spark-gc/spark-gc.search.json \
  > /usr/share/elasticsearch/elasticsearch/outputs/spark-gc.search.out.json

echo "✅ Spark GC initialized"

# ============================================================================
# STEP 12: Initialize OpenTelemetry Traces (ILM, Templates, Data Views)
# ============================================================================
echo ""
echo "=== STEP 12: INITIALIZING OPENTELEMETRY TRACES ==="

echo "Creating otel-traces ILM policy..."
esapi PUT /_ilm/policy/otel-traces elasticsearch/otel-traces/otel-traces.ilm-policy.json \
  > /usr/share/elasticsearch/elasticsearch/outputs/otel-traces.ilm.out.json

echo "Creating otel-traces index template..."
esapi PUT /_index_template/otel-traces elasticsearch/otel-traces/otel-traces.template.json \
  > /usr/share/elasticsearch/elasticsearch/outputs/otel-traces.template.out.json

echo "Creating otel-traces data view..."
kapi POST /api/data_views/data_view elasticsearch/otel-traces/otel-traces.dataview.json \
  > /usr/share/elasticsearch/elasticsearch/outputs/otel-traces.dataview.out.json

echo "✅ OpenTelemetry traces initialized"

# ============================================================================
# COMPLETION
# ============================================================================
echo ""
echo "========================================"
echo "✅ ALL INITIALIZATIONS COMPLETE"
echo "========================================"
echo ""
echo "Summary:"
echo "  - Elasticsearch: Available and configured"
echo "  - Kibana: Available with password set"
echo "  - ILM Policies: Created for all indices"
echo "  - Index Templates: Created for all indices"
echo "  - Watchers: Configured for batch events and metrics"
echo "  - Data Views: Created for all data sources"
echo "  - Searches: Created for all data views"
echo ""
echo "Next steps:"
echo "  1. Verify services at https://\${ELASTIC_HOST}:9200 and http://\${KIBANA_HOST}:5601"
echo "  2. Check Kibana data views in Stack Management"
echo "  3. Start sending data from Spark applications"
echo ""
