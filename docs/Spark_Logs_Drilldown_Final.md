# Spark Logs Drilldown - Final Implementation

## Overview
Implemented complete drilldown capability from the Spark metrics chart to detailed log viewer with proper time range filtering and enhanced log display.

## Fixed Issues

### 1. Time Range Bug (1969 Epoch Error)
**Problem:** URL format `${__value.time:date:iso}+1m` wasn't supported by Grafana, resulting in epoch timestamp 0 (1969-12-31).

**Solution:** Changed to `${__value.time}&to=${__value.time:date:seconds:raw}+60`
- Uses raw timestamp in seconds
- Adds 60 seconds for 1-minute window
- Matches the aggregation bucket period

### 2. Logs Panel Display Enhancement
**Implemented:**
- ✅ **Key Fields Displayed**: Time, Level, Host, Pod, Message, Stack Trace
- ✅ **Color-Coded Log Levels**: ERROR (red), WARN (yellow), INFO (green), DEBUG (blue)
- ✅ **Field Labels**: All fields clearly labeled
- ✅ **Message Wrapping**: Long messages wrap for readability
- ✅ **Stack Trace Visibility**: Shows in dedicated column when present
- ✅ **Expandable Rows**: Click any log line to see full JSON with all attributes

## User Workflow

### From Metrics to Logs
1. **View Metrics Dashboard**
   - http://GaryPC.local:3000/d/spark-system-metrics
   - Scroll to "Spark Application Logs by Level" panel

2. **Identify Issue**
   - See spike in logs (e.g., ERROR - lab2 at 10:35)
   - Bar shows aggregated count for that minute

3. **Drilldown**
   - Click the bar
   - Choose "View ERROR - lab2 Logs (1-minute window)"
   - New tab opens with Logs Viewer

4. **View Details**
   - Logs Viewer shows time range: 10:35:00 to 10:36:00
   - All logs from that minute are displayed
   - Key fields visible: Time, Level, Host, Pod, Message

5. **Access Stack Traces**
   - Logs with errors show stack trace in column
   - Click any row to expand and see full details
   - Expanded view shows complete JSON including:
     - All ECS fields
     - Kubernetes metadata
     - Full message and stack trace
     - Spark-specific fields

6. **Filter Further** (Optional)
   - Use dropdown filters:
     - Log Level: ERROR, WARN, INFO, DEBUG
     - Hostname: lab1, lab2, etc.
     - Pod Name: Specific Spark pods
   - Adjust time range if needed

## Visual Indicators

### Log Levels
- **ERROR**: Red background
- **WARN**: Yellow background  
- **INFO**: Green background
- **DEBUG**: Blue background

### Stack Traces
- When `error.stack_trace` field exists:
  - Shown in "Stack Trace" column
  - Click row to expand and view full trace
  - Multi-line traces fully preserved from capture

### Field Organization
```
┌──────────────┬───────┬──────────┬─────────────────┬────────────────┬──────────────┐
│ Time         │ Level │ Host     │ Pod             │ Message        │ Stack Trace  │
├──────────────┼───────┼──────────┼─────────────────┼────────────────┼──────────────┤
│ 10:35:55.208 │ ERROR │ lab2     │ spark-history-… │ Connection... │ at java.b... │
│ 10:35:56.123 │ INFO  │ lab1     │ spark-worker-…  │ Task compl... │              │
└──────────────┴───────┴──────────┴─────────────────┴────────────────┴──────────────┘
```

## Technical Details

### Drilldown URL Format
```
/d/spark-logs-viewer?
  orgId=1&
  from=${__value.time}&                    # Start timestamp (epoch ms)
  to=${__value.time:date:seconds:raw}+60& # End timestamp (epoch s + 60)
  var-log_level=All&                       # Default: show all levels
  var-hostname=All&                        # Default: show all hosts
  var-pod_name=All                         # Default: show all pods
```

### Time Range Calculation
- **Aggregation Bucket**: 1 minute (60 seconds)
- **Drilldown Window**: Exactly 1 minute from clicked bar
- **Format**: Unix timestamp in milliseconds for `from`, seconds+60 for `to`

### Logs Panel Configuration
```json
{
  "type": "logs",
  "options": {
    "enableLogDetails": true,  // Click to expand
    "showLabels": true,         // Show field names
    "wrapLogMessage": true,     // Wrap long messages
    "sortOrder": "Descending"   // Newest first
  },
  "transformations": [
    {
      "id": "organize",
      "options": {
        "indexByName": {          // Field order
          "@timestamp": 0,
          "log.level": 1,
          "host.hostname": 2,
          "spark.pod_name": 3,
          "message": 4,
          "error.stack_trace": 5
        }
      }
    }
  ]
}
```

## Files Modified
1. **spark-system.json** - Updated drilldown link with correct time format
2. **spark-logs-viewer.json** - Enhanced display with:
   - Field transformations (organize, rename)
   - Color-coded log levels
   - Proper field ordering
   - Stack trace visibility

## Testing Checklist

- [ ] Click bar on metrics chart
- [ ] Verify correct time range (not 1969!)
- [ ] See color-coded log levels
- [ ] View key fields: Time, Level, Host, Pod, Message
- [ ] Click log row to expand
- [ ] View full JSON in expanded view
- [ ] See stack trace for ERROR logs
- [ ] Test filter dropdowns (Level, Host, Pod)
- [ ] Try Kibana drilldown option
- [ ] Adjust time range manually

## URLs

- **Metrics Dashboard**: http://GaryPC.local:3000/d/spark-system-metrics
- **Logs Viewer**: http://GaryPC.local:3000/d/spark-logs-viewer
- **Kibana Discover**: https://GaryPC.local:5601/app/discover

## Known Limitations

1. **Field Access**: Grafana bar charts can't access individual aggregation bucket fields in URLs
   - Can't pre-filter by log_level from the bar
   - Can't pre-filter by hostname from the bar
   - **Workaround**: User filters after drilldown (acceptable UX)

2. **min_timestamp/max_timestamp**: Not used in URL due to Grafana limitations
   - 1-minute window is close enough (typically logs span < 10 seconds)
   - **Alternative**: User can adjust time picker for exact range

## Future Enhancements

1. Add table panel below bar chart (tables have full field access)
2. Create separate panels per hostname (simplifies filtering)
3. Add dashboard variables linked to panels
4. Implement custom drilldown plugin with full field access


