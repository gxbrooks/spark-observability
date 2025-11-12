# System Metrics Downsampling and Lifecycle Policies

This directory contains Index Lifecycle Management (ILM) policies for system, docker, and spark metrics with downsampling enabled.

## Overview

These policies implement a tiered data retention strategy with automatic downsampling to reduce storage costs while maintaining historical data.

## Retention and Downsampling Strategy

| Phase | Age | Interval | Retention | Notes |
|-------|-----|----------|-----------|-------|
| **Hot** | 0-2 days | 30s → 5m | ~2 days | Original data, downsampled to 5m after rollover |
| **Warm** | 4-8 days | 15 minutes | 4 days | Second downsampling tier |
| **Cold** | 8-12 days | 60 minutes | 4 days | Third downsampling tier |
| **Delete** | >12 days | - | - | Data is deleted |

## Policies

### 1. system-metrics.ilm.json
Applies to system metrics data streams:
- `metrics-system.cpu-*`
- `metrics-system.memory-*`
- `metrics-system.network-*`
- `metrics-system.diskio-*`
- `metrics-system.load-*`

### 2. docker-metrics.ilm.json
Applies to docker metrics data streams:
- `metrics-docker.cpu-*`
- `metrics-docker.memory-*`
- `metrics-docker.network-*`

### 3. spark-gc.ilm.json
Applies to Spark GC metrics:
- `logs-spark_gc-*`

### 4. spark-logs-metrics.ilm.json
Applies to Spark log count metrics:
- `metrics-spark-logs-*`

## Applying Policies

### Automatic (Recommended): Using init-index.sh

The ILM policies are automatically created when you run the initialization script:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin
./init-index.sh
```

This script creates all downsampling ILM policies as part of STEP 10.

### Manual: Using apply-ilm-policies.sh

If you need to apply policies independently or update them:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/system-metrics
./apply-ilm-policies.sh
```

### Manual: Using esapi directly

```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch

# Create/update the ILM policies
esapi PUT _ilm/policy/system-metrics-downsampled system-metrics/system-metrics.ilm.json
esapi PUT _ilm/policy/docker-metrics-downsampled system-metrics/docker-metrics.ilm.json
esapi PUT _ilm/policy/spark-gc-downsampled system-metrics/spark-gc.ilm.json
esapi PUT _ilm/policy/spark-logs-metrics-downsampled system-metrics/spark-logs-metrics.ilm.json
```

## Attaching Policies to Data Streams

After creating the policies, you need to attach them to existing data streams or index templates.

### Automatic: Using attach-policies-to-datastreams.sh

The easiest way to attach policies to all relevant data streams:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/system-metrics
./attach-policies-to-datastreams.sh
```

This script will:
- Check if each data stream exists
- Attach the appropriate downsampling policy
- Provide verification commands

### Manual: Using esapi

For individual data streams:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin

# System metrics
./esapi PUT 'metrics-system.cpu-default/_settings' -d '{"index.lifecycle.name":"system-metrics-downsampled"}'
./esapi PUT 'metrics-system.memory-default/_settings' -d '{"index.lifecycle.name":"system-metrics-downsampled"}'
./esapi PUT 'metrics-system.network-default/_settings' -d '{"index.lifecycle.name":"system-metrics-downsampled"}'
./esapi PUT 'metrics-system.diskio-default/_settings' -d '{"index.lifecycle.name":"system-metrics-downsampled"}'
./esapi PUT 'metrics-system.load-default/_settings' -d '{"index.lifecycle.name":"system-metrics-downsampled"}'

# Docker metrics
./esapi PUT 'metrics-docker.cpu-default/_settings' -d '{"index.lifecycle.name":"docker-metrics-downsampled"}'
./esapi PUT 'metrics-docker.memory-default/_settings' -d '{"index.lifecycle.name":"docker-metrics-downsampled"}'
./esapi PUT 'metrics-docker.network-default/_settings' -d '{"index.lifecycle.name":"docker-metrics-downsampled"}'

# Spark GC
./esapi PUT 'logs-spark_gc-default/_settings' -d '{"index.lifecycle.name":"spark-gc-downsampled"}'

# Spark log metrics
./esapi PUT 'metrics-spark-logs-default/_settings' -d '{"index.lifecycle.name":"spark-logs-metrics-downsampled"}'
```

### Manual: Using Kibana Dev Tools

```json
PUT metrics-system.cpu-default/_settings
{"index.lifecycle.name": "system-metrics-downsampled"}

PUT metrics-system.memory-default/_settings
{"index.lifecycle.name": "system-metrics-downsampled"}

# ... (repeat for all data streams)
```

## Time Series Data Stream (TSDS) Requirements

For downsampling to work properly, data streams must be configured as Time Series Data Streams (TSDS). Key requirements:

1. **Time field**: Must have a `@timestamp` field
2. **Dimensions**: Fields that identify unique time series (e.g., `host.name`, `container.id`)
3. **Metrics**: Numeric fields with proper metric types (gauge, counter, etc.)

## Monitoring

Check ILM execution:

```bash
# View ILM explain for a data stream
GET metrics-system.cpu-default/_ilm/explain

# Check policy status
GET _ilm/policy/system-metrics
```

## Configuration Variables

Retention periods are defined in `variables.yaml`:
- `ES_RETENTION_BASE`: 2d (Hot phase)
- `ES_RETENTION_5MIN`: 4d (Warm phase cumulative)
- `ES_RETENTION_15MIN`: 8d (Cold phase cumulative)
- `ES_RETENTION_60MIN`: 12d (Frozen phase cumulative)

## Dashboard Integration

The "Spark System Metrics" dashboard includes a granularity dropdown that automatically queries the appropriate downsampled indices based on the selected time range and granularity.

## Notes

- Downsampling is a one-way operation and cannot be reversed
- Once data is downsampled, the original high-resolution data is removed
- Ensure your queries handle downsampled data appropriately (some aggregations may not work)
- The base sampling rate for metrics should be 30 seconds as per Elastic recommendations

