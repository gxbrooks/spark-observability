# Grafana Legend Statistics Guidelines

## Overview

This document provides guidelines for when to display statistical calculations (min, max, mean, avg, sum, last, etc.) in Grafana panel legends.

## General Principle

**Legend statistics should enhance understanding, not clutter the display.** For time-series metrics, especially rates and instantaneous values, statistical summaries in legends are often redundant or misleading.

## Guidelines by Metric Type

### 1. Rate Metrics (Network I/O, Disk I/O, Throughput)
**Recommendation: NO legend statistics**

**Rationale:**
- Rate metrics represent instantaneous values at each time point
- Mean/max values across the time range don't provide actionable insights
- The time-series visualization itself shows trends and patterns
- Legend statistics can be misleading (e.g., a brief spike creates a high "max" that doesn't reflect normal operation)

**Examples:**
- Network byte rate (bytes/sec)
- Disk I/O rate (bytes/sec)
- Request rate (requests/sec)
- Message throughput (messages/sec)

**Configuration:**
```json
"legend": {
  "displayMode": "list",
  "calcs": []
}
```

### 2. Percentage Metrics (CPU, Memory, Utilization)
**Recommendation: OPTIONAL - Use sparingly**

**Rationale:**
- Percentages are bounded (0-100%), making statistics more meaningful
- Mean and max can help identify sustained vs. peak usage
- However, the time-series visualization is usually sufficient

**When to include:**
- If the dashboard is used for capacity planning
- If users need quick reference for typical vs. peak values
- If the metric is critical for alerting thresholds

**When to exclude:**
- If the dashboard is primarily for real-time monitoring
- If the visualization clearly shows the range

**Examples:**
- CPU utilization %
- Memory utilization %
- Disk usage %
- Network interface utilization %

**Configuration (if including):**
```json
"legend": {
  "displayMode": "list",
  "calcs": ["mean", "max", "last"]
}
```

### 3. Cumulative Metrics (Counters, Totals)
**Recommendation: NO legend statistics**

**Rationale:**
- Cumulative metrics are typically displayed as rates (derivatives)
- Raw cumulative values are rarely useful in legends
- The current value is usually what matters

**Examples:**
- Total bytes transferred (displayed as rate)
- Total requests processed (displayed as rate)
- Total errors (displayed as rate)

### 4. Aggregated Metrics (Sums Across Hosts)
**Recommendation: NO legend statistics**

**Rationale:**
- Aggregated metrics already represent cluster-wide totals
- Statistical summaries add little value
- The visualization shows the aggregated trend clearly

**Examples:**
- Total network I/O across all hosts
- Total disk I/O across all hosts
- Total active jobs across cluster

### 5. Count Metrics (Active Jobs, Log Counts)
**Recommendation: NO legend statistics**

**Rationale:**
- Counts are discrete values that change over time
- Mean/max don't provide meaningful insights
- The time-series shows the actual count at each point

**Examples:**
- Active Spark jobs
- Log entries by level
- Active connections

### 6. Gauge Metrics (Current State)
**Recommendation: NO legend statistics**

**Rationale:**
- Gauges represent current state, not historical trends
- Statistics are redundant with the current value display

**Examples:**
- Current queue depth
- Current active threads
- Current heap usage

## Dashboard-Specific Guidelines

### Spark System Metrics (Aggregated Dashboard)
**Policy: NO legend statistics for all panels**

**Rationale:**
- This dashboard focuses on cluster-wide aggregated metrics
- All metrics are either rates, counts, or percentages
- Clean legends improve readability and reduce cognitive load
- Users can hover over data points for exact values

**Implementation:**
All panels should use:
```json
"legend": {
  "displayMode": "list",
  "calcs": []
}
```

### Spark Cluster Metrics (Per-Node Dashboard)
**Policy: OPTIONAL - Use for percentage metrics only**

**Rationale:**
- Per-node dashboards may benefit from statistics for capacity planning
- Percentage metrics (CPU, memory) can show typical vs. peak usage per node
- Rate metrics should still exclude statistics

## Best Practices

1. **Default to Empty**: Start with `calcs: []` and only add statistics if they provide clear value
2. **Consistency**: Use the same legend configuration across similar metric types
3. **Tooltip Over Statistics**: Prefer tooltips (hover) for exact values rather than legend statistics
4. **Document Decisions**: If statistics are included, document why in panel descriptions
5. **User Testing**: Validate that legend statistics actually help users make decisions

## When Statistics ARE Useful

Legend statistics are appropriate when:
- **Capacity Planning**: Mean values help estimate typical resource needs
- **Threshold Monitoring**: Max values help identify peak usage patterns
- **Summary Dashboards**: High-level dashboards that show many metrics at once
- **Alerting Context**: Statistics help set meaningful alert thresholds

## Implementation Checklist

When creating or updating a dashboard panel:

- [ ] Identify the metric type (rate, percentage, count, etc.)
- [ ] Apply the appropriate guideline
- [ ] Verify legend statistics add value (if included)
- [ ] Ensure consistency with similar panels
- [ ] Test that the legend is readable and not cluttered

## Examples

### Good: Rate Metric (No Statistics)
```json
{
  "title": "Total Network Byte Rate (In/Out)",
  "options": {
    "legend": {
      "displayMode": "list",
      "calcs": []
    }
  }
}
```

### Acceptable: Percentage Metric (With Statistics)
```json
{
  "title": "Average CPU Utilization %",
  "options": {
    "legend": {
      "displayMode": "list",
      "calcs": ["mean", "max", "last"]
    }
  }
}
```

### Avoid: Rate Metric (With Statistics)
```json
{
  "title": "Network Byte Rate",
  "options": {
    "legend": {
      "calcs": ["mean", "max"]  // ❌ Not recommended for rates
    }
  }
}
```

## References

- [Grafana Legend Documentation](https://grafana.com/docs/grafana/latest/panels/visualizations/time-series/#legend)
- [Time-Series Best Practices](https://grafana.com/docs/grafana/latest/best-practices/time-series-panels/)

