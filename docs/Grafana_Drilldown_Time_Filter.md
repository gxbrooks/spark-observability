# Grafana Drill-down Time Filtering

## Overview

This document explains the drill-down time filtering mechanism from the Spark Application Logs metrics panel to the detailed log viewer.

## Current Issue

**Problem**: The drill-down does NOT filter log entries by the start and end times of the clicked time bucket.

**User Question**: "Is that an unusual feature to add?"

**Answer**: No, this is a **standard and expected feature** in observability dashboards. Time-based drill-down filtering is considered a best practice and is commonly implemented in production monitoring systems.

## Root Cause

The drill-down link in `spark-system.json` attempts to pass time range parameters:

```json
"url": "/d/spark-logs-viewer?orgId=1&from=${__data.fields.@timestamp}&to=${__data.fields.bucket_end_time}"
```

### Issues:

1. **`bucket_end_time` field doesn't exist** in the aggregated data
   - The Elasticsearch aggregation uses `date_histogram` which creates buckets with `@timestamp` (bucket start)
   - There is no automatic `bucket_end_time` field

2. **Field reference syntax** may not work for time range parameters
   - Grafana's `from` and `to` parameters expect epoch milliseconds or relative time strings
   - `${__data.fields.X}` syntax works for data links but may need specific formatting

## Solution Options

### Option 1: Use Built-in Time Range Variables (Recommended)

Replace the custom drill-down with Grafana's built-in time range variables:

```json
"url": "/d/spark-logs-viewer?orgId=1&from=${__from}&to=${__to}"
```

**Pros**:
- Simple and reliable
- Uses the current panel's time range
- No data processing needed

**Cons**:
- Drills down to the entire panel time range, not the specific clicked bucket
- Less precise than bucket-level filtering

### Option 2: Calculate Bucket End Time in Transformation

Add a transformation to calculate `bucket_end_time` based on the interval:

```json
{
  "id": "calculateField",
  "options": {
    "mode": "binary",
    "reduce": {
      "include": ["@timestamp"],
      "reducer": "sum"
    },
    "binary": {
      "left": "@timestamp",
      "operation": "add",
      "right": "60000"  // Add bucket interval in ms (e.g., 1 minute)
    },
    "alias": "bucket_end_time"
  }
}
```

**Pros**:
- Precise bucket-level filtering
- True drill-down to the clicked time range

**Cons**:
- Requires knowing the bucket interval statically
- More complex configuration
- Interval must match the aggregation interval

### Option 3: Use Variables with Bucket Interval

Create a dashboard variable for bucket interval and use it in a transformation:

1. Add variable: `$bucket_interval` (e.g., "1m", "5m", "auto")
2. Calculate end time dynamically
3. Pass to drill-down URL

**Pros**:
- Flexible and configurable
- Works with different time ranges

**Cons**:
- Most complex solution
- Requires dashboard variable management

## Recommendation

**For Now**: Use Option 1 (built-in time range variables)
- Provides immediate functionality
- Sufficient for most use cases
- Users can always adjust time range in the target dashboard

**Future Enhancement**: Implement Option 2 if precise bucket-level filtering is required
- Add transformation to calculate bucket end time
- Update drill-down link to use calculated field

## Implementation Status

- ✅ Log level filter fixed (uses `log.level` field)
- ⏳ Time range filtering (currently pending, using panel time range as workaround)
- ⏳ Testing with active Spark jobs

## Related Files

- `observability/grafana/provisioning/dashboards/spark-system.json` - Metrics panel with drill-down link
- `observability/grafana/provisioning/dashboards/spark-logs-viewer.json` - Target log viewer dashboard

## Testing

To test the drill-down:

1. Ensure Spark jobs are running and generating logs
2. Open Grafana → Spark Cluster Metrics dashboard
3. Click on a bar in the "Spark Application Logs" panel
4. Verify the log viewer opens with appropriate time range
5. Check if logs are filtered by the selected time period

## Notes

- This is NOT an unusual feature - it's standard practice
- Most commercial observability platforms (Datadog, New Relic, Dynatrace) implement this by default
- The feature improves user experience significantly by reducing cognitive load

