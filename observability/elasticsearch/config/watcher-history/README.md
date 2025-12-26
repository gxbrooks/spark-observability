# Watcher History Cleanup

This directory contains configuration for cleaning up Elasticsearch Watcher execution history to reduce storage overhead.

## Problem

Watchers that run frequently (e.g., every 5 seconds) create execution records in `.watcher-history-*` indices even when their conditions are not met (`result.condition.met: false`). These non-executed watcher runs can accumulate quickly and consume significant storage space without providing useful information.

## Solution

Two mechanisms are provided to compress watcher history:

1. **ILM Policy** (`watcher-history.ilm.json`): Manages lifecycle of watcher history indices with 30-day retention
2. **Cleanup Watcher** (`watcher-history-cleanup.watcher.json`): Periodically deletes non-executed watcher runs (where `result.condition.met: false`) older than 1 hour, running every 10 minutes

## Components

### watcher-history.ilm.json
- **Hot Phase**: Rollover at 1GB or 7 days
- **Warm Phase**: Force merge after 7 days
- **Delete Phase**: Delete indices after 30 days

### watcher-history-cleanup.watcher.json
- **Trigger**: Runs every 10 minutes
- **Condition**: Only executes if there are non-executed watcher runs older than one hour
- **Action**: Deletes watcher history records where:
  - `result.condition.met: false` (condition was not met)
  - `@timestamp` less than `now-1h` (all data older than 1 hour)
- **Incremental Processing**:
  - **Time Window**: Processes all data older than 1 hour (protects everything newer than 1 hour)
  - **Batch Limiting**: `max_docs=10000` ensures each run processes at most 10,000 documents
  - **Gradual Cleanup**: Large backlogs are processed incrementally over multiple 10-minute runs (10,000 docs per 10 minutes = 60,000 docs per hour)
  - `requests_per_second=100`: Increased deletion rate for faster cleanup
  - `scroll_size=1000`: Larger batch size (1000 docs) for more efficient processing
  - `max_docs=10000`: Maximum documents deleted per run (increased from 5000)
  - `wait_for_completion=false`: Runs asynchronously to avoid blocking

### watcher-history.template.json
- Applies the ILM policy to all `.watcher-history-*` indices
- Ensures new watcher history indices automatically use the lifecycle policy

## Usage

The cleanup watcher and ILM policy are automatically initialized by `init-index.sh`:

```bash
cd observability/elasticsearch/bin
./init-index.sh
```

## Manual Operations

### Check Cleanup Watcher Status
```bash
esapi GET /_watcher/watch/watcher-history-cleanup
```

### Execute Cleanup Watcher Manually
```bash
esapi POST /_watcher/watch/watcher-history-cleanup/_execute
```

### Check Watcher History Size
```bash
esapi GET '/_cat/indices/.watcher-history-*?v&h=index,docs.count,store.size&s=index'
```

### Apply ILM Policy to Existing Indices
```bash
esapi POST "/.watcher-history-*/_settings" -d '{"index.lifecycle.name":"watcher-history"}'
```

## Benefits

- **Reduced Storage**: Only retains watcher execution records where conditions were met
- **Faster Queries**: Smaller indices improve query performance
- **Automatic Cleanup**: No manual intervention required
- **Retention Control**: ILM policy ensures long-term cleanup
- **Incremental Processing**: 1-hour cleanup window processes data gradually to avoid overwhelming Elasticsearch/Kibana while keeping indices small
- **Rate Limiting**: Controlled deletion rate (100 requests/sec, 1000 docs per batch, max 10k docs per run)

## Performance

Current aggressive cleanup settings:
- **Watcher execution time**: ~600ms (wall clock)
- **Batch size**: 10,000 records per run (increased from 5,000)
- **Frequency**: 10 minutes (increased from 1 hour)
- **Throughput**: Up to 60,000 records per hour (10,000 × 6 runs/hour)
- **Time window**: 1 hour (reduced from 24 hours for faster cleanup)
- **Deletion rate**: 100 requests/second (increased from 50)

With these settings, a backlog of 150,000 records would be cleaned up in approximately 2.5 hours (150,000 ÷ 60,000 per hour).

To further accelerate cleanup if needed:
- Increase `max_docs` (currently 10,000) to process more per run
- Decrease time window (currently 1h) to clean up records sooner
- Increase `requests_per_second` (currently 100) for faster deletion

## Note

The cleanup watcher uses hardcoded credentials (`elastic:myElastic2025`) in the webhook action. For production environments, consider using Elasticsearch Watcher secrets for secure credential storage.

