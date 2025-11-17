# Elasticsearch Lifecycle Policies for Metrics Downsampling

## Overview

Index Lifecycle Management (ILM) policies with automatic downsampling reduce storage costs while maintaining historical data access. Elasticsearch automatically downsamples metrics data through progressive intervals as it ages.

## Downsampling Strategy

| Phase | Data Age | Sampling Interval | Actions |
|-------|----------|-------------------|---------|
| **Hot** | 0-2 days | 30s → 5m | Rollover after 1d or 50GB, then downsample to 5m |
| **Warm** | 2-4 days | 5m → 15m | Downsample to 15-minute intervals |
| **Cold** | 4-8 days | 15m → 60m | Downsample to 60-minute intervals |
| **Delete** | >12 days | - | Data removal |

**Note**: Elasticsearch cannot downsample in the Frozen phase, only in Hot, Warm, and Cold.

## Policies

### system-metrics-downsampled

**Location**: `config/system-metrics/system-metrics.ilm.json`

**Applies to**:
- `metrics-system.cpu-default`
- `metrics-system.memory-default`
- `metrics-system.network-default`
- `metrics-system.diskio-default`
- `metrics-system.load-default`

### docker-metrics-downsampled

**Location**: `config/docker-metrics/docker-metrics.ilm.json`

**Applies to**:
- `metrics-docker.cpu-default`
- `metrics-docker.memory-default`
- `metrics-docker.network-default`

### spark-gc-downsampled

**Location**: `config/spark-gc/spark-gc-downsampled.ilm.json`

**Applies to**:
- `logs-spark_gc-default`

### spark-logs-metrics-downsampled

**Location**: `config/spark-logs/spark-logs-metrics-downsampled.ilm.json`

**Applies to**:
- `metrics-spark-logs-default`

## Configuration

Retention periods are defined in `/vars/variables.yaml` (lines 36-53):

```yaml
ES_RETENTION_BASE:      2d   # Hot phase retention
ES_RETENTION_5MIN:      4d   # Warm phase (cumulative)
ES_RETENTION_15MIN:     8d   # Cold phase (cumulative)  
ES_RETENTION_60MIN:     12d  # Delete threshold
```

**Important**: These are test/lab values for rapid validation (12-day cycle).

### Enterprise Production Recommendations

For production deployments, consider Elastic's best practices:

```yaml
ES_RETENTION_BASE:      7d      # 1 week high-resolution
ES_RETENTION_5MIN:      30d     # 1 month at 5m intervals
ES_RETENTION_15MIN:     90d     # 3 months at 15m intervals
ES_RETENTION_60MIN:     365d    # 1 year at hourly intervals
```

**Source**: [Elasticsearch Data Tiers](https://www.elastic.co/guide/en/elasticsearch/reference/current/data-tiers.html)

## Automatic Application

ILM policies are automatically created and attached by `init-index.sh` (STEP 10):

```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin
./init-index.sh
```

The script:
1. Creates all 4 downsampling ILM policies
2. Checks if data streams exist
3. Attaches policies to existing data streams
4. Skips gracefully if streams don't exist yet

## Time Series Data Stream (TSDS) Requirements

For downsampling to work, data streams must support time series features:

1. **@timestamp field**: Primary time dimension
2. **Dimensions**: Fields identifying unique series (e.g., `host.name`, `pod.name`)
3. **Metrics**: Numeric fields with proper types (gauge, counter, histogram)

The Elastic Agent automatically configures system and docker metrics as TSDS-compatible.

## Monitoring

### Check Policy Status

```bash
# View ILM policy
esapi GET /_ilm/policy/system-metrics-downsampled

# Check policy attachment
esapi GET /metrics-system.cpu-default/_ilm/explain

# List all ILM policies
esapi GET /_ilm/policy
```

### Verify Downsampling Execution

```bash
# Check for downsampled indices (after 2+ days)
esapi GET '/_cat/indices/.ds-*downsample*?v'

# Monitor ILM execution
esapi GET /metrics-system.cpu-default/_ilm/explain
```

### ILM Service Status

```bash
# Check ILM is running
esapi GET /_ilm/status

# Start ILM if stopped
esapi POST /_ilm/start

# Force ILM to check policies
esapi POST /_ilm/poll
```

## Storage Savings

Progressive downsampling provides significant storage reduction:

| Interval | Compression Ratio | Storage Reduction |
|----------|-------------------|-------------------|
| 30s → 5m | 10:1 | ~90% |
| 5m → 15m | 3:1 | ~67% (cumulative ~97%) |
| 15m → 60m | 4:1 | ~75% (cumulative ~99%) |

**Overall**: ~95% storage savings while maintaining 12-day retention.

## Limitations

### Irreversible Operation
- Downsampling cannot be reversed
- Original high-resolution data is permanently removed
- Plan retention periods carefully

### Aggregation Compatibility
- Some aggregations don't work on downsampled data
- Percentile aggregations not supported
- Histogram fields cannot be downsampled

### Field Requirements
- Only numeric gauge and counter fields are downsampled
- Text and keyword fields are preserved
- Join relationships are not downsampled

## Grafana Integration

The "Spark System Metrics" dashboard automatically queries the appropriate data:
- Elasticsearch serves downsampled data transparently
- No special dashboard configuration needed
- Queries use standard `-default` index patterns

**Dashboard**: http://GaryPC.local:3000/d/spark-system-metrics-aggregated

## Troubleshooting

### Downsampling Not Occurring

**Check**:
1. ILM is running: `GET /_ilm/status`
2. Data has rolled over: `GET /_cat/indices/.ds-metrics-*`
3. Data is old enough: Check `age` in `_ilm/explain`
4. No errors: Look for `step_info.error` in `_ilm/explain`

**Solution**: Force rollover if needed:
```bash
esapi POST /metrics-system.cpu-default/_rollover
```

### Policy Not Applying

**Check**: Verify policy attachment
```bash
esapi GET /metrics-system.cpu-default/_settings | grep lifecycle
```

**Solution**: Rerun STEP 10 attachment logic from init-index.sh manually

## References

- **Implementation**: `/observability/DOWNSAMPLING_IMPLEMENTATION.md`
- **Quick Start**: `/observability/QUICK_START_DOWNSAMPLING.md`
- **Elasticsearch Guide**: https://www.elastic.co/guide/en/elasticsearch/reference/8.15/downsampling.html
- **Data Tiers**: https://www.elastic.co/guide/en/elasticsearch/reference/current/data-tiers.html

