# Spark System Metrics Dashboard

## Overview

The **Spark System Metrics** dashboard provides an aggregated view of system metrics across all Spark cluster nodes. Unlike the "Spark Cluster Metrics" dashboard which shows per-node metrics, this dashboard sums metrics across the cluster to provide a holistic system view.

## Features

### Aggregated Metrics
All metrics are aggregated (summed or averaged) across all cluster nodes:
- **CPU Utilization**: Total CPU usage across all nodes
- **Memory Utilization**: Average memory usage across all nodes
- **Network Traffic**: Total network I/O across all nodes
- **Disk I/O**: Total disk read/write rates across all nodes
- **System Load**: Total system load across all nodes
- **Page Faults**: Total page fault rates across all nodes
- **GC Metrics**: Total garbage collection pause time and heap reclaimed
- **Log Counts**: Aggregated log entry counts by level

### Downsampling Support

The dashboard supports multiple granularities through Elasticsearch's automatic downsampling:

| Granularity | Sampling Interval | Use Case | Data Age |
|-------------|-------------------|----------|----------|
| **Default (30s)** | 30 seconds | Recent data, detailed analysis | 0-2 days |
| **5 Minutes** | 5 minutes | Short-term trends | 2-4 days |
| **15 Minutes** | 15 minutes | Medium-term trends | 4-8 days |
| **60 Minutes** | 1 hour | Long-term trends | 8-12 days |

### Granularity Dropdown

The dashboard includes a **Granularity** dropdown at the top. While Elasticsearch automatically uses the appropriate downsampled data based on data age, this dropdown serves as a:
- User reference for the expected data granularity
- Guide for interpretation of the displayed metrics
- Future enhancement point for explicit index selection

## Panels

### 1. Total System CPU Utilization %
- **Metric**: Sum of `system.cpu.total.pct` across all hosts
- **Type**: Time series
- **Legend Stats**: Mean, Max, Last value

### 2. Average System Memory Utilization %
- **Metric**: Average of `system.memory.used.pct` across all hosts
- **Type**: Time series
- **Legend Stats**: Mean, Max, Last value

### 3. Total Network Byte Rate (In/Out)
- **Metrics**: 
  - Network In: Derivative of `system.network.in.bytes`
  - Network Out: Derivative of `system.network.out.bytes`
- **Type**: Time series
- **Note**: Excludes loopback interface

### 4. Total Disk I/O Rate (Read/Write)
- **Metrics**:
  - Disk Read: Derivative of `system.diskio.read.bytes`
  - Disk Write: Derivative of `system.diskio.write.bytes`
- **Type**: Time series

### 5. Total System Load Average
- **Metrics**: 
  - Sum of `system.load.1` (1-minute load)
  - Sum of `system.load.5` (5-minute load)
  - Sum of `system.load.15` (15-minute load)
- **Type**: Time series
- **Legend Stats**: Mean, Max, Last value

### 6. Total Page Fault Rate
- **Metrics**:
  - Total Page Faults: Sum of `system.memory.page_stats.pgfault.rate`
  - Total Major Faults: Sum of `system.memory.page_stats.pgmajfault.rate`
- **Type**: Time series

### 7. Total GC Pause Time
- **Metric**: Sum of `gc.paused.millis` from Spark GC events
- **Type**: Time series
- **Unit**: Milliseconds
- **Legend Stats**: Mean, Max, Sum

### 8. Total GC Heap Reclaimed
- **Metric**: Sum of `gc.paused.reclaimed` from Spark GC events
- **Type**: Time series
- **Unit**: Kilobytes (displayed as deckbytes in Grafana)
- **Legend Stats**: Mean, Max, Sum

### 9. Total Spark Application Logs by Level
- **Metric**: Sum of `log_count` by `log_level`
- **Type**: Stacked bar chart
- **Color Coding**:
  - ERROR: Red
  - WARN: Yellow
  - INFO: Green
  - DEBUG: Blue
- **Interactive**: Click to view detailed logs in Spark Logs Viewer
- **Legend Stats**: Sum

## Data Sources

The dashboard queries the following Elasticsearch indices:
- `metrics-system.cpu-default`
- `metrics-system.memory-default`
- `metrics-system.network-default`
- `metrics-system.diskio-default`
- `metrics-system.load-default`
- `logs-spark_gc-default`
- `metrics-spark-logs-default`

**Note**: With downsampling enabled, Elasticsearch automatically uses the appropriate downsampled data (5m, 15m, 60m) based on the data age while maintaining these same index patterns.

## Automatic Downsampling

When the ILM policies are applied (see `/observability/elasticsearch/system-metrics/README.md`), Elasticsearch automatically:
1. Keeps high-resolution (30s) data for 2 days in the **hot** tier
2. Downsamples to 5-minute intervals and moves to **warm** tier at 2 days
3. Downsamples to 15-minute intervals and moves to **cold** tier at 4 days
4. Downsamples to 60-minute intervals and moves to **frozen** tier at 8 days
5. Deletes data older than 12 days

The dashboard queries remain the same; Elasticsearch handles the complexity of selecting the appropriate downsampled data.

## Usage

### Viewing Recent Activity
- Set time range to "Last 6 hours" or "Last 24 hours"
- Expect 30-second resolution data
- Use "Default (30s)" granularity selection

### Viewing Short-term Trends
- Set time range to "Last 2 days" to "Last 4 days"
- Data will be at 5-minute resolution
- Use "5 Minutes" granularity selection

### Viewing Medium-term Trends
- Set time range to "Last 4 days" to "Last 8 days"
- Data will be at 15-minute resolution
- Use "15 Minutes" granularity selection

### Viewing Long-term Trends
- Set time range to "Last 8 days" to "Last 12 days"
- Data will be at 60-minute resolution
- Use "60 Minutes" granularity selection

## Refresh Rate

The dashboard automatically refreshes every 30 seconds to show near-real-time data.

## Comparison with Spark Cluster Metrics

| Feature | Spark Cluster Metrics | Spark System Metrics (Aggregated) |
|---------|----------------------|-----------------------------------|
| **View** | Per-node breakdown | Cluster-wide totals |
| **CPU** | By host | Total across cluster |
| **Memory** | By host | Average across cluster |
| **Network** | By host | Total across cluster |
| **Use Case** | Identify problem nodes | Overall cluster health |
| **Downsampling** | No | Yes, automatic |
| **Data Retention** | Depends on ES config | Up to 12 days with downsampling |

## Links to Related Dashboards

- **Spark Cluster Metrics**: Per-node system metrics (use for troubleshooting specific nodes)
- **Spark Logs Viewer**: Click on log count bars to view detailed logs
- **Spark GC Analysis**: Detailed garbage collection analysis

## Variables

### Granularity
- **Type**: Dropdown (single select)
- **Options**: Default (30s), 5 Minutes, 15 Minutes, 60 Minutes
- **Purpose**: User reference for expected data resolution
- **Hidden Variables**: 
  - `index_suffix`: Maps to index naming (future use)
  - `derivative_unit`: Used for rate calculations

## Troubleshooting

### No data showing
1. Verify Elastic Agent is collecting system metrics on all nodes
2. Check that data streams exist: `GET _data_stream/metrics-system.*-default`
3. Verify ILM policies are applied: `GET metrics-system.cpu-default/_ilm/explain`

### Aggregations seem incorrect
1. Ensure all cluster nodes are reporting metrics
2. Check for missing hosts: compare with "Spark Cluster Metrics" dashboard
3. Verify time synchronization across nodes (NTP)

### Downsampled data not appearing
1. Wait for ILM to execute (check `min_age` in policies)
2. Verify ILM is running: `GET _ilm/status`
3. Check ILM history: `GET .ds-metrics-system.cpu-default-*/_ilm/explain`

## Configuration

Dashboard configuration is provisioned via Grafana's provisioning system:
- **Location**: `/observability/grafana/provisioning/dashboards/spark-system-metrics-aggregated.json`
- **UID**: `spark-system-metrics-aggregated`
- **Schema Version**: 39 (Grafana 11.3.0+)

## Future Enhancements

1. **Dynamic Index Selection**: Implement explicit index pattern selection based on granularity dropdown
2. **Kubernetes Metrics**: Add aggregated K8s pod/container metrics
3. **Alerting**: Configure alerts for aggregate threshold violations
4. **Cost Analysis**: Display storage costs for different retention tiers
5. **Capacity Planning**: Predictive metrics based on historical trends
6. **Multi-Cluster**: Support for multiple Spark clusters in single view

## Related Documentation

- [System Metrics ILM Policies](/observability/elasticsearch/system-metrics/README.md)
- [Variables Configuration](/vars/variables.yaml) - Retention policy definitions
- [Grafana Dashboard Provisioning](/observability/grafana/README.md)

