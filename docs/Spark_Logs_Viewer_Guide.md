# Spark Application Logs Viewer - User Guide

## Overview

The Spark Application Logs Viewer provides a table-based interface for viewing and analyzing Spark application logs collected from all cluster components.

**URL:** http://Lab3.lan:3000/d/spark-logs-viewer

## Table Columns

The viewer displays 6 columns in this order:

| Column | Width | Description |
|--------|-------|-------------|
| **Time** | 180px | Log entry timestamp (@timestamp) |
| **Level** | 100px | Log level (ERROR, WARN, INFO, DEBUG) - Bold colored text |
| **Host** | 80px | Hostname where log originated (lab1, lab2, etc.) |
| **Pod** | 250px | Kubernetes pod name (spark-master, spark-worker, etc.) |
| **Message** | 500px | Clean log message (no stack traces) |
| **Stack Trace** | 150px | Java stack trace (when present, for errors/warnings) |

## UI Controls

### 1. View Full JSON Details
**Method:** Click the **Time** cell in any row

**What It Does:**
- Shows a link: "View Full JSON Details"
- Clicking opens a modal/dialog with the complete log entry
- Displays all fields in JSON format including:
  - All ECS fields
  - All Kubernetes metadata
  - Complete message with stack trace
  - Agent information
  - Everything Elasticsearch captured

**Best For:**
- Debugging specific log entries
- Seeing all available metadata
- Copying complete log data

### 2. View Stack Trace
**Method:** Check the **Stack Trace** column

**What It Shows:**
- If the log has a stack trace: Shows preview
- Click the cell to expand inline
- Uses `json-view` display mode for readable formatting

**When Available:**
- Typically on ERROR and WARN logs
- When Java exceptions occur
- Multi-line traces fully captured

**Best For:**
- Quickly scanning for errors with stack traces
- Identifying exception types
- Reading full error context

### 3. Expand Row for All Fields
**Method:** Click anywhere on a row (besides specific cell links)

**What It Does:**
- Row expands below
- Shows all fields in a structured view
- Includes both displayed and hidden fields
- Can scroll through all metadata

**Best For:**
- Seeing everything at once
- Comparing multiple field values
- Finding specific metadata fields

## Log Level Visual Indicators

The **Level** column uses bold colored text for quick identification:

- **ERROR**: Bold red text
- **WARN**: Bold yellow text  
- **INFO**: Bold green text
- **DEBUG**: Bold blue text

**Not garish background colors** - just the text is colored and bolded.

## Filtering

The dashboard includes three filter dropdowns at the top:

### Log Level Filter
- Multi-select dropdown
- Options: ERROR, WARN, INFO, DEBUG
- Default: All selected
- Usage: Uncheck levels you don't want to see

### Hostname Filter
- Multi-select dropdown
- Options: lab1, lab2, etc. (auto-populated from data)
- Default: All selected
- Usage: Select specific hosts to view

### Pod Name Filter
- Multi-select dropdown
- Options: All Spark pods (auto-populated from data)
- Default: All selected
- Usage: Filter to specific pods (e.g., only spark-history)

## Time Range

**Time Picker:** Top-right corner

- Default: Last 1 hour
- Adjustable: 5m, 15m, 1h, 6h, 24h, 7d, etc.
- Custom: Click to set exact from/to timestamps

## Drilldown from Metrics

You can navigate to this viewer from the Spark Cluster Metrics dashboard:

1. Go to: http://Lab3.lan:3000/d/spark-system-metrics
2. Scroll to "Spark Application Logs by Level" panel
3. Click any bar on the chart
4. Select "View ... Logs (1-minute window)"
5. Logs Viewer opens with time range set to that 1-minute bucket

The time range is automatically set to show logs from the clicked time period.

## Column Sorting

Click any column header to sort:
- **Time**: Sort chronologically (newest/oldest first)
- **Level**: Sort by severity
- **Host**: Sort alphabetically by hostname
- **Pod**: Sort alphabetically by pod name
- **Message**: Sort alphabetically by message text

Click again to reverse sort order.

## Row Actions

### Standard Table Interactions:
1. **Single click row** → Expands to show all fields
2. **Click Time cell** → Link to view full JSON
3. **Click Stack Trace cell** → Expands inline to show full trace
4. **Hover over cell** → Shows tooltip (if truncated)

### Copy Data:
- Right-click any cell → Browser context menu → Copy
- Expand row → Copy from JSON view
- Select text in Message/Stack Trace cells → Copy

## Technical Details

### Data Source
- **Type:** Elasticsearch
- **Index:** logs-spark-default
- **Query Type:** raw_data
- **Size:** 500 rows per query
- **Refresh:** 30 seconds (auto-refresh)

### Field Mapping
- `@timestamp` → Time
- `log.level` → Level
- `host.hostname` → Host
- `spark.pod_name` → Pod
- `log_message` → Message (parsed, clean)
- `error.stack_trace` → Stack Trace (when present)

### Hidden Fields (excluded from table)
- All agent metadata (agent.id, agent.version, etc.)
- All ECS metadata (ecs.version, etc.)
- All data_stream fields
- All host OS details (except hostname)
- Spark class and component
- Log file paths and offsets
- Raw `message` field (use `log_message` instead)

## Troubleshooting

### No Data Showing
**Check:**
1. Time range includes data (try "Last 24 hours")
2. Filters aren't too restrictive (set all to "All")
3. Elasticsearch is running: `curl https://Lab3.lan:9200/_cluster/health`

### Columns Not Appearing
**Check:**
1. Browser cache - Hard refresh (Ctrl+Shift+R)
2. Dashboard version - Should show transformations in edit mode
3. Query type - Should be "raw_data" not "raw_document"

### Stack Trace Not Showing
**Check:**
1. Filter to ERROR or WARN logs (most likely to have stack traces)
2. Click the Stack Trace cell to expand it
3. Or expand the row to see error.stack_trace in JSON

### Level Colors Not Showing
**Check:**
1. Mappings are configured (edit panel → Field overrides → Level)
2. displayMode is "color-text" not "color-background"
3. Hard refresh browser

## Related Dashboards

- **Spark Cluster Metrics**: http://Lab3.lan:3000/d/spark-system-metrics
  - Overview of cluster health
  - Log counts by level (drilldown to this viewer)
  - GC metrics, system metrics

- **Spark GC Analysis**: http://Lab3.lan:3000/d/spark-gc-analysis
  - Garbage collection metrics
  - GC pause times
  - Memory usage

## Configuration Files

- **Dashboard:** `observability/grafana/provisioning/dashboards/spark-logs-viewer.json`
- **Index Template:** `observability/elasticsearch/spark-logs/logs-spark-default.template.json`
- **Ingest Pipeline:** `observability/elasticsearch/spark-logs/spark-logs-ingest-pipeline.json`
- **Data View:** `observability/elasticsearch/spark-logs/spark-logs.dataview.json`


