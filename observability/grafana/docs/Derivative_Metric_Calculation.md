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

## Data Transformation Pipeline: From Raw Telemetry to Derivative Rates

This section illustrates the complete data transformation pipeline, showing how raw counter values flow through each aggregation stage to produce derivative rates. Understanding this pipeline is critical for troubleshooting and optimizing derivative calculations.

### Stage 0: Raw Telemetry Data (Elasticsearch Documents)

**Source**: Elastic Agent collects system metrics every 10 seconds (`period: 10s`)

**Raw Document Structure** (JSON):
```json
{
  "@timestamp": "2025-11-18T10:00:00.000Z",
  "host.name": "lab1",
  "system.network.name": "enp0s3",
  "system.network.in.bytes": 21691424182,
  "system.network.out.bytes": 5432109876,
  "_index": "metrics-system.network-default"
}
```

**Relational View** (Sample Data):
| @timestamp | host.name | system.network.name | system.network.in.bytes | system.network.out.bytes |
|------------|-----------|---------------------|------------------------|--------------------------|
| 10:00:00 | lab1 | enp0s3 | 21691424182 | 5432109876 |
| 10:00:00 | lab1 | enp0s8 | 1234567890 | 987654321 |
| 10:00:00 | lab2 | enp0s3 | 50000000000 | 20000000000 |
| 10:00:10 | lab1 | enp0s3 | 21691439516 | 5432112345 |
| 10:00:10 | lab1 | enp0s8 | 1234568901 | 987654432 |
| 10:00:10 | lab2 | enp0s3 | 50000015334 | 20000012345 |

**Key Characteristics**:
- **Cumulative counters**: Values increase monotonically (except on counter reset)
- **Multiple interfaces per host**: Each host may have multiple network interfaces
- **10-second collection period**: New documents arrive every 10 seconds
- **Per-interface metrics**: Each document represents one interface at one point in time

### Stage 1: Query Filtering

**Grafana Query**:
```
_index:metrics-system.network-default AND 
system.network.name:(enp* OR ens* OR wlp* OR eth0 OR eth1) AND 
NOT system.network.name:lo AND
@timestamp: [10:00:00 TO 10:05:00]
```

**Effect**: Filters documents to:
- Specific index pattern
- Physical network interfaces (excludes loopback)
- Time range (Grafana's selected time window)

**Filtered Data** (Same structure, fewer rows):
| @timestamp | host.name | system.network.name | system.network.in.bytes | system.network.out.bytes |
|------------|-----------|---------------------|------------------------|--------------------------|
| 10:00:00 | lab1 | enp0s3 | 21691424182 | 5432109876 |
| 10:00:00 | lab1 | enp0s8 | 1234567890 | 987654321 |
| 10:00:00 | lab2 | enp0s3 | 50000000000 | 20000000000 |
| 10:00:10 | lab1 | enp0s3 | 21691439516 | 5432112345 |
| ... | ... | ... | ... | ... |

**Key Parameters**:
- **Time range**: Determines which documents are included
- **Interface filter**: Excludes loopback, includes only physical interfaces
- **Index pattern**: Ensures correct data stream

### Stage 2: Terms Aggregation (Group by Host)

**Aggregation Configuration**:
```json
{
  "id": "4",
  "type": "terms",
  "field": "host.name",
  "settings": {
    "min_doc_count": "1",
    "order": "asc",
    "orderBy": "_key",
    "size": "10"
  }
}
```

**Effect**: Groups documents by `host.name`, creating separate buckets for each host.

**After Terms Aggregation** (Nested Structure):
```
Bucket: host.name = "lab1"
  Documents:
    - 10:00:00, enp0s3, 21691424182, 5432109876
    - 10:00:00, enp0s8, 1234567890, 987654321
    - 10:00:10, enp0s3, 21691439516, 5432112345
    - 10:00:10, enp0s8, 1234568901, 987654432
    - ...

Bucket: host.name = "lab2"
  Documents:
    - 10:00:00, enp0s3, 50000000000, 20000000000
    - 10:00:10, enp0s3, 50000015334, 20000012345
    - ...
```

**Key Parameters**:
- **Field**: `host.name` - Groups by hostname
- **Size**: Maximum number of host buckets (10)
- **Order**: Determines which hosts appear first

**Pitfall**: If `size` is too small, some hosts may be excluded from results.

### Stage 3: Date Histogram Aggregation (Time Bucketing)

**Aggregation Configuration**:
```json
{
  "id": "5",
  "type": "date_histogram",
  "field": "@timestamp",
  "settings": {
    "interval": "10s"
  }
}
```

**Effect**: Groups documents within each host bucket by time intervals of 10 seconds.

**After Date Histogram** (Nested Structure):
```
Bucket: host.name = "lab1"
  Bucket: @timestamp = 10:00:00
    Documents:
      - enp0s3, 21691424182, 5432109876
      - enp0s8, 1234567890, 987654321
  Bucket: @timestamp = 10:00:10
    Documents:
      - enp0s3, 21691439516, 5432112345
      - enp0s8, 1234568901, 987654432
  Bucket: @timestamp = 10:00:20
    Documents:
      - enp0s3, 21691454850, 5432114814
      - enp0s8, 1234569912, 987654543
  ...

Bucket: host.name = "lab2"
  Bucket: @timestamp = 10:00:00
    Documents:
      - enp0s3, 50000000000, 20000000000
  Bucket: @timestamp = 10:00:10
    Documents:
      - enp0s3, 50000015334, 20000012345
  ...
```

**Relational View** (Per Host, Per Time Bucket):
| host.name | bucket_time | interface | in.bytes | out.bytes |
|-----------|-------------|-----------|----------|-----------|
| lab1 | 10:00:00 | enp0s3 | 21691424182 | 5432109876 |
| lab1 | 10:00:00 | enp0s8 | 1234567890 | 987654321 |
| lab1 | 10:00:10 | enp0s3 | 21691439516 | 5432112345 |
| lab1 | 10:00:10 | enp0s8 | 1234568901 | 987654432 |
| lab2 | 10:00:00 | enp0s3 | 50000000000 | 20000000000 |
| lab2 | 10:00:10 | enp0s3 | 50000015334 | 20000012345 |

**Key Parameters**:
- **Interval**: `10s` - Must match or exceed data collection period (10s)
- **Field**: `@timestamp` - Time field for bucketing

**Critical Pitfall: Interval Too Small**

If `interval` < data collection period (10s):
- Many buckets will be **empty** (no documents)
- Empty buckets break derivative calculation chain
- Result: **No data displayed** for short time ranges

**Example of Problem**:
```
Interval = 3s (too small)
Bucket: 10:00:00-10:00:03 → Empty (no data collected yet)
Bucket: 10:00:03-10:00:06 → Empty
Bucket: 10:00:06-10:00:09 → Empty
Bucket: 10:00:09-10:00:12 → Has data (10:00:10 document)
Bucket: 10:00:12-10:00:15 → Empty
...
```

**Solution**: Use fixed interval of `10s` to match data collection period.

### Stage 4: Sum Aggregation (Aggregate Across Interfaces)

**Aggregation Configuration**:
```json
{
  "id": "1",
  "type": "sum",
  "field": "system.network.in.bytes",
  "hide": true
}
```

**Effect**: Sums counter values across all interfaces within each time bucket.

**After Sum Aggregation** (Per Host, Per Time Bucket):
| host.name | bucket_time | sum(in.bytes) | sum(out.bytes) |
|-----------|-------------|---------------|----------------|
| lab1 | 10:00:00 | 22925992072 | 6419764197 |
| lab1 | 10:00:10 | 22926008417 | 6419766777 |
| lab1 | 10:00:20 | 22926024762 | 6419769357 |
| lab2 | 10:00:00 | 50000000000 | 20000000000 |
| lab2 | 10:00:10 | 50000015334 | 20000012345 |
| lab2 | 10:00:20 | 50000030668 | 20000024690 |

**Calculation Example** (lab1, 10:00:00):
- enp0s3: 21691424182
- enp0s8: 1234567890
- **Sum**: 21691424182 + 1234567890 = 22925992072

**Key Parameters**:
- **Type**: `sum` - Aggregates across multiple interfaces
- **Field**: Counter field to aggregate
- **Hide**: `true` - Hides intermediate result from display

**Alternative Aggregations**:
- `max`: Takes maximum value (used for per-host metrics)
- `avg`: Takes average (rarely used for counters)
- `min`: Takes minimum (rarely used for counters)

**Pitfall: Using Max Instead of Sum for Aggregated Metrics**

When aggregating across multiple hosts/interfaces, use `sum` to get total cluster throughput:
- **Sum**: Total bytes across all hosts/interfaces (correct for aggregated view)
- **Max**: Maximum single-host/interface value (incorrect, causes oscillation)

**Example of Problem** (Max Aggregation):
```
Time 10:00:00: lab1=100GB, lab2=50GB → Max=100GB
Time 10:00:10: lab1=101GB, lab2=60GB → Max=101GB (derivative = 1GB/10s)
Time 10:00:20: lab1=102GB, lab2=70GB → Max=102GB (derivative = 1GB/10s)
Time 10:00:30: lab1=103GB, lab2=80GB → Max=103GB (derivative = 1GB/10s)
```

But if max switches between hosts:
```
Time 10:00:00: lab1=100GB, lab2=50GB → Max=100GB (lab1)
Time 10:00:10: lab1=101GB, lab2=60GB → Max=101GB (lab1, derivative = 1GB/10s)
Time 10:00:20: lab1=102GB, lab2=70GB → Max=102GB (lab1, derivative = 1GB/10s)
Time 10:00:30: lab1=103GB, lab2=80GB → Max=103GB (lab1, derivative = 1GB/10s)
Time 10:00:40: lab1=104GB, lab2=90GB → Max=104GB (lab1, derivative = 1GB/10s)
Time 10:00:50: lab1=105GB, lab2=100GB → Max=105GB (lab1, derivative = 1GB/10s)
Time 10:01:00: lab1=106GB, lab2=110GB → Max=110GB (lab2!) → derivative = 5GB/10s (spike!)
Time 10:01:10: lab1=107GB, lab2=111GB → Max=111GB (lab2, derivative = 1GB/10s)
```

This causes **oscillation** when the max switches between hosts.

**Solution**: Use `sum` for aggregated metrics to ensure monotonically increasing counters.

### Stage 5: Derivative Aggregation (Rate Calculation)

**Aggregation Configuration**:
```json
{
  "id": "2",
  "type": "derivative",
  "field": "1",
  "pipelineAgg": "1",
  "settings": {
    "unit": "10s"
  },
  "hide": true
}
```

**Effect**: Calculates rate of change between consecutive time buckets, normalized by time unit.

**After Derivative Aggregation**:
| host.name | bucket_time | sum(in.bytes) | derivative(in.bytes) |
|-----------|-------------|---------------|----------------------|
| lab1 | 10:00:00 | 22925992072 | **null** (no previous bucket) |
| lab1 | 10:00:10 | 22926008417 | **16345** bytes/10s = 1634.5 bytes/s |
| lab1 | 10:00:20 | 22926024762 | **16345** bytes/10s = 1634.5 bytes/s |
| lab1 | 10:00:30 | 22926041107 | **16345** bytes/10s = 1634.5 bytes/s |
| lab2 | 10:00:00 | 50000000000 | **null** |
| lab2 | 10:00:10 | 50000015334 | **15334** bytes/10s = 1533.4 bytes/s |
| lab2 | 10:00:20 | 50000030668 | **15334** bytes/10s = 1533.4 bytes/s |

**Calculation Formula**:
```
derivative = (current_value - previous_value) / time_delta
           = (22926008417 - 22925992072) / 10s
           = 16345 bytes / 10s
           = 1634.5 bytes/s
```

**Key Parameters**:
- **unit**: `10s` - Normalization unit (must match date_histogram interval)
- **pipelineAgg**: `1` - References the sum aggregation (ID "1")
- **field**: `1` - Also references aggregation ID "1"

**Critical Pitfall: Endpoint Anomalies**

**Problem**: First and last buckets compare with buckets outside the query time window.

**Example**:
```
Query time range: 10:00:00 to 10:05:00

Bucket sequence in Elasticsearch:
  09:59:50 → 10000000000 (outside query window)
  10:00:00 → 22925992072 (first bucket in query)
  10:00:10 → 22926008417
  ...
  10:05:00 → 22927000000 (last bucket in query)
  10:05:10 → 50000000000 (outside query window, different counter state!)

Derivative calculation:
  10:00:00: (22925992072 - 10000000000) / 10s = 1292599207 bytes/s = 1.29 GB/s ❌
  10:00:10: (22926008417 - 22925992072) / 10s = 1634.5 bytes/s ✅
  ...
  10:05:00: (50000000000 - 22927000000) / 10s = 2707300000 bytes/s = 2.7 GB/s ❌
```

**Root Cause**:
- Elasticsearch stores continuous data (buckets exist outside query window)
- Derivative operates on bucket sequence, not query time range
- Boundary buckets compare with external buckets that may have very different counter values

**Solution**: 
- Set `nullValueMode: "null"` in Grafana field config to hide null values
- Set `spanNulls: false` to break lines at null values
- This hides the first bucket (which is null) and prevents display of anomalous last bucket

**JSON Configuration**:
```json
{
  "fieldConfig": {
    "defaults": {
      "nullValueMode": "null",
      "custom": {
        "spanNulls": false
      }
    }
  }
}
```

### Stage 6: Bucket Script (Wave Envelope - Negation)

**Aggregation Configuration**:
```json
{
  "id": "3",
  "type": "bucket_script",
  "pipelineAgg": "2",
  "settings": {
    "script": "params._value != null ? params._value * -1 : null"
  },
  "pipelineVariables": [
    {
      "name": "_value",
      "pipelineAgg": "2"
    }
  ]
}
```

**Effect**: Multiplies derivative by -1 for "In" metrics to create wave envelope visualization.

**After Bucket Script** (For "In" metrics only):
| host.name | bucket_time | derivative | bucket_script (negated) |
|-----------|-------------|------------|-------------------------|
| lab1 | 10:00:00 | null | null |
| lab1 | 10:00:10 | 1634.5 | **-1634.5** bytes/s |
| lab1 | 10:00:20 | 1634.5 | **-1634.5** bytes/s |
| lab1 | 10:00:30 | 1634.5 | **-1634.5** bytes/s |

**Key Parameters**:
- **script**: `params._value * -1` - Negates the derivative value
- **pipelineVariables**: Maps `_value` to aggregation ID "2" (derivative)
- **pipelineAgg**: `2` - References the derivative aggregation

**Pitfall: Incorrect Script Syntax**

**Wrong**:
```json
{"script": "_value * -1"}  // Missing params. prefix
```

**Correct**:
```json
{"script": "params._value * -1"}  // Must use params. prefix
```

**Pitfall: Null Handling**

If derivative is null (first bucket), bucket_script should also return null:
```json
{"script": "params._value != null ? params._value * -1 : null"}
```

### Stage 7: Final Output to Grafana

**Elasticsearch Response Structure**:
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
                "key_as_string": "2025-11-18T10:00:10.000Z",
                "1": {"value": 22926008417.0},      // sum (hidden)
                "2": {"value": 1634.5},              // derivative (hidden)
                "3": {"value": -1634.5}               // bucket_script (displayed)
              },
              {
                "key_as_string": "2025-11-18T10:00:20.000Z",
                "1": {"value": 22926024762.0},
                "2": {"value": 1634.5},
                "3": {"value": -1634.5}
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

**Grafana Time Series Data**:
| Time | lab1 In | lab1 Out | lab2 In | lab2 Out |
|------|---------|----------|---------|----------|
| 10:00:10 | -1634.5 | 1634.5 | -1533.4 | 1533.4 |
| 10:00:20 | -1634.5 | 1634.5 | -1533.4 | 1533.4 |
| 10:00:30 | -1634.5 | 1634.5 | -1533.4 | 1533.4 |

**Visual Result**:
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

### Complete Pipeline Summary

```
Raw Documents (Elasticsearch)
    ↓ [Query Filter]
Filtered Documents
    ↓ [Terms Aggregation: group by host.name]
Host Buckets
    ↓ [Date Histogram: group by @timestamp, interval=10s]
Time Buckets (per host)
    ↓ [Sum Aggregation: sum across interfaces]
Aggregated Counters (per host, per time bucket)
    ↓ [Derivative Aggregation: rate calculation]
Derivative Rates (bytes/second)
    ↓ [Bucket Script: negation for "In" metrics]
Final Rates (negative for "In", positive for "Out")
    ↓ [Grafana Display]
Time Series Visualization
```

### Key Parameters Summary

| Stage | Parameter | Value | Critical? | Pitfall |
|-------|-----------|-------|-----------|---------|
| Date Histogram | `interval` | `10s` | ✅ Yes | Too small → empty buckets → no data |
| Derivative | `unit` | `10s` | ✅ Yes | Must match date_histogram interval |
| Bucket Script | `script` | `params._value * -1` | ✅ Yes | Missing `params.` → compile error |
| Field Config | `nullValueMode` | `null` | ✅ Yes | Missing → shows null as 0 |
| Field Config | `spanNulls` | `false` | ✅ Yes | `true` → connects across nulls |
| Sum | `type` | `sum` | ✅ Yes | `max` → oscillation when max switches hosts |

### Common Pitfalls and Solutions

1. **Empty Buckets (No Data for Short Time Ranges)**
   - **Cause**: `interval` < data collection period
   - **Solution**: Use fixed `interval: "10s"` to match collection period

2. **Endpoint Anomalies (Spikes at Beginning/End)**
   - **Cause**: Derivative compares with buckets outside query time window
   - **Solution**: Set `nullValueMode: "null"` and `spanNulls: false` to hide boundary anomalies

3. **Oscillation (Values Switching Positive/Negative)**
   - **Cause**: Using `max` aggregation instead of `sum` for aggregated metrics
   - **Solution**: Use `sum` to ensure monotonically increasing counters

4. **No Derivative Data (All Nulls)**
   - **Cause**: Using string metric IDs instead of numeric
   - **Solution**: Use numeric IDs ("1", "2", "3") for pipeline aggregations

5. **Bucket Script Compile Error**
   - **Cause**: Missing `params.` prefix in script
   - **Solution**: Use `params._value` instead of `_value`

## Summary

The scalable solution for derivative metric calculation combines:

1. **Numeric Metric IDs** - Required by Grafana's Elasticsearch datasource for pipeline aggregations
2. **Separate Targets** - IN/OUT or Read/Write in distinct queries for clean aliasing
3. **Alias Patterns** - `{{term host.name}}` template variable for dynamic labels
4. **Bucket Script** - Server-side negation with `params._value * -1` for wave envelope
5. **Terms Before Date Histogram** - Aggregation order enables per-host breakdown
6. **Hide Intermediate Metrics** - Clean legends showing only final calculated rates
7. **Fixed Interval** - Use `10s` to match data collection period and prevent empty buckets
8. **Null Value Handling** - Configure `nullValueMode` and `spanNulls` to handle boundary cases

This configuration is:
- ✅ **Scalable**: Works with 2 to 2000+ hosts without modification
- ✅ **Performant**: Server-side calculations, no client transformations
- ✅ **Maintainable**: Zero configuration changes for cluster topology updates
- ✅ **Clear**: Clean labels and visual distinction (wave envelope)
- ✅ **Reliable**: Automatic counter reset handling via Elasticsearch derivatives
- ✅ **Robust**: Handles edge cases (empty buckets, boundary anomalies, null values)

Following these patterns ensures enterprise-ready dashboards that adapt automatically to infrastructure changes while maintaining clarity and performance.

