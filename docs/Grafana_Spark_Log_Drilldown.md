# Grafana Spark Log Metrics Drilldown

## Overview

The "Spark Application Logs by Level" panel in the Spark System Metrics dashboard now supports drilldown capability. Users can click on any bar in the chart to view the detailed log entries that contributed to that aggregated count.

## Features

### Min/Max Timestamps
Each metrics bucket now captures:
- `min_timestamp`: Earliest log entry timestamp in the bucket
- `max_timestamp`: Latest log entry timestamp in the bucket

These timestamps define the exact time range of logs within each 1-minute aggregation bucket.

### Drilldown Options

When you click on a bar in the panel, you'll see two drilldown options:

#### 1. View Logs in Kibana
Opens Kibana Discover in a new tab with:
- Time range: Set to the bucket's `min_timestamp` and `max_timestamp`
- Filters applied:
  - `log.level`: Matches the selected log level (ERROR, INFO, WARN, etc.)
  - `host.hostname.keyword`: Matches the selected hostname (lab1, lab2, etc.)
- Index: `spark-logs`
- Sorted by: `@timestamp` descending

#### 2. View Logs in Grafana Explore
Opens Grafana Explore in a new tab with:
- Datasource: Elasticsearch (spark-elasticsearch)
- Time range: Set to the bucket's `min_timestamp` and `max_timestamp`  
- Query: `log.level:"<level>" AND host.hostname.keyword:"<hostname>"`
- View: Logs

## User Experience

### Basic Workflow
1. View the aggregated log counts by level and hostname in the bar chart
2. Identify a bucket of interest (e.g., a spike in ERROR logs)
3. Click on the bar
4. Choose "View Logs in Kibana" or "View Logs in Grafana Explore"
5. Review the actual log entries that contributed to that count

### Advanced Workflow
1. Use the Grafana time range picker to zoom into a specific time window
2. The chart updates to show log counts for that period
3. Click on specific bars to drilldown
4. The drilldown opens with the exact time range of that 1-minute bucket

## Technical Implementation

### Transform Aggregations
The `spark-log-metrics` transform includes three aggregations per bucket:
```json
{
  "aggregations": {
    "log_count": {
      "value_count": {"field": "@timestamp"}
    },
    "min_timestamp": {
      "min": {"field": "@timestamp"}
    },
    "max_timestamp": {
      "max": {"field": "@timestamp"}
    }
  }
}
```

### Grafana Data Links
Two data links are configured in the panel's field config:
- Kibana Discover URL with query parameters for time range and filters
- Grafana Explore URL with encoded query and time range

The links use Grafana variables to dynamically populate:
- `${__data.fields.log_level}`: The log level of the clicked bar
- `${__data.fields.hostname}`: The hostname of the clicked bar
- `${__data.fields.min_timestamp}`: Start of time range
- `${__data.fields.max_timestamp}`: End of time range

## Configuration Files

- **Transform**: `observability/elasticsearch/spark-logs/spark-log-metrics-transform.json`
- **Index Template**: `observability/elasticsearch/spark-logs/metrics-spark-logs.template.json`
- **Dashboard**: `observability/grafana/provisioning/dashboards/spark-system.json`

## Future Enhancements

Potential improvements:
1. Add support for drilling down to specific pod names
2. Include component filters (master, worker, executor, driver)
3. Add direct link to full stack traces for ERROR logs
4. Support for custom time range selection (click and drag on chart)
5. Add breadcrumb navigation to return from drilldown view


