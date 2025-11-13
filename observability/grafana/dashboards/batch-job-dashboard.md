# Batch Job Dashboard

**Dashboard Name**: Batch Job Dashboard  
**File**: `provisioning/dashboards/batch-job-dashboard4.json`  
**URL**: `http://garypc.local:3000/` (navigate via UI)

## Purpose

Monitors batch job processing metrics including job counts, execution times, resource usage, and failure rates.

## Data Sources

### Indices
- `batch-events-*`: Job lifecycle events
- `batch-metrics-*`: Job execution metrics
- `batch-traces-*`: Distributed tracing data

### Fields
- Job status (running, completed, failed)
- Execution duration
- Resource consumption
- Error messages and stack traces

## Panels

Details of specific panels in this dashboard are defined in the JSON configuration file. Key visualizations include:

- Active job counts
- Job completion rates
- Job duration histograms
- Resource utilization per job
- Failure tracking and error analysis

## Accessing

Navigate to the dashboard via Grafana's search or dashboard browser.

## Customization

This dashboard can be customized to match your specific batch job patterns and monitoring requirements. Export the JSON after modifications to persist changes.

## See Also

- [Grafana README](../README.md) - General Grafana documentation
- [Spark Cluster Metrics](./spark-system-metrics.md) - Infrastructure metrics

