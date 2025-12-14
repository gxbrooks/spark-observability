# Derivative Metric Calculation Architecture

## Overview

This document describes the architecture for computing rates (derivatives) from cumulative counter metrics (network I/O, disk I/O) using Logstash aggregate filters. Rates are precomputed at ingestion time and stored in Elasticsearch alongside counter values, enabling efficient visualization in Grafana across all time ranges and downsampled granularities.

## Architecture

### Data Flow

```
┌─────────────────┐
│ Elastic Agent   │
│ (System Metrics)│
└────────┬────────┘
         │
         │ Beats Protocol (TCP)
         │ data_stream.dataset: system.network, system.diskio
         ▼
┌─────────────────────────────────────────────────────────────┐
│ Logstash (system-metrics-rates pipeline)                    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Aggregate Filter (Network)                           │  │
│  │ - task_id: network_<host>|<interface>                │  │
│  │ - Maintains state: prev_in_bytes, prev_out_bytes     │  │
│  │ - Computes: system.network.in.bytes_rate             │  │
│  │           system.network.out.bytes_rate               │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Aggregate Filter (Disk I/O)                          │  │
│  │ - task_id: disk_<host>|<device>                      │  │
│  │ - Maintains state: prev_read_bytes, prev_write_bytes │  │
│  │ - Computes: system.diskio.read.bytes_rate            │  │
│  │           system.diskio.write.bytes_rate              │  │
│  └──────────────────────────────────────────────────────┘  │
└────────┬───────────────────────────────────────────────────┘
         │
         │ HTTP/HTTPS
         │ Documents with rate fields added
         ▼
┌─────────────────┐
│ Elasticsearch   │
│ (Data Streams)  │
│                 │
│ - Original      │
│   counters      │
│ - Precomputed   │
│   rates         │
└────────┬────────┘
         │
         │ Query with avg aggregation on rate fields
         ▼
┌─────────────────┐
│ Grafana         │
│ (Visualization) │
└─────────────────┘
```

### Key Components

#### 1. Elastic Agent

**Role**: Collects system metrics every 10 seconds (`ES_METRIC_SAMPLING_INTERVAL`)

**Configuration**:
- Routes cumulative counter metrics (network, diskio) to Logstash via Beats protocol
- Other metrics (CPU, memory, load) continue to Elasticsearch directly
- Maintains original data stream structure (`data_stream.type: metrics`, `data_stream.dataset: system.network`)

**Output Routing**:
```yaml
outputs:
  system_metrics_rates:
    type: logstash
    hosts: ["${LS_HOST}:${LS_SYSTEM_METRICS_PORT}"]
```

#### 2. Logstash Aggregate Filter Pipeline

**Purpose**: Compute rates (derivatives) from cumulative counters in real-time

**Pipeline**: `system-metrics-rates.conf`

**Key Features**:
- **Stateful Processing**: Maintains in-memory state per metric type and key
- **Composite Task ID**: `<metric_type>_<host>|<dimension>` (e.g., `network_lab1|eth0`)
- **Isolated State**: Each metric type has separate aggregate filter with isolated state
- **Real-time Computation**: Rates computed immediately as documents arrive
- **Counter Reset Handling**: Detects and handles counter resets (when current < previous)

**Rate Calculation Formula**:
```
rate = (current_counter - previous_counter) / time_delta_seconds
```

**First Document Handling**:
- First document per key has `rate = null` (expected)
- Subsequent documents have computed rates

#### 3. Elasticsearch Data Streams

**Role**: Store documents with both counter and rate fields

**Document Structure** (Network Example):
```json
{
  "@timestamp": "2025-12-13T10:00:00.000Z",
  "host.name": "lab1",
  "system.network.name": "eth0",
  "system.network.in.bytes": 21691424182,          // Counter (cumulative)
  "system.network.out.bytes": 5432109876,          // Counter (cumulative)
  "system.network.in.bytes_rate": 1634.5,          // Rate (precomputed, bytes/second)
  "system.network.out.bytes_rate": 456.7           // Rate (precomputed, bytes/second)
}
```

**Benefits**:
- ✅ Rates available immediately for querying
- ✅ No derivative aggregation needed in Grafana queries
- ✅ Works seamlessly with downsampled data (ILM averages rates correctly)
- ✅ Supports all time ranges (short and long)

#### 4. Grafana Queries

**Simplified Query Pattern**:
- Use `avg` aggregation on rate fields (not `derivative`)
- `date_histogram` with `$__interval` for time bucketing
- No pipeline aggregations needed

**Example Query** (Network In Rate):
```json
{
  "query": "_index:metrics-system.network-default* AND NOT system.network.name:lo",
  "metrics": [
    {
      "id": "1",
      "type": "avg",
      "field": "system.network.in.bytes_rate"
    }
  ],
  "bucketAggs": [
    {
      "type": "date_histogram",
      "field": "@timestamp",
      "settings": {
        "interval": "$__interval"
      }
    }
  ]
}
```

## Design Decisions

### Why Logstash Aggregate Filter?

1. **Efficiency**: 0% Elasticsearch CPU overhead (vs 10-15% for transform-based approaches)
2. **Real-time**: Zero latency in rate computation
3. **Simplicity**: Single filter per metric type vs transform + enrichment + pipeline
4. **Guarantees**: Every document (except first) gets rate computed
5. **Scalability**: Efficient for hundreds of nodes

### Why Precompute Rates?

1. **Downsampling Compatibility**: Precomputed rates average correctly during ILM downsampling
2. **Query Simplicity**: Grafana queries use simple `avg` aggregation, not derivatives
3. **Performance**: No derivative calculations at query time
4. **Reliability**: Rates computed once at ingestion, not on every query

### Composite Task ID Pattern

**Pattern**: `<metric_type>_<host>|<dimension>`

**Examples**:
- Network: `network_lab1|eth0`, `network_lab2|eth1` (stored in `_network_key` field)
- Disk I/O: `disk_lab1|sda`, `disk_lab1|sdb` (stored in `_disk_key` field)

**Benefits**:
- ✅ Unique per metric type + key combination
- ✅ Easy to identify metric type from task_id
- ✅ No collisions between different metric types (separate field names: `_network_key` vs `_disk_key`)
- ✅ State isolation per metric type

### Multi-Metric Support

**Single Pipeline Architecture**:
- One Logstash pipeline handles multiple metric types
- Each metric type has its own aggregate filter
- State isolation via composite task_id prefix
- Easy to extend with new metric types

**Supported Metrics**:
- Network I/O (`system.network`)
- Disk I/O (`system.diskio`)
- (Future: GPU, other cumulative metrics)

## Performance Characteristics

### Memory Usage

**Per Metric Type** (100 nodes × 5 interfaces/devices = 500 keys):
- State per key: ~500 bytes
- Total per metric type: ~250KB
- With 2-3 metric types: ~500-750KB total

**Verdict**: Negligible memory footprint

### CPU Usage

**Per Metric Type**:
- Aggregate filter: ~2-5% Logstash CPU
- O(1) hash lookup for state access
- Minimal computation (subtraction and division)

**Total**: ~5-10% Logstash CPU for 2-3 metric types

**Verdict**: Efficient, scales linearly

### Latency

- **Rate Computation**: Zero latency (instantaneous)
- **Document Processing**: Minimal (< 1ms per document)
- **End-to-end**: Document indexed with rates within milliseconds of arrival

**Verdict**: Real-time processing

## Deployment

### Logstash Pipeline Configuration

**Location**: `observability/logstash/pipeline/system-metrics-rates.conf`

**Port**: Configured via `LS_SYSTEM_METRICS_PORT` variable (default: 5051)

**Input**: Beats protocol on configured port

**Output**: Elasticsearch (same data streams, documents with rate fields added)

### Elastic Agent Configuration

**Update**: `elastic-agent.linux.yml.j2`

**Changes**:
- Add `system_metrics_rates` output (Logstash type)
- Route `system.network` and `system.diskio` streams to Logstash
- Keep other metrics routing to Elasticsearch directly

### Grafana Panel Updates

**Update Panels**:
- Replace derivative aggregations with `avg` on rate fields
- Remove pipeline aggregations (derivative, bucket_script for negation)
- Use `$__interval` for time bucketing (works with precomputed rates)

## Operational Considerations

### State Management

**In-Memory State**:
- State maintained in Logstash memory per `task_id`
- State lost on Logstash restart
- State rebuilds automatically as new documents arrive

**First Document After Restart**:
- Rate = `null` (expected behavior)
- Subsequent documents have computed rates

**Timeout**:
- State kept for 1 hour (3600 seconds)
- Handles temporary interface/device disappearance

### Counter Resets

**Detection**: When `current_counter < previous_counter`

**Handling**: Set rate to `null` (indicates counter reset event)

**Recovery**: Next document with valid counter computes rate normally

### Monitoring

**Logstash Health**:
- Monitor Logstash container status
- Check Logstash logs for aggregate filter errors
- Monitor Logstash CPU/memory usage

**Rate Field Population**:
- Query Elasticsearch for documents with null rates
- Should only see first document per key (expected)
- If many null rates, investigate Logstash issues

## Troubleshooting

### Issue: Rates Not Being Computed

**Symptoms**: All rate fields are `null`

**Diagnosis**:
1. Check Logstash is running: `docker ps | grep logstash`
2. Check Logstash logs: `docker logs logstash01`
3. Verify Elastic Agent routing to Logstash
4. Check aggregate filter task_id generation (should match pattern)

### Issue: Incorrect Rate Values

**Symptoms**: Rates appear too high/low or negative

**Diagnosis**:
1. Check counter values are cumulative (monotonically increasing)
2. Verify time delta calculation (should be in seconds)
3. Check for counter resets (should set rate to null)
4. Review aggregate filter code logic

### Issue: Missing Rate Fields

**Symptoms**: Documents don't have rate fields

**Diagnosis**:
1. Verify aggregate filter is processing documents (check logs)
2. Check data_stream.dataset matches filter conditions
3. Verify required fields (counters, timestamp) are present
4. Check Ruby filter creates appropriate key field (`_network_key`, `_disk_key`, etc.) correctly

## Extension Points

### Adding New Metric Types

1. Add new `else if` block in Logstash pipeline
2. Create composite task_id: `<new_type>_<host>|<dimension>`
3. Implement aggregate filter with appropriate counter fields
4. Update Grafana panels to use new rate fields

**Example** (GPU Metrics):
```ruby
else if [data_stream][dataset] == "gpu.memory" {
  ruby {
    code => "
      host = event.get('[host][name]')
      gpu_id = event.get('[gpu][id]')
      if host && gpu_id
        event.set('_gpu_key', 'gpu_' + host + '|' + gpu_id)
      end
    "
  }
  
  aggregate {
    task_id => "%{[_gpu_key]}"
    code => "
      # ... GPU-specific rate computation
    "
  }
}
```

## Summary

The Logstash aggregate filter approach provides:

- ✅ **Efficient**: Minimal CPU/memory overhead
- ✅ **Real-time**: Zero latency rate computation
- ✅ **Simple**: Single pipeline, easy to maintain
- ✅ **Scalable**: Handles hundreds of nodes efficiently
- ✅ **Reliable**: Guaranteed rate computation (except first document)
- ✅ **Extensible**: Easy to add new metric types

This architecture eliminates the complexity and performance issues of computing derivatives at query time, providing a production-ready solution for visualizing cumulative counter metrics.

## References

- Logstash Aggregate Filter: https://www.elastic.co/guide/en/logstash/current/plugins-filters-aggregate.html
- Elasticsearch Data Streams: https://www.elastic.co/guide/en/elasticsearch/reference/current/data-streams.html
- Grafana Elasticsearch Datasource: https://grafana.com/docs/grafana/latest/datasources/elasticsearch/
