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
echo "  ES_DIR: ${ES_DIR}"
echo "  ES_CONFIG_DIR: ${ES_CONFIG_DIR}"
echo "  ES_OUTPUTS_DIR: ${ES_OUTPUTS_DIR}"
echo "  ES_BIN_DIR: ${ES_BIN_DIR}"
echo "  ES_HOST: ${ES_HOST}"
echo "  ES_PORT: ${ES_PORT}"
echo "  ES_USER: ${ES_USER}"
echo "  ES_PASSWORD: ${ES_PASSWORD}"
echo "  CA_CERT: ${CA_CERT}"
echo "  KB_HOST: ${KB_HOST}"
echo "  KB_PORT: ${KB_PORT}"
echo "  KB_PASSWORD: ${KB_PASSWORD}"
echo "================================="

# Export ES_* variables for developer use (can be copy/pasted into shell)
# Standardized naming: ES_* for Elasticsearch (ES already stands for Elasticsearch)
# All variables must be provided via .env from vars/variables.yaml (fail-fast, no defaults)
export ES_DIR="${ES_DIR}"
export ES_CONFIG_DIR="${ES_CONFIG_DIR}"
export ES_OUTPUTS_DIR="${ES_OUTPUTS_DIR}"
export ES_BIN_DIR="${ES_BIN_DIR}"
export CA_CERT="${CA_CERT}"
export ES_HOST="${ES_HOST}"
export ES_PORT="${ES_PORT}"
export ES_USER="${ES_USER}"
export ES_PASSWORD="${ES_PASSWORD}"
export KB_HOST="${KB_HOST}"
export KB_PORT="${KB_PORT}"
export KB_PASSWORD="${KB_PASSWORD}"

echo ""
echo "=== PATH CONFIGURATION ==="
echo "ES_DIR: ${ES_DIR}"
echo "ES_CONFIG_DIR: ${ES_CONFIG_DIR}"
echo "ES_OUTPUTS_DIR: ${ES_OUTPUTS_DIR}"
echo "ES_BIN_DIR: ${ES_BIN_DIR}"
echo "================================="
echo ""
echo "=== ES_* ENVIRONMENT VARIABLES (for developer use) ==="
echo "Copy/paste these into your shell to use esapi/kapi commands:"
echo "export ES_DIR=\"${ES_DIR}\""
echo "export ES_CONFIG_DIR=\"${ES_CONFIG_DIR}\""
echo "export ES_OUTPUTS_DIR=\"${ES_OUTPUTS_DIR}\""
echo "export ES_BIN_DIR=\"${ES_BIN_DIR}\""
echo "export CA_CERT=\"${CA_CERT}\""
echo "export ES_HOST=\"${ES_HOST}\""
echo "export ES_PORT=\"${ES_PORT}\""
echo "export ES_USER=\"${ES_USER}\""
echo "export ES_PASSWORD=\"${ES_PASSWORD}\""
echo "export KB_HOST=\"${KB_HOST}\""
echo "export KB_PORT=\"${KB_PORT}\""
echo "export KB_PASSWORD=\"${KB_PASSWORD}\""
echo "export PATH=\"\${PATH}:${ES_BIN_DIR}\""
echo "================================="

# Add bin directory to PATH for esapi/kapi scripts
PATH="${PATH}:${ES_BIN_DIR}"

# Change to elasticsearch directory so relative paths work
cd "${ES_DIR}"

# Verify required environment variables (fail-fast: all must be provided via .env from vars/variables.yaml)
REQUIRED_VARS=(
  "ES_DIR"
  "ES_CONFIG_DIR"
  "ES_OUTPUTS_DIR"
  "ES_BIN_DIR"
  "CA_CERT"
  "ES_HOST"
  "ES_PORT"
  "ES_USER"
  "ES_PASSWORD"
  "KB_HOST"
  "KB_PORT"
  "KB_PASSWORD"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var}" ]]; then
    MISSING_VARS+=("$var")
  fi
done

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
  echo "❌ Fatal error: Required environment variables not set (must be provided via .env from vars/variables.yaml):"
  printf "   %s\n" "${MISSING_VARS[@]}"
  echo ""
  echo "This is a fail-fast check. All variables must be explicitly defined in vars/variables.yaml"
  echo "and passed through the .env file. No default values are allowed."
  exit 1
fi

# Verify CA_CERT file exists
if [[ ! -f "$CA_CERT" ]]; then
  echo "❌ Fatal error: CA_CERT='$CA_CERT' is not a file or does not exist"
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
  if esapi --noauth GET / > /dev/null 2>&1; then
    echo "✅ Elasticsearch is available and responding"
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
# STEP 2: Wait for Kibana availability
# ============================================================================
echo ""
echo "=== STEP 2: WAITING FOR KIBANA AVAILABILITY ==="
MAX_RETRIES=60
KIBANA_RETRY_DELAY=5
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Kibana health check attempt $((RETRY_COUNT + 1))/$MAX_RETRIES"
  if kapi --noauth GET /api/status > /dev/null 2>&1; then
    echo "✅ Kibana is available and responding"
    break
  else
    echo "⏳ Kibana not ready yet, waiting ${KIBANA_RETRY_DELAY} seconds..."
    sleep ${KIBANA_RETRY_DELAY}
    RETRY_COUNT=$((RETRY_COUNT + 1))
  fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "❌ Kibana health check failed after $MAX_RETRIES attempts"
  exit 1
fi

# ============================================================================
# STEP 3: Create outputs directory
# ============================================================================
echo ""
echo "=== STEP 3: PREPARING OUTPUT DIRECTORIES ==="
# Outputs directory should be created by ansible playbook with correct ownership
# Create it here as fallback if running manually
mkdir -p "${ES_OUTPUTS_DIR}" 2>/dev/null || true
echo "✅ Output directories ready"

# ============================================================================
# STEP 4: Start Elasticsearch Trial License
# ============================================================================
echo ""
echo "=== STEP 4: ENABLING ELASTICSEARCH TRIAL LICENSE ==="
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
      echo "⚠️  Trial license could not be enabled (may have already been enable"
    fi
  fi
else
  echo "⚠️  Could not check license status"
fi
rm -f "$LICENSE_STATUS"

# ============================================================================
# STEP 5: Initialize Batch Events (Index, ILM, Watchers, Data Views)
# ============================================================================
echo ""
echo "=== STEP 5: INITIALIZING BATCH EVENTS ==="

echo "Creating batch-events ILM policy..."
esapi PUT /_ilm/policy/batch-events ${ES_CONFIG_DIR}/batch-events/batch-events.ilm.json \
  > ${ES_OUTPUTS_DIR}/batch-events.ilm.out.json

echo "Creating batch-events index template..."
esapi PUT /_index_template/batch-events ${ES_CONFIG_DIR}/batch-events/batch-events.template.json \
  > ${ES_OUTPUTS_DIR}/batch-events.template.out.json

echo "Creating batch-events-000001 index if it doesn't exist..."
if ! esapi GET /batch-events-000001 >& /dev/null; then
  esapi PUT /batch-events-000001 ${ES_CONFIG_DIR}/batch-events/batch-events.index.json \
    > ${ES_OUTPUTS_DIR}/batch-events.index.out.json
else
  echo "  (index already exists, skipping)"
fi

echo "Creating batch-match-join watcher..."
esapi PUT /_watcher/watch/batch-match-join ${ES_CONFIG_DIR}/batch-events/match-join.watcher.json \
  > /dev/null 2>&1

echo "Creating batch-events data view..."
kapi POST /api/data_views/data_view \
  ${ES_CONFIG_DIR}/batch-events/batch-events.dataview.json \
  > ${ES_OUTPUTS_DIR}/batch-events.dataview.out.json

echo "Creating batch-events searches..."
kapi POST /api/saved_objects/search/batch-events-events?overwrite=true \
  ${ES_CONFIG_DIR}/batch-events/batch-events.search.json > /dev/null 2>&1
kapi POST /api/saved_objects/search/active-batches?overwrite=true \
  ${ES_CONFIG_DIR}/batch-events/active-batches.search.json > /dev/null 2>&1

echo "✅ Batch events initialized"

# ============================================================================
# STEP 6: Initialize Watcher Data View
# ============================================================================
echo ""
echo "=== STEP 6: INITIALIZING WATCHER DATA VIEW ==="

echo "Creating watcher data view..."
kapi POST /api/data_views/data_view ${ES_CONFIG_DIR}/batch-events/watcher.dataview.json \
  > ${ES_OUTPUTS_DIR}/watcher.dataview.out.json

echo "Creating watcher searches..."
kapi POST /api/saved_objects/search/match-mustache-watcher-runs?overwrite=true \
  ${ES_CONFIG_DIR}/batch-events/match-mustache.watcher-runs.search.json > /dev/null 2>&1
kapi POST /api/saved_objects/search/match-join-watcher-runs?overwrite=true \
  ${ES_CONFIG_DIR}/batch-events/match-join.watcher-runs.search.json > /dev/null 2>&1

echo "✅ Watcher data view initialized"

# ============================================================================
# STEP 7: Initialize System Metrics (ILM with Downsampling)
# ============================================================================
echo ""
echo "=== STEP 7: INITIALIZING SYSTEM METRICS ==="

echo "Creating system-metrics-downsampled ILM policy..."
esapi PUT /_ilm/policy/system-metrics-downsampled ${ES_CONFIG_DIR}/system-metrics/system-metrics.ilm.json \
  > ${ES_OUTPUTS_DIR}/system-metrics-downsampled.ilm.out.json

echo "Attaching policy to existing system metrics data streams..."
for ds in metrics-system.cpu-default metrics-system.memory-default metrics-system.network-default metrics-system.diskio-default metrics-system.load-default; do
  if esapi --allow-errors GET "/_data_stream/${ds}" > /dev/null 2>&1; then
    echo "  Attaching to ${ds}..."
    esapi PUT "${ds}/_settings" -d '{"index.lifecycle.name":"system-metrics-downsampled"}' > /dev/null 2>&1 || true
  fi
done

echo "✅ System metrics initialized"

# ============================================================================
# STEP 7.8: Initialize GPU Metrics (Data Stream)
# ============================================================================
echo ""
echo "=== STEP 7.8: INITIALIZING GPU METRICS ==="

echo "Creating gpu-metrics ILM policy..."
esapi PUT /_ilm/policy/gpu-metrics ${ES_CONFIG_DIR}/gpu-metrics/gpu-metrics.ilm.json \
  > ${ES_OUTPUTS_DIR}/gpu-metrics.ilm.out.json

echo "Creating gpu-metrics index template..."
esapi PUT /_index_template/metrics-gpu-default ${ES_CONFIG_DIR}/gpu-metrics/gpu-metrics.template.json \
  > ${ES_OUTPUTS_DIR}/gpu-metrics.template.out.json

echo "Creating metrics-gpu-default data stream if it doesn't exist..."
if ! esapi GET /_data_stream/metrics-gpu-default >& /dev/null; then
  esapi PUT /_data_stream/metrics-gpu-default \
    > ${ES_OUTPUTS_DIR}/gpu-metrics.datastream.out.json 2>&1
else
  echo "  (data stream already exists, skipping)"
fi

echo "Creating gpu-metrics data view..."
kapi POST /api/data_views/data_view \
  ${ES_CONFIG_DIR}/gpu-metrics/gpu-metrics.dataview.json \
  > ${ES_OUTPUTS_DIR}/gpu-metrics.dataview.out.json

echo "Creating gpu-metrics saved search..."
kapi POST /api/saved_objects/search/gpu-metrics-default?overwrite=true \
  ${ES_CONFIG_DIR}/gpu-metrics/gpu-metrics.search.json > /dev/null 2>&1

echo "✅ GPU metrics initialized"

# ============================================================================
# STEP 7.9: Initialize Elastic Agent Logs (ILM Policy)
# ============================================================================
echo ""
echo "=== STEP 7.9: INITIALIZING ELASTIC AGENT LOGS ILM POLICY ==="

echo "Creating elastic-agent-logs ILM policy (14 days OR 1GB retention)..."
esapi PUT /_ilm/policy/elastic-agent-logs ${ES_CONFIG_DIR}/elastic-agent-logs/elastic-agent-logs.ilm.json \
  > ${ES_OUTPUTS_DIR}/elastic-agent-logs.ilm.out.json

echo "Attaching policy to existing elastic agent log data streams..."
for ds in logs-elastic_agent-default logs-elastic_agent.filebeat-default logs-elastic_agent.metricbeat-default; do
  if esapi --allow-errors GET "/_data_stream/${ds}" > /dev/null 2>&1; then
    echo "  Attaching to ${ds}..."
    esapi PUT "${ds}/_settings" -d '{"index.lifecycle.name":"elastic-agent-logs"}' > /dev/null 2>&1 || true
  fi
done

echo "✅ Elastic Agent logs ILM policy initialized"

# ============================================================================
# STEP 8: Initialize Docker Metrics (ILM with Downsampling)
# ============================================================================
echo ""
echo "=== STEP 8: INITIALIZING DOCKER METRICS ==="

echo "Creating docker-metrics-downsampled ILM policy..."
esapi PUT /_ilm/policy/docker-metrics-downsampled ${ES_CONFIG_DIR}/docker-metrics/docker-metrics.ilm.json \
  > ${ES_OUTPUTS_DIR}/docker-metrics-downsampled.ilm.out.json

echo "Attaching policy to existing docker metrics data streams..."
for ds in metrics-docker.cpu-default metrics-docker.memory-default metrics-docker.network-default; do
  if esapi --allow-errors GET "/_data_stream/${ds}" > /dev/null 2>&1; then
    echo "  Attaching to ${ds}..."
    esapi PUT "${ds}/_settings" -d '{"index.lifecycle.name":"docker-metrics-downsampled"}' > /dev/null 2>&1 || true
  fi
done

echo "✅ Docker metrics initialized"

# ============================================================================
# STEP 9: Initialize Spark Logs (ILM, Templates, Data Views)
# ============================================================================
echo ""
echo "=== STEP 9: INITIALIZING SPARK LOGS ==="

echo "Creating spark-logs ILM policy..."
esapi PUT /_ilm/policy/spark-logs ${ES_CONFIG_DIR}/spark-logs/spark-logs.ilm.json \
  > /dev/null 2>&1

echo "Creating logs-spark-default index template..."
esapi PUT /_index_template/logs-spark-default \
  ${ES_CONFIG_DIR}/spark-logs/logs-spark-default.template.json \
  > /dev/null 2>&1

echo "Creating spark-logs data view..."
kapi POST /api/data_views/data_view \
  ${ES_CONFIG_DIR}/spark-logs/spark-logs.dataview.json \
  > ${ES_OUTPUTS_DIR}/spark-logs.dataview.out.json

echo "Creating spark-logs default search..."
kapi POST /api/saved_objects/search/spark-logs-default?overwrite=true \
  ${ES_CONFIG_DIR}/spark-logs/spark-logs.search.json > /dev/null 2>&1

echo "✅ Spark logs initialized"

# ============================================================================
# STEP 10: Initialize Batch Traces (ILM, Templates, Data Views)
# ============================================================================
echo ""
echo "=== STEP 10: INITIALIZING BATCH TRACES ==="

echo "Creating batch-traces ILM policy..."
esapi PUT /_ilm/policy/batch-traces ${ES_CONFIG_DIR}/batch-traces/batch-traces.ilm.json \
  > /dev/null 2>&1

echo "Creating batch-traces index template..."
esapi PUT /_index_template/batch-traces ${ES_CONFIG_DIR}/batch-traces/batch-traces.template.json \
  > /dev/null 2>&1

echo "Creating batch-traces data view..."
kapi POST /api/data_views/data_view ${ES_CONFIG_DIR}/batch-traces/batch-traces.dataview.json \
  > ${ES_OUTPUTS_DIR}/batch-traces.dataview.out.json

echo "Creating batch-traces searches..."
kapi POST /api/saved_objects/search/completed-batch-jobs?overwrite=true \
  ${ES_CONFIG_DIR}/batch-traces/batch-traces.search.json > /dev/null 2>&1

echo "✅ Batch traces initialized"

# ============================================================================
# STEP 11: Initialize Batch Metrics (Templates, Data Streams, Watchers, Data Views)
# ============================================================================
echo ""
echo "=== STEP 11: INITIALIZING BATCH METRICS ==="

echo "Creating batch-metrics index template..."
esapi PUT /_index_template/batch-metrics-ds ${ES_CONFIG_DIR}/batch-metrics/batch-metrics.template.json \
  > /dev/null 2>&1

echo "Creating batch-metrics data stream if it doesn't exist..."
if ! esapi GET /_data_stream/batch-metrics-ds >& /dev/null; then
  esapi PUT /_data_stream/batch-metrics-ds > /dev/null 2>&1
else
  echo "  (data stream already exists, skipping)"
fi

echo "Creating batch-metrics watcher..."
esapi PUT /_watcher/watch/batch-metrics ${ES_CONFIG_DIR}/batch-metrics/batch-metrics.watcher.json \
  > /dev/null 2>&1

echo "Creating batch-metrics data view..."
kapi POST /api/data_views/data_view ${ES_CONFIG_DIR}/batch-metrics/batch-metrics.dataview.json \
  > ${ES_OUTPUTS_DIR}/batch-metrics.dataview.out.json

echo "Creating batch-metrics searches..."
kapi POST /api/saved_objects/search/batch-events-counts?overwrite=true \
  ${ES_CONFIG_DIR}/batch-metrics/batch-counts.search.json > /dev/null 2>&1

echo "✅ Batch metrics initialized"

# ============================================================================
# STEP 12: Initialize Spark GC (ILM, Templates, Ingest Pipelines, Data Views, Downsampling)
# ============================================================================
echo ""
echo "=== STEP 12: INITIALIZING SPARK GC ==="

echo "Creating spark-gc ILM policy..."
esapi PUT /_ilm/policy/spark-gc ${ES_CONFIG_DIR}/spark-gc/spark-gc.ilm.json \
  > ${ES_OUTPUTS_DIR}/spark-gc.ilm.out.json

echo "Creating spark-gc-downsampled ILM policy..."
esapi PUT /_ilm/policy/spark-gc-downsampled ${ES_CONFIG_DIR}/spark-gc/spark-gc-downsampled.ilm.json \
  > ${ES_OUTPUTS_DIR}/spark-gc-downsampled.ilm.out.json

echo "Creating spark-gc index template..."
esapi PUT /_index_template/spark-gc-ds ${ES_CONFIG_DIR}/spark-gc/spark-gc.template.json \
  > /dev/null 2>&1

echo "Creating spark-gc ingest pipeline..."
esapi PUT /_ingest/pipeline/logs-spark_gc-default ${ES_CONFIG_DIR}/spark-gc/spark-gc-ingest-pipeline.json \
  > ${ES_OUTPUTS_DIR}/spark-gc-ingest-pipeline.out.json

echo "Attaching downsampling policy to GC data stream..."
if esapi --allow-errors GET "/_data_stream/logs-spark_gc-default" > /dev/null 2>&1; then
  esapi PUT "logs-spark_gc-default/_settings" -d '{"index.lifecycle.name":"spark-gc-downsampled"}' > /dev/null 2>&1 || true
fi

echo "Creating spark-gc data view..."
kapi POST /api/data_views/data_view ${ES_CONFIG_DIR}/spark-gc/spark-gc.dataview.json \
  > ${ES_OUTPUTS_DIR}/spark-gc.dataview.out.json

echo "Creating spark-gc searches..."
kapi POST /api/saved_objects/search/spark-gc-search?overwrite=true \
  ${ES_CONFIG_DIR}/spark-gc/spark-gc.search.json \
  > ${ES_OUTPUTS_DIR}/spark-gc.search.out.json

echo "✅ Spark GC initialized"

# ============================================================================
# STEP 13: Initialize Spark Application Logs (ILM, Templates, Ingest Pipelines, Data Views, Transform, Downsampling)
# ============================================================================
echo ""
echo "=== STEP 13: INITIALIZING SPARK APPLICATION LOGS ==="

echo "Creating spark-logs ILM policy..."
esapi PUT /_ilm/policy/spark-logs ${ES_CONFIG_DIR}/spark-logs/spark-logs.ilm.json \
  > ${ES_OUTPUTS_DIR}/spark-logs.ilm.out.json

echo "Creating spark-logs ingest pipeline..."
esapi PUT /_ingest/pipeline/spark-logs-pipeline ${ES_CONFIG_DIR}/spark-logs/spark-logs-ingest-pipeline.json \
  > ${ES_OUTPUTS_DIR}/spark-logs-ingest-pipeline.out.json

echo "Creating logs-spark-default index template..."
esapi PUT /_index_template/logs-spark-default ${ES_CONFIG_DIR}/spark-logs/logs-spark-default.template.json \
  > ${ES_OUTPUTS_DIR}/logs-spark-default.template.out.json 2>&1

echo "Creating logs-spark-default data stream (force creation for transform)..."
if ! esapi --allow-errors GET /_data_stream/logs-spark-default > /dev/null 2>&1; then
  esapi PUT /_data_stream/logs-spark-default \
    > ${ES_OUTPUTS_DIR}/logs-spark-default.datastream.out.json 2>&1
  echo "  Data stream created"
else
  echo "  (data stream already exists, skipping)"
fi

echo "Creating spark-logs data view..."
kapi POST /api/data_views/data_view ${ES_CONFIG_DIR}/spark-logs/spark-logs.dataview.json \
  > ${ES_OUTPUTS_DIR}/spark-logs.dataview.out.json 2>&1

echo "Creating spark-logs default search..."
kapi POST /api/saved_objects/search/spark-logs-default?overwrite=true \
  ${ES_CONFIG_DIR}/spark-logs/spark-logs.search.json \
  > ${ES_OUTPUTS_DIR}/spark-logs.search.out.json 2>&1

# Create metrics data stream infrastructure
echo "Creating metrics ILM policy..."
esapi PUT /_ilm/policy/spark-metrics ${ES_CONFIG_DIR}/spark-logs/metrics-spark-logs.ilm.json \
  > ${ES_OUTPUTS_DIR}/metrics-spark-logs.ilm.out.json

echo "Creating spark-logs-metrics-downsampled ILM policy..."
esapi PUT /_ilm/policy/spark-logs-metrics-downsampled ${ES_CONFIG_DIR}/spark-logs/spark-logs-metrics-downsampled.ilm.json \
  > ${ES_OUTPUTS_DIR}/spark-logs-metrics-downsampled.ilm.out.json

echo "Creating metrics index template..."
esapi PUT /_index_template/metrics-spark-logs-default ${ES_CONFIG_DIR}/spark-logs/metrics-spark-logs.template.json \
  > ${ES_OUTPUTS_DIR}/metrics-spark-logs.template.out.json 2>&1

echo "Creating metrics data view..."
kapi POST /api/data_views/data_view ${ES_CONFIG_DIR}/spark-logs/metrics-spark-logs.dataview.json \
  > ${ES_OUTPUTS_DIR}/metrics-spark-logs.dataview.out.json 2>&1

echo "Creating metrics default search..."
kapi POST /api/saved_objects/search/spark-log-metrics-default?overwrite=true \
  ${ES_CONFIG_DIR}/spark-logs/metrics-spark-logs.search.json \
  > ${ES_OUTPUTS_DIR}/metrics-spark-logs.search.out.json 2>&1

# Create or update spark-log-metrics transform
echo "Checking if spark-log-metrics transform exists..."
if esapi --allow-errors GET /_transform/spark-log-metrics > /dev/null 2>&1; then
  TRANSFORM_EXISTS=$?
  if [ $TRANSFORM_EXISTS -eq 0 ]; then
    echo "Transform exists, updating..."
    # Stop existing transform
    esapi POST /_transform/spark-log-metrics/_stop?force=true \
      > ${ES_OUTPUTS_DIR}/spark-log-metrics-stop.out.json 2>&1 || true
    # Delete existing transform
    esapi DELETE /_transform/spark-log-metrics?force=true \
      > ${ES_OUTPUTS_DIR}/spark-log-metrics-delete.out.json 2>&1 || true
  else
    echo "Transform does not exist, will create..."
  fi
else
  echo "Transform does not exist, will create..."
fi

# Create transform (index now exists)
echo "Creating spark-log-metrics transform..."
esapi PUT /_transform/spark-log-metrics \
  ${ES_CONFIG_DIR}/spark-logs/spark-log-metrics-transform.json \
  > ${ES_OUTPUTS_DIR}/spark-log-metrics-transform.out.json 2>&1

# Start transform
echo "Starting spark-log-metrics transform..."
esapi POST /_transform/spark-log-metrics/_start \
  > ${ES_OUTPUTS_DIR}/spark-log-metrics-start.out.json 2>&1

echo "✅ Transform created and started"

echo "Attaching downsampling policy to spark log metrics data stream..."
if esapi --allow-errors GET "/_data_stream/metrics-spark-logs-default" > /dev/null 2>&1; then
  esapi PUT "metrics-spark-logs-default/_settings" -d '{"index.lifecycle.name":"spark-logs-metrics-downsampled"}' > /dev/null 2>&1 || true
fi

echo "✅ Spark Application Logs initialized"

# ============================================================================
# STEP 14: Initialize OpenTelemetry Traces (ILM, Templates, Data Views)
# ============================================================================
echo ""
echo "=== STEP 14: INITIALIZING OPENTELEMETRY TRACES (DATA STREAM) ==="

echo "Creating extract-application-fields ingest pipeline..."
esapi PUT /_ingest/pipeline/extract-application-fields \
  ${ES_CONFIG_DIR}/otel-traces/extract-application-fields-pipeline.json \
  > ${ES_OUTPUTS_DIR}/otel-traces.pipeline.out.json

echo "Creating spark-semantic-enrichment ingest pipeline..."
esapi PUT /_ingest/pipeline/spark-semantic-enrichment \
  ${ES_CONFIG_DIR}/otel-traces/spark-semantic-enrichment-pipeline.json \
  > ${ES_OUTPUTS_DIR}/otel-traces.semantic-pipeline.out.json

echo "Creating otel-traces ILM policy..."
esapi PUT /_ilm/policy/otel-traces \
  ${ES_CONFIG_DIR}/otel-traces/otel-traces.ilm-policy.json \
  > ${ES_OUTPUTS_DIR}/otel-traces.ilm.out.json

echo "Creating otel-traces data stream template..."
esapi PUT /_index_template/otel-traces \
  ${ES_CONFIG_DIR}/otel-traces/otel-traces.datastream.json \
  > ${ES_OUTPUTS_DIR}/otel-traces.template.out.json

echo "Creating traces-otel-default data stream if it doesn't exist..."
if ! esapi GET /_data_stream/traces-otel-default >& /dev/null; then
  esapi PUT /_data_stream/traces-otel-default \
    > ${ES_OUTPUTS_DIR}/otel-traces.datastream.out.json 2>&1
  echo "  Data stream created"
else
  echo "  (data stream already exists, skipping)"
fi

echo "Creating/updating otel-traces data view..."
# Note: Kibana doesn't have a cache flush API. When the title/index pattern changes,
# we need to delete and recreate the data view to ensure Kibana UI picks up the change.
# The override: true parameter may not be sufficient if Kibana has cached the old metadata.
# Extract desired title from JSON (using grep/sed as fallback if python3/jq unavailable)
DESIRED_TITLE=$(grep -o '"title"[[:space:]]*:[[:space:]]*"[^"]*"' ${ES_CONFIG_DIR}/otel-traces/otel-traces.dataview.json 2>/dev/null | sed 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "")
if [ -n "$DESIRED_TITLE" ]; then
  # Check if data view exists and get its current title
  if kapi --allow-errors GET /api/data_views/data_view/otel-traces > /tmp/otel-dataview-check.json 2>&1; then
    CURRENT_TITLE=$(grep -o '"title"[[:space:]]*:[[:space:]]*"[^"]*"' /tmp/otel-dataview-check.json 2>/dev/null | sed 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1 || echo "")
    if [ "$CURRENT_TITLE" != "$DESIRED_TITLE" ] && [ -n "$CURRENT_TITLE" ]; then
      echo "  Title mismatch (current: '$CURRENT_TITLE', desired: '$DESIRED_TITLE'), deleting old data view..."
      kapi DELETE /api/data_views/data_view/otel-traces > /dev/null 2>&1 || true
      sleep 1  # Brief pause to ensure deletion completes
    fi
  fi
fi
kapi POST /api/data_views/data_view \
  ${ES_CONFIG_DIR}/otel-traces/otel-traces.dataview.json \
  > ${ES_OUTPUTS_DIR}/otel-traces.dataview.out.json

echo "Creating otel-traces searches..."
kapi POST /api/saved_objects/search/otel-traces?overwrite=true \
  ${ES_CONFIG_DIR}/otel-traces/otel-traces.search.json > /dev/null 2>&1
kapi POST /api/saved_objects/search/spark-applications?overwrite=true \
  ${ES_CONFIG_DIR}/otel-traces/spark-applications.search.json > /dev/null 2>&1
kapi POST /api/saved_objects/search/spark-errors?overwrite=true \
  ${ES_CONFIG_DIR}/otel-traces/spark-errors.search.json > /dev/null 2>&1

echo "✅ OpenTelemetry traces (data stream) initialized"

# ============================================================================
# STEP 15: Initialize Application Events (ILM, Templates, Index, Data Views)
# ============================================================================
echo ""
echo "=== STEP 15: INITIALIZING APPLICATION EVENTS ==="

echo "Creating application-events ILM policy..."
esapi PUT /_ilm/policy/application-events \
  ${ES_CONFIG_DIR}/application-events/application-events.ilm.json \
  > ${ES_OUTPUTS_DIR}/application-events.ilm.out.json

echo "Creating application-events index template..."
esapi PUT /_index_template/application-events \
  ${ES_CONFIG_DIR}/application-events/application-events.template.json \
  > ${ES_OUTPUTS_DIR}/application-events.template.out.json

echo "Creating app-events-000001 index if it doesn't exist..."
if ! esapi GET /app-events-000001 >& /dev/null; then
  esapi PUT /app-events-000001 \
    ${ES_CONFIG_DIR}/application-events/application-events.index.json \
    > ${ES_OUTPUTS_DIR}/application-events.index.out.json
else
  echo "  (index already exists, skipping)"
fi

echo "Creating application-events data view..."
kapi POST /api/data_views/data_view \
  ${ES_CONFIG_DIR}/application-events/application-events.dataview.json \
  > ${ES_OUTPUTS_DIR}/application-events.dataview.out.json

echo "Creating application-events searches..."
kapi POST /api/saved_objects/search/application-events?overwrite=true \
  ${ES_CONFIG_DIR}/application-events/application-events.search.json > /dev/null 2>&1
kapi POST /api/saved_objects/search/open-operations?overwrite=true \
  ${ES_CONFIG_DIR}/application-events/open-operations.search.json > /dev/null 2>&1
kapi POST /api/saved_objects/search/active-applications?overwrite=true \
  ${ES_CONFIG_DIR}/application-events/active-applications.search.json > /dev/null 2>&1

echo "✅ Application events initialized"

# ============================================================================
# STEP 16: Initialize Application Events Metrics (Templates, Data Streams, Watchers, Data Views)
# ============================================================================
echo ""
echo "=== STEP 16: INITIALIZING APPLICATION EVENTS METRICS ==="

echo "Creating application-events-metrics ILM policy..."
esapi PUT /_ilm/policy/application-events-metrics ${ES_CONFIG_DIR}/application-events-metrics/application-events-metrics.ilm.json \
  > ${ES_OUTPUTS_DIR}/application-events-metrics.ilm.out.json

echo "Creating application-events-metrics index template..."
esapi PUT /_index_template/application-events-metrics-ds ${ES_CONFIG_DIR}/application-events-metrics/application-events-metrics.template.json \
  > /dev/null 2>&1

echo "Creating application-events-metrics data stream if it doesn't exist..."
if ! esapi GET /_data_stream/application-events-metrics-ds >& /dev/null; then
  esapi PUT /_data_stream/application-events-metrics-ds > /dev/null 2>&1
else
  echo "  (data stream already exists, skipping)"
fi

echo "Creating application-events-metrics watcher..."
esapi PUT /_watcher/watch/application-events-metrics ${ES_CONFIG_DIR}/application-events-metrics/application-events-metrics.watcher.json \
  > /dev/null 2>&1

echo "Creating application-events-metrics data view..."
kapi POST /api/data_views/data_view ${ES_CONFIG_DIR}/application-events-metrics/application-events-metrics.dataview.json \
  > ${ES_OUTPUTS_DIR}/application-events-metrics.dataview.out.json

echo "Creating application-events-metrics searches..."
kapi POST /api/saved_objects/search/application-events-counts?overwrite=true \
  ${ES_CONFIG_DIR}/application-events-metrics/application-events-counts.search.json > /dev/null 2>&1

echo "✅ Application events metrics initialized"

# ============================================================================
# STEP 17: Initialize Spark OTel Errors (Index Template, ILM Policy, Data View, Saved Search)
# ============================================================================
echo ""
echo "=== STEP 17: INITIALIZING SPARK OTEL ERRORS ==="

echo "Creating spark-otel-errors ILM policy..."
esapi PUT /_ilm/policy/spark-otel-errors \
  ${ES_CONFIG_DIR}/spark-otel-errors/spark-otel-errors.ilm.json \
  > /dev/null 2>&1

echo "Creating spark-otel-errors index template..."
esapi PUT /_index_template/spark-otel-errors ${ES_CONFIG_DIR}/spark-otel-errors/spark-otel-errors.template.json \
  > /dev/null 2>&1

echo "Creating spark-otel-errors data stream if it doesn't exist..."
if ! esapi GET /_data_stream/logs-spark-otel-errors-default >& /dev/null; then
  esapi PUT /_data_stream/logs-spark-otel-errors-default > /dev/null 2>&1
else
  echo "  (data stream already exists, skipping)"
fi

echo "Creating spark-otel-errors data view..."
kapi POST /api/data_views/data_view ${ES_CONFIG_DIR}/spark-otel-errors/spark-otel-errors.dataview.json \
  > ${ES_OUTPUTS_DIR}/spark-otel-errors.dataview.out.json

echo "Creating spark-otel-errors searches..."
kapi POST /api/saved_objects/search/spark-otel-errors?overwrite=true \
  ${ES_CONFIG_DIR}/spark-otel-errors/spark-otel-errors.search.json > /dev/null 2>&1

echo "✅ Spark OTel errors initialized"

# ============================================================================
# STEP 18: Initialize Watcher History Cleanup (ILM Policy, Template, Cleanup Watcher)
# ============================================================================
echo ""
echo "=== STEP 18: INITIALIZING WATCHER HISTORY CLEANUP ==="

echo "Creating watcher-history ILM policy..."
esapi PUT /_ilm/policy/watcher-history \
  ${ES_CONFIG_DIR}/watcher-history/watcher-history.ilm.json \
  > ${ES_OUTPUTS_DIR}/watcher-history.ilm.out.json

echo "Creating watcher-history index template..."
esapi PUT /_index_template/watcher-history \
  ${ES_CONFIG_DIR}/watcher-history/watcher-history.template.json \
  > ${ES_OUTPUTS_DIR}/watcher-history.template.out.json

echo "Applying ILM policy to existing watcher history indices..."
# Apply ILM policy to any existing watcher history indices
esapi POST "/.watcher-history-*/_settings" -d '{"index.lifecycle.name":"watcher-history"}' > /dev/null 2>&1 || true

echo "Creating watcher-history-cleanup watcher..."
esapi PUT /_watcher/watch/watcher-history-cleanup \
  ${ES_CONFIG_DIR}/watcher-history/watcher-history-cleanup.watcher.json \
  > ${ES_OUTPUTS_DIR}/watcher-history-cleanup.watcher.out.json

echo "✅ Watcher history cleanup initialized"

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
echo "  - Watchers: Configured for batch events, metrics, and history cleanup"
echo "  - Data Views: Created for all data sources"
echo "  - Searches: Created for all data views"
echo ""
echo "Next steps:"
echo "  1. Verify services at https://\${ES_HOST}:9200 and http://\${KB_HOST}:5601"
echo "  2. Check Kibana data views in Stack Management"
echo "  3. Start sending data from Spark applications"
echo ""
