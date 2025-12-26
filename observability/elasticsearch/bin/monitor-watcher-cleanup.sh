#!/bin/bash
#
# Monitor Watcher History Cleanup
# 
# Checks watcher history index sizes every 30 minutes and logs the results.
# Run this script in the background to monitor through the night.
#
# Usage:
#   nohup ./monitor-watcher-cleanup.sh > /tmp/watcher-cleanup-monitor.log 2>&1 &
#   tail -f /tmp/watcher-cleanup-monitor.log
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."  # Go to observability directory

LOG_FILE="/tmp/watcher-cleanup-monitor.log"
INTERVAL_MINUTES=30
INTERVAL_SECONDS=$((INTERVAL_MINUTES * 60))

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Function to call Elasticsearch API via docker compose
esapi() {
    docker compose exec -T es01 curl -s -u elastic:myElastic2025 -k "https://localhost:9200$@"
}

# Function to get index sizes
check_index_sizes() {
    log "=== Checking Watcher History Index Sizes ==="
    
    # Get index sizes
    indices_info=$(esapi "/_cat/indices/.watcher-history-*?v&h=index,docs.count,store.size&s=index&format=json" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$indices_info" ]; then
        echo "$indices_info" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print('Index Name                    | Docs Count  | Store Size')
    print('-' * 60)
    total_docs = 0
    for idx in data:
        name = idx.get('index', 'unknown')
        docs = idx.get('docs.count', '0')
        size = idx.get('store.size', '0b')
        print(f'{name:29} | {docs:>11} | {size:>10}')
        try:
            total_docs += int(docs)
        except:
            pass
    print('-' * 60)
    print(f'{"TOTAL":29} | {total_docs:>11} |')
except Exception as e:
    print(f'Error parsing indices: {e}', file=sys.stderr)
    sys.exit(1)
" | tee -a "$LOG_FILE"
        
        log "Total documents across all watcher history indices: $(echo "$indices_info" | python3 -c "import sys, json; data=json.load(sys.stdin); print(sum(int(idx.get('docs.count', 0)) for idx in data if str(idx.get('docs.count', '0')).isdigit()))" 2>/dev/null || echo "unknown")"
    else
        log "❌ Error: Failed to retrieve index information"
    fi
}

# Function to check watcher status
check_watcher_status() {
    log "=== Checking Watcher Status ==="
    
    watcher_status=$(esapi "/_watcher/watch/watcher-history-cleanup" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$watcher_status" ]; then
        echo "$watcher_status" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    status = data.get('status', {})
    state = status.get('state', {}).get('active', 'unknown')
    last_checked = status.get('last_checked', 'never')
    
    action_status = status.get('actions', {}).get('cleanup_non_executed', {})
    last_execution = action_status.get('last_execution', {})
    last_exec_time = last_execution.get('timestamp', 'never')
    last_exec_successful = last_execution.get('successful', False)
    
    print(f'Watcher State: {state}')
    print(f'Last Checked: {last_checked}')
    print(f'Last Execution: {last_exec_time}')
    print(f'Last Execution Successful: {last_exec_successful}')
    
    # Check for any execution failures
    failures = last_execution.get('reason', '')
    if failures and 'error' in str(failures).lower():
        print(f'⚠️  Warning: {failures}')
except Exception as e:
    print(f'Error parsing watcher status: {e}', file=sys.stderr)
" | tee -a "$LOG_FILE"
    else
        log "❌ Error: Failed to retrieve watcher status"
    fi
}

# Function to check condition met vs not met counts
check_condition_stats() {
    log "=== Checking Condition Statistics ==="
    
    stats=$(esapi "/.watcher-history-*/_search?size=0" -H "Content-Type: application/json" \
        -d '{"aggs":{"by_condition":{"terms":{"field":"result.condition.met","missing":"null"}}}}' 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$stats" ]; then
        echo "$stats" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    total = data.get('hits', {}).get('total', {}).get('value', 0)
    buckets = data.get('aggregations', {}).get('by_condition', {}).get('buckets', [])
    
    print(f'Total documents: {total:,}')
    
    met_count = 0
    not_met_count = 0
    
    for bucket in buckets:
        key = bucket.get('key', 'unknown')
        count = bucket.get('doc_count', 0)
        if key == True or key == 'true':
            met_count = count
            print(f'  Condition met (true): {count:,}')
        elif key == False or key == 'false':
            not_met_count = count
            print(f'  Condition NOT met (false): {count:,}')
        else:
            print(f'  Condition {key}: {count:,}')
    
    if not_met_count > 0:
        percentage = (not_met_count / total * 100) if total > 0 else 0
        print(f'  Non-executed percentage: {percentage:.1f}%')
        
        # Estimate cleanup time
        docs_per_hour = 60000  # 10k docs per run × 6 runs per hour
        hours_to_clean = not_met_count / docs_per_hour if docs_per_hour > 0 else 0
        print(f'  Estimated cleanup time: {hours_to_clean:.2f} hours at current rate')
except Exception as e:
    print(f'Error parsing stats: {e}', file=sys.stderr)
" | tee -a "$LOG_FILE"
    else
        log "❌ Error: Failed to retrieve condition statistics"
    fi
}

# Main monitoring loop
log "=========================================="
log "Starting Watcher History Cleanup Monitor"
log "Checking every $INTERVAL_MINUTES minutes"
log "Log file: $LOG_FILE"
log "=========================================="

# Initial check
check_index_sizes
check_watcher_status
check_condition_stats

# Monitoring loop
while true; do
    sleep "$INTERVAL_SECONDS"
    log ""
    log "=========================================="
    check_index_sizes
    log ""
    check_watcher_status
    log ""
    check_condition_stats
    log "=========================================="
    log "Next check in $INTERVAL_MINUTES minutes"
    log ""
done
