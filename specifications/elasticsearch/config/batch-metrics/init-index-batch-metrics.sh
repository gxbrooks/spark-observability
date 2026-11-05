#!/usr/bin/bash

# DEPRECATED — batch-metrics-ds data stream and watcher
#
# The batch-metrics-ds approach counted "active Spark jobs" by watching the
# batch-events-* indices for Start events with matched=false, aggregating
# counts by realm and class, and indexing the result into the
# batch-metrics-ds data stream every 5 seconds.
#
# This pipeline was non-functional prior to deprecation:
#   - The watcher condition (ctx.payload.hits.total > 0) never fired because
#     all historical Start events had already been marked matched=true and
#     no new batch-events were being ingested.
#   - The Elasticsearch transform disk flood-stage watermark also blocked
#     new writes.
#
# The "Active Application Jobs" panel (application-events-metrics-ds) now
# provides equivalent and more reliable active-job tracking.
#
# This standalone script is provided so the resources can still be created
# manually if needed for testing or migration.  It is NOT called by
# init-index.sh.

set -e

# Require esapi / kapi on PATH and ES_CONFIG_DIR set
if ! command -v esapi &>/dev/null || ! command -v kapi &>/dev/null; then
  echo "❌ esapi and kapi must be on PATH.  Source the init-index.sh environment"
  echo "   or export the ES_* / KB_* variables and add bin/ to PATH."
  exit 1
fi

if [[ -z "${ES_CONFIG_DIR}" ]]; then
  echo "❌ ES_CONFIG_DIR is not set."
  exit 1
fi

BATCH_DIR="${ES_CONFIG_DIR}/batch-metrics"
ES_OUTPUTS_DIR="${ES_OUTPUTS_DIR:-${ES_CONFIG_DIR}/../outputs}"

echo "=== INITIALIZING BATCH METRICS (deprecated) ==="

echo "Creating batch-metrics index template..."
esapi PUT /_index_template/batch-metrics-ds "${BATCH_DIR}/batch-metrics.template.json" \
  > /dev/null 2>&1

echo "Creating batch-metrics data stream if it doesn't exist..."
if ! esapi GET /_data_stream/batch-metrics-ds >& /dev/null; then
  esapi PUT /_data_stream/batch-metrics-ds > /dev/null 2>&1
else
  echo "  (data stream already exists, skipping)"
fi

echo "Creating batch-metrics watcher..."
esapi PUT /_watcher/watch/batch-metrics "${BATCH_DIR}/batch-metrics.watcher.json" \
  > /dev/null 2>&1

echo "Creating batch-metrics data view..."
kapi POST /api/data_views/data_view "${BATCH_DIR}/batch-metrics.dataview.json" \
  > "${ES_OUTPUTS_DIR}/batch-metrics.dataview.out.json"

echo "Creating batch-metrics searches..."
kapi POST /api/saved_objects/search/batch-events-counts?overwrite=true \
  "${BATCH_DIR}/batch-counts.search.json" > /dev/null 2>&1

echo "✅ Batch metrics initialized (deprecated)"
