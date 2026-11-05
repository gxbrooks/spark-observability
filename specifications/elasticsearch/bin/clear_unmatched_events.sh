#!/usr/bin/env bash
# Clear unmatched Spark start events from batch-events index
# These are events from aborted Spark operations that never received matching end events
#
# Usage:
#   ./clear_unmatched_events.sh           # Dry run (show what would be deleted)
#   ./clear_unmatched_events.sh --execute # Actually delete the events

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config/batch-events"
EXECUTE=false

# Parse arguments
if [[ "${1:-}" == "--execute" ]]; then
    EXECUTE=true
fi

echo "=== Clear Unmatched Spark Events ==="
echo ""

# First, show what would be cleared
echo "Querying unmatched events (matched=false)..."
UNMATCHED_COUNT=$(esapi POST /batch-events/_count -d '{"query": {"term": {"matched": false}}, "size": 0}' 2>/dev/null | jq -r '.count // 0')

echo "Found ${UNMATCHED_COUNT} unmatched events"
echo ""

if [[ "${UNMATCHED_COUNT}" == "0" ]]; then
    echo "No unmatched events to clear. Exiting."
    exit 0
fi

# Show sample of events
echo "Sample of unmatched events:"
esapi GET /batch-events/_search -d '{
  "query": {"term": {"matched": false}},
  "size": 5,
  "sort": [{"@timestamp": "desc"}],
  "_source": ["event_uid", "event_type", "@timestamp", "app_name"]
}' 2>/dev/null | jq -r '.hits.hits[] | "  - \(._source.event_uid) (\(._source["@timestamp"]))"'

echo ""

if [[ "${EXECUTE}" == "false" ]]; then
    echo "DRY RUN: Use --execute to actually delete these events"
    echo ""
    echo "Command that would be executed:"
    echo '  esapi POST /batch-events/_delete_by_query -d '"'"'{"query": {"term": {"matched": false}}}'"'"
    exit 0
fi

# Execute the deletion
echo "EXECUTING: Clearing unmatched events..."
RESULT=$(esapi POST /batch-events/_delete_by_query -d '{"query": {"term": {"matched": false}}}' 2>/dev/null)

DELETED=$(echo "${RESULT}" | jq -r '.deleted // 0')
FAILURES=$(echo "${RESULT}" | jq -r '.failures | length')

echo ""
echo "=== Results ==="
echo "Deleted: ${DELETED} documents"
echo "Failures: ${FAILURES}"

if [[ "${FAILURES}" != "0" ]]; then
    echo ""
    echo "Failure details:"
    echo "${RESULT}" | jq '.failures'
    exit 1
fi

echo ""
echo "✅ Successfully cleared ${DELETED} unmatched events"

