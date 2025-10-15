# Derivative Metric Calculation in Grafana with Elasticsearch

## Best Practices for Rate Calculations and Time Series Visualization

When implementing rate calculations from cumulative counter metrics in Grafana:

### 1. Use Meaningful Field Names
- **Query Design**: Structure Elasticsearch queries with descriptive aggregation names that indicate their purpose
- **Alias Patterns**: Leverage Grafana's template variables like `{{term host.name}}` to create dynamic, readable labels
- **Clarity**: Labels should immediately convey what metric is being displayed (e.g., "lab1 In" vs "lab1 Derivative Max system.network.in.bytes")

### 2. Derive Rate Calculations Server-Side
- **Elasticsearch Derivatives**: Use Elasticsearch derivative aggregations for rate calculations rather than client-side transformations
- **Performance**: Server-side calculations handle counter resets automatically and are more efficient for large datasets
- **Reliability**: Elasticsearch's derivative aggregation includes built-in time normalization and null handling

### 3. Separate Inputs from Outputs in Time Series Graphs
- **Visual Distinction**: Use wave envelope visualization (inputs below x-axis, outputs above) for immediate pattern recognition
- **Separate Targets**: Split IN/OUT or Read/Write metrics into distinct query targets for clean aliasing
- **Scalability**: Design visualizations that automatically accommodate dynamic cluster membership without configuration changes

### 4. Prioritize Enterprise Scalability
- **Dynamic Host Discovery**: Use regex patterns and template variables instead of hardcoded host names
- **Minimal Maintenance**: Configuration should work with 2 hosts or 2000 hosts without modification
- **Automatic Adaptation**: New hosts should appear in dashboards automatically with correct labels and formatting

## Technical Implementation

### Why Grafana Requires Numeric Metric IDs

Grafana's Elasticsearch datasource has a specific implementation requirement for pipeline aggregations (like derivative and bucket_script):

**Numeric IDs are Required** because:
1. **Internal Reference Resolution**: Grafana's Elasticsearch query builder constructs `buckets_path` references by directly using the metric ID value
2. **Pipeline Aggregation Chain**: When a pipeline aggregation references another metric, Grafana expects the ID to be a simple numeric string that can be directly inserted into the Elasticsearch query
3. **Query Construction Logic**: The datasource code treats metric IDs as both:
   - Configuration identifiers within Grafana
   - Direct field references in the generated Elasticsearch query

**What Works:**
```json
{
  "id": "1",                    // Numeric string ID
  "type": "max",
  "field": "system.network.in.bytes"
},
{
  "id": "2",                    // Numeric string ID
  "type": "derivative",
  "field": "1",                 // References numeric ID
  "pipelineAgg": "1",           // References numeric ID
  "settings": {"unit": "10s"}
}
```

**What Doesn't Work:**
```json
{
  "id": "max_in_bytes",         // String ID
  "type": "max",
  "field": "system.network.in.bytes"
},
{
  "id": "in_rate",              // String ID
  "type": "derivative",
  "field": "max_in_bytes",      // String reference - fails
  "pipelineAgg": "max_in_bytes" // String reference - fails
}
```

**Result**: When using string IDs, the derivative aggregation returns no data (all nulls) because Grafana cannot correctly construct the `buckets_path` in the Elasticsearch query.

### Grafana Series Name Generation

Understanding how Grafana creates series names is critical for field overrides:

**Series Name Pattern:**
```
<terms_bucket_key> <AggregationType> <field_name>
```

**Examples:**
- Max aggregation on `system.network.in.bytes` with terms bucket `lab1`:
  - Series name: `"lab1 Max system.network.in.bytes"`
- Derivative of that max aggregation:
  - Series name: `"lab1 Derivative Max system.network.in.bytes"`
- Bucket script of that derivative:
  - Series name: `"lab1 Bucket script Derivative Max system.network.in.bytes"`

**Key Insight**: The series name is derived from the aggregation type and field name, NOT from the metric ID. Grafana traces back through pipeline aggregations to find the original field.

### Scalable Configuration Pattern

The following pattern achieves all best practices: meaningful names, server-side rate calculation, input/output separation, and enterprise scalability.

#### Step 1: Split Queries into Separate Targets

Create distinct targets for IN/OUT or Read/Write metrics:

**Target A - Input/Read (Negative for Wave Envelope):**
```json
{
  "datasource": {"type": "elasticsearch", "uid": "spark-elasticsearch"},
  "query": "_index:metrics-system.network-default AND system.network.name:(enp* OR ens*) AND NOT system.network.name:lo",
  "alias": "{{term host.name}} In",
  "metrics": [
    {
      "id": "1",
      "type": "max",
      "field": "system.network.in.bytes",
      "hide": true
    },
    {
      "id": "2",
      "type": "derivative",
      "field": "1",
      "pipelineAgg": "1",
      "settings": {"unit": "10s"},
      "hide": true
    },
    {
      "id": "3",
      "type": "bucket_script",
      "pipelineAgg": "2",
      "settings": {"script": "params._value * -1"},
      "pipelineVariables": [{"name": "_value", "pipelineAgg": "2"}]
    }
  ],
  "bucketAggs": [
    {
      "id": "4",
      "type": "terms",
      "field": "host.name",
      "settings": {"min_doc_count": "1", "order": "asc", "orderBy": "_key", "size": "10"}
    },
    {
      "id": "5",
      "type": "date_histogram",
      "field": "@timestamp",
      "settings": {"interval": "10s"}
    }
  ],
  "refId": "A",
  "timeField": "@timestamp"
}
```

**Target B - Output/Write (Positive):**
```json
{
  "datasource": {"type": "elasticsearch", "uid": "spark-elasticsearch"},
  "query": "_index:metrics-system.network-default AND system.network.name:(enp* OR ens*) AND NOT system.network.name:lo",
  "alias": "{{term host.name}} Out",
  "metrics": [
    {
      "id": "1",
      "type": "max",
      "field": "system.network.out.bytes",
      "hide": true
    },
    {
      "id": "2",
      "type": "derivative",
      "field": "1",
      "pipelineAgg": "1",
      "settings": {"unit": "10s"}
    }
  ],
  "bucketAggs": [
    {
      "id": "3",
      "type": "terms",
      "field": "host.name",
      "settings": {"min_doc_count": "1", "order": "asc", "orderBy": "_key", "size": "10"}
    },
    {
      "id": "4",
      "type": "date_histogram",
      "field": "@timestamp",
      "settings": {"interval": "10s"}
    }
  ],
  "refId": "B",
  "timeField": "@timestamp"
}
```

#### Step 2: Key Configuration Elements

**1. Numeric Metric IDs:**
- Use sequential numeric IDs: "1", "2", "3", etc.
- Required for pipeline aggregations to work correctly
- Grafana's Elasticsearch datasource limitation

**2. Alias Pattern with Template Variable:**
```json
"alias": "{{term host.name}} In"
```
- `{{term host.name}}` extracts the hostname from the terms aggregation bucket
- Dynamically creates clean labels: "lab1 In", "lab2 In", "prod-node-47 In"
- Works for any number of hosts automatically

**3. Bucket Script for Wave Envelope:**
```json
{
  "type": "bucket_script",
  "pipelineAgg": "2",
  "settings": {"script": "params._value * -1"},
  "pipelineVariables": [{"name": "_value", "pipelineAgg": "2"}]
}
```
- Multiplies derivative result by -1 for negative values
- Creates wave envelope effect (IN/Read below x-axis)
- Must use `params._value` syntax (not just `_value`)

**4. Hide Intermediate Aggregations:**
```json
{"id": "1", "type": "max", "hide": true},      // Hide cumulative counter
{"id": "2", "type": "derivative", "hide": true} // Hide intermediate derivative
```
- Only the final result (bucket_script or derivative) displays
- Keeps legend clean and readable

**5. Terms Aggregation Before Date Histogram:**
```json
"bucketAggs": [
  {"type": "terms", "field": "host.name", ...},        // First
  {"type": "date_histogram", "field": "@timestamp", ...} // Second
]
```
- Order matters: terms aggregation must come before date_histogram
- Enables per-host breakdown in time series

#### Step 3: Elasticsearch Query Generated

The configuration generates this Elasticsearch query:

```json
GET metrics-system.network-default/_search
{
  "size": 0,
  "query": {
    "bool": {
      "must": [
        {
          "query_string": {
            "query": "_index:metrics-system.network-default AND system.network.name:(enp* OR ens*) AND NOT system.network.name:lo"
          }
        },
        {
          "range": {
            "@timestamp": {"gte": "now-15m", "lte": "now"}
          }
        }
      ]
    }
  },
  "aggs": {
    "4": {
      "terms": {
        "field": "host.name",
        "size": 10,
        "order": {"_key": "asc"}
      },
      "aggs": {
        "5": {
          "date_histogram": {
            "field": "@timestamp",
            "fixed_interval": "10s"
          },
          "aggs": {
            "1": {
              "max": {"field": "system.network.in.bytes"}
            },
            "2": {
              "derivative": {
                "buckets_path": "1",
                "unit": "10s"
              }
            },
            "3": {
              "bucket_script": {
                "buckets_path": {"_value": "2"},
                "script": "params._value * -1"
              }
            }
          }
        }
      }
    }
  }
}
```

#### Step 4: Elasticsearch Response Structure

```json
{
  "aggregations": {
    "4": {
      "buckets": [
        {
          "key": "lab1",
          "5": {
            "buckets": [
              {
                "key_as_string": "2025-10-15T10:00:00.000Z",
                "1": {"value": 21691424182.0},    // max (cumulative)
                "2": {"value": 15334.0},           // derivative (rate)
                "3": {"value": -15334.0}           // bucket_script (negative rate)
              }
            ]
          }
        },
        {
          "key": "lab2",
          "5": {"buckets": [...]}
        }
      ]
    }
  }
}
```

#### Step 5: Grafana Label Generation

**For Target A (with alias `{{term host.name}} In`):**
- Grafana extracts `key: "lab1"` from terms bucket
- Applies alias pattern: `"lab1" + " In"` = `"lab1 In"`
- Creates clean, dynamic label

**Result for 2-host cluster:**
- `lab1 In` (negative values, below x-axis)
- `lab1 Out` (positive values, above x-axis)
- `lab2 In` (negative values)
- `lab2 Out` (positive values)

**Result for 100-host cluster (automatic):**
- All 100 hosts appear with correct labels
- No configuration changes needed
- Pattern: `<hostname> In` and `<hostname> Out`

## Complete Working Example: Network Byte Rate Panel

### Panel Configuration

```json
{
  "title": "Network Byte Rate (In/Out)",
  "type": "timeseries",
  "targets": [
    {
      "datasource": {"type": "elasticsearch", "uid": "spark-elasticsearch"},
      "query": "_index:metrics-system.network-default AND system.network.name:(enp* OR ens* OR eth0 OR eth1) AND NOT system.network.name:lo",
      "alias": "{{term host.name}} In",
      "metrics": [
        {"id": "1", "type": "max", "field": "system.network.in.bytes", "hide": true},
        {"id": "2", "type": "derivative", "field": "1", "pipelineAgg": "1", "settings": {"unit": "10s"}, "hide": true},
        {"id": "3", "type": "bucket_script", "pipelineAgg": "2", "settings": {"script": "params._value * -1"}, "pipelineVariables": [{"name": "_value", "pipelineAgg": "2"}]}
      ],
      "bucketAggs": [
        {"id": "4", "type": "terms", "field": "host.name", "settings": {"min_doc_count": "1", "order": "asc", "orderBy": "_key", "size": "10"}},
        {"id": "5", "type": "date_histogram", "field": "@timestamp", "settings": {"interval": "10s"}}
      ],
      "refId": "A",
      "timeField": "@timestamp"
    },
    {
      "datasource": {"type": "elasticsearch", "uid": "spark-elasticsearch"},
      "query": "_index:metrics-system.network-default AND system.network.name:(enp* OR ens* OR eth0 OR eth1) AND NOT system.network.name:lo",
      "alias": "{{term host.name}} Out",
      "metrics": [
        {"id": "1", "type": "max", "field": "system.network.out.bytes", "hide": true},
        {"id": "2", "type": "derivative", "field": "1", "pipelineAgg": "1", "settings": {"unit": "10s"}}
      ],
      "bucketAggs": [
        {"id": "3", "type": "terms", "field": "host.name", "settings": {"min_doc_count": "1", "order": "asc", "orderBy": "_key", "size": "10"}},
        {"id": "4", "type": "date_histogram", "field": "@timestamp", "settings": {"interval": "10s"}}
      ],
      "refId": "B",
      "timeField": "@timestamp"
    }
  ],
  "fieldConfig": {
    "defaults": {
      "unit": "Bps",
      "custom": {
        "lineWidth": 1,
        "fillOpacity": 0
      }
    },
    "overrides": []
  },
  "options": {
    "legend": {
      "showLegend": true,
      "displayMode": "list",
      "placement": "bottom",
      "calcs": []
    }
  }
}
```

### Visual Result

```
   OUT ─────────▲──────── (positive rates above x-axis)
                │
                │    lab1 Out, lab2 Out
                │
   ─────────────0─────────────────────────────────────
                │
                │    lab1 In, lab2 In
                │
   IN  ─────────▼──────── (negative rates below x-axis)
```

## Scalability Analysis

### Current Implementation (2 Hosts)

**Configuration Complexity:**
- 2 targets per panel (IN and OUT)
- No hardcoded host names
- No field overrides needed
- No transformations required

**Visible Series:**
- lab1 In (negative)
- lab1 Out (positive)
- lab2 In (negative)
- lab2 Out (positive)

### Adding 98 New Hosts (100 Total)

**Configuration Changes Required:** **ZERO**

**Automatic Behavior:**
1. Elasticsearch `terms` aggregation returns all 100 hosts
2. Grafana applies alias pattern to each: `{{term host.name}} In/Out`
3. Bucket_script negates IN values automatically
4. Wave envelope applies to all hosts

**Visible Series (automatically):**
- lab1 In, lab1 Out
- lab2 In, lab2 Out
- prod-node-01 In, prod-node-01 Out
- prod-node-02 In, prod-node-02 Out
- ... (all 100 hosts)
- prod-node-100 In, prod-node-100 Out

### Enterprise Benefits

✅ **Zero Maintenance**: No dashboard updates when cluster topology changes  
✅ **Automatic Discovery**: New hosts appear immediately with correct formatting  
✅ **Consistent Behavior**: Wave envelope and labels work identically for all hosts  
✅ **Performance**: Server-side calculations scale efficiently  
✅ **Reliability**: No client-side transformations that could fail or slow down rendering  

## Common Patterns

### Network Metrics (Physical Interfaces)

**Query Filter:**
```
_index:metrics-system.network-default AND system.network.name:(enp* OR ens* OR eth0 OR eth1) AND NOT system.network.name:lo
```

**Fields:**
- IN: `system.network.in.bytes`
- OUT: `system.network.out.bytes`

### Loopback Traffic

**Query Filter:**
```
_index:metrics-system.network-default AND system.network.name:lo
```

**Fields:**
- IN: `system.network.in.bytes`
- OUT: `system.network.out.bytes`

### Disk I/O Metrics

**Query Filter:**
```
_index:metrics-system.diskio-default
```

**Fields:**
- READ: `system.diskio.read.bytes`
- WRITE: `system.diskio.write.bytes`

## Troubleshooting

### Issue: Derivative Returns No Data

**Symptom**: Derivative columns show no values in exported data

**Cause**: Using string metric IDs instead of numeric

**Fix**:
```json
// Change from:
{"id": "max_in_bytes", "type": "max", ...}
{"id": "in_rate", "type": "derivative", "field": "max_in_bytes", ...}

// To:
{"id": "1", "type": "max", ...}
{"id": "2", "type": "derivative", "field": "1", "pipelineAgg": "1", ...}
```

### Issue: Bucket Script Compile Error

**Symptom**: "Compile error" message in query editor, no data from Target A

**Cause**: Incorrect bucket_script syntax

**Fix**:
```json
// Change from:
{"script": "_value * -1"}

// To:
{"script": "params._value * -1"}
```

Elasticsearch bucket_script requires accessing pipeline variables through the `params` object.

### Issue: Wave Envelope Not Showing

**Symptom**: All values appear positive, no negative values below x-axis

**Cause**: Bucket_script not configured or not working

**Verification**:
1. Check Target A has bucket_script metric (ID "3")
2. Verify script: `"params._value * -1"`
3. Ensure pipelineVariables correctly references derivative metric
4. Export panel data to CSV - bucket_script column should show negative values

### Issue: Labels Not Dynamic

**Symptom**: Labels show same text for all hosts or show as "$1 In"

**Cause**: Using wrong alias pattern or field override approach

**Fix**:
```json
// Use alias pattern (not field overrides):
"alias": "{{term host.name}} In"

// Grafana will replace {{term host.name}} with actual hostname from terms bucket
```

Note: Field override `displayName` with regex capture groups (`$1`) does NOT work in Grafana. Use alias patterns instead.

## Summary

The scalable solution for derivative metric calculation combines:

1. **Numeric Metric IDs** - Required by Grafana's Elasticsearch datasource for pipeline aggregations
2. **Separate Targets** - IN/OUT or Read/Write in distinct queries for clean aliasing
3. **Alias Patterns** - `{{term host.name}}` template variable for dynamic labels
4. **Bucket Script** - Server-side negation with `params._value * -1` for wave envelope
5. **Terms Before Date Histogram** - Aggregation order enables per-host breakdown
6. **Hide Intermediate Metrics** - Clean legends showing only final calculated rates

This configuration is:
- ✅ **Scalable**: Works with 2 to 2000+ hosts without modification
- ✅ **Performant**: Server-side calculations, no client transformations
- ✅ **Maintainable**: Zero configuration changes for cluster topology updates
- ✅ **Clear**: Clean labels and visual distinction (wave envelope)
- ✅ **Reliable**: Automatic counter reset handling via Elasticsearch derivatives

Following these patterns ensures enterprise-ready dashboards that adapt automatically to infrastructure changes while maintaining clarity and performance.

