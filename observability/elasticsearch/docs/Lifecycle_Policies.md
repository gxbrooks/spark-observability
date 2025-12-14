# Elasticsearch Lifecycle Policies for Metrics Downsampling

## Overview

Index Lifecycle Management (ILM) policies with automatic downsampling reduce storage costs while maintaining historical data access. Elasticsearch automatically downsamples metrics data through progressive intervals as it ages.

## Metric Collection Frequency

**Base Sampling Rate**: System metrics are collected at intervals specified by `ES_METRIC_SAMPLING_INTERVAL` (currently **10 seconds**).

- Source: Variable `ES_METRIC_SAMPLING_INTERVAL` in `/vars/variables.yaml`
- Current value: `10s` (Elastic Agent `system/metrics` input default period)
- Configuration: See `elastic-agent/elastic-agent.linux.yml.j2`
- Affects: All system metric data streams (CPU, memory, network, disk, load)
- **Future**: Elastic best practice is 0.5s sampling, to be implemented after aligning on derivative graphing approach

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

Retention periods are defined in `/vars/variables.yaml` (lines 36-53) using the following variables:

| Variable | Default Value | Description | ILM Phase Mapping |
|----------|---------------|-------------|-------------------|
| `ES_METRIC_SAMPLING_INTERVAL` | `10s` | Base metric collection frequency | Used in Grafana queries and downsampling |
| `ES_RETENTION_BASE` | `2d` | Hot phase retention (original sampling interval data) | Hot phase duration |
| `ES_RETENTION_5MIN` | `4d` | Warm phase start age (5-minute downsampled data) | Warm phase `min_age` |
| `ES_RETENTION_15MIN` | `8d` | Cold phase start age (15-minute downsampled data) | Cold phase `min_age` |
| `ES_RETENTION_60MIN` | `730d` | Delete threshold (60-minute downsampled data, 2 years) | Delete phase `min_age` |

**ILM Policy Configuration** (from `system-metrics.ilm.json`):

| Phase | min_age | Downsample Interval | Variable Reference |
|-------|---------|---------------------|-------------------|
| **Hot** | `0ms` | 5m (after rollover) | `ES_RETENTION_BASE` = 2d (actual hot retention) |
| **Warm** | `4d` | 15m | `ES_RETENTION_5MIN` = 4d |
| **Cold** | `8d` | 60m | `ES_RETENTION_15MIN` = 8d |
| **Delete** | `730d` | - | `ES_RETENTION_60MIN` = 730d (2 years) |

**Note**: The ILM policy uses **absolute ages** (not cumulative). The variables represent the transition points:
- Data remains in Hot phase until `ES_RETENTION_5MIN` (4 days), then transitions to Warm
- Data remains in Warm phase until `ES_RETENTION_15MIN` (8 days), then transitions to Cold
- Data remains in Cold phase until `ES_RETENTION_60MIN` (730 days = 2 years), then is deleted

**Important**: Current retention values are test/lab values for rapid validation. Delete threshold follows Elastic best practice of 2 years for metrics data.

### Enterprise Production Recommendations

For production deployments, consider Elastic's best practices:

| Variable | Production Value | Description |
|----------|------------------|-------------|
| `ES_METRIC_SAMPLING_INTERVAL` | `0.5s` | Elastic best practice for metric sampling |
| `ES_RETENTION_BASE` | `7d` | 1 week high-resolution (base interval → 5m) |
| `ES_RETENTION_5MIN` | `30d` | 1 month at 5m intervals |
| `ES_RETENTION_15MIN` | `90d` | 3 months at 15m intervals |
| `ES_RETENTION_60MIN` | `730d` | 2 years at hourly intervals (best practice) |

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

### ILM Polling Frequency

**Default**: ILM polls policies every **10 minutes** (`indices.lifecycle.poll_interval`)

This is an Elasticsearch cluster setting, not configurable per-policy. To check current setting:

```bash
# Check ILM poll interval
esapi GET /_cluster/settings?include_defaults=true&filter_path=**.lifecycle.poll_interval
```

**Note**: No custom polling configuration is set in this deployment, so the default 10-minute interval applies.

## Storage Savings

Progressive downsampling provides significant storage reduction:

| Interval | Compression Ratio | Storage Reduction |
|----------|-------------------|-------------------|
| 30s → 5m | 10:1 | ~90% |
| 5m → 15m | 3:1 | ~67% (cumulative ~97%) |
| 15m → 60m | 4:1 | ~75% (cumulative ~99%) |

**Overall**: ~95% storage savings while maintaining 730-day (2-year) retention for downsampled data.

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

### Date Histogram and Derivative Alignment

When using derivative aggregations for rate calculations (network, disk I/O):

1. **Date Histogram Interval**: Must be >= base metric sampling frequency (10s)
2. **Derivative Unit**: Should match the date histogram interval
3. **Critical Rule**: If date_histogram interval < derivative unit, derivative values may be NULL

**Why derivatives return NULL when interval < unit**:

The Elasticsearch derivative aggregation calculates rates by comparing the current bucket's value with a previous bucket that is exactly `unit` time before it. When the date_histogram creates buckets smaller than the derivative unit (e.g., 1s buckets with 10s unit):

- The derivative needs to find a bucket that is exactly `unit` time before the current bucket
- With smaller intervals, it must look back multiple buckets (e.g., 10 buckets for 1s interval with 10s unit)
- If the target bucket is empty (no documents), outside the query window, or misaligned, Elasticsearch returns NULL
- **Solution**: Always ensure `date_histogram.interval >= derivative.unit`, and ideally they should match

**Example of the problem**:
```
Date Histogram: 1s intervals
Derivative Unit: 10s

Buckets:
  10:00:00 → value: 1000
  10:00:01 → derivative needs bucket at 09:59:51 (may not exist or be empty) → NULL
  10:00:02 → derivative needs bucket at 09:59:52 (may not exist or be empty) → NULL
  ...
  10:00:10 → derivative finds bucket at 10:00:00 ✅ (10s before) → Calculated
```

**Recommended Configuration**:
- For current data (< 4 days): Use intervals matching `ES_METRIC_SAMPLING_INTERVAL` (currently 10s) to match base sampling rate
- For downsampled data (4-8 days): Use 5m or larger intervals to match downsampled granularity (5m)
- For older data (8-730 days): Use 15m or larger intervals to match downsampled granularity (15m, 60m)
- Use fixed base interval in queries, let Grafana handle display downsampling (see Derivative_Metric_Calculation.md)

See `/observability/grafana/docs/Derivative_Metric_Calculation.md` for detailed examples.

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

