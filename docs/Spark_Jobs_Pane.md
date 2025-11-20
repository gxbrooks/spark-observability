# Spark Jobs Pane - File-Based Telemetry Architecture

## **Overview**

The Spark Jobs pane in Grafana displays real-time metrics about active Spark applications using a file-based event collection architecture. This document describes the data flow from Spark applications through each processing stage to visualization in Grafana.

---

## **Architecture Diagram**

```
Spark Application
    ↓ (writes event logs)
Event Log Files (/mnt/spark/events)
    ↓ (harvested)
Elastic Agent (Filebeat)
    ↓ (Beats protocol, port 5050)
Logstash (Ruby filter)
    ↓ (HTTPS, port 9200)
Elasticsearch (batch-events index)
    ↓ (queried)
Grafana (Active Spark Jobs panel)
```

---

## **Data Flow**

### **Stage 1: Spark Application**

**Actor**: Apache Spark EventLog subsystem

**Inputs**: 
- Spark application lifecycle events (internal)
- Configuration: `spark-defaults.conf`

**Operations**:
- Captures application lifecycle events (App, Job, Stage, Task, SQL)
- Serializes events as JSON (one event per line)
- Writes to configured event log directory

**Outputs**:
- File: `/mnt/spark/events/app-<timestamp>-<id>`
- Format: Newline-delimited JSON (NDJSON)
- Sample event: See `observability/elasticsearch/batch-events/sample-app-start.json`

**Configuration** (See: `spark/conf/spark-defaults.conf`):
```properties
spark.eventLog.enabled                 true
spark.eventLog.dir                     /mnt/spark/events
spark.eventLog.rolling.enabled         false
spark.eventLog.compression.codec       none
```

---

### **Stage 2: Event Log Files**

**Storage**: NFS-mounted shared directory

**Location**: 
- K8s pods: `/mnt/spark/events` (mounted from NFS)
- NFS server: `/srv/nfs/spark/events` (Lab2)
- Managed nodes: `/mnt/spark/events` (NFS mount)

**Ownership**: 
- User:Group: `gxbrooks:gxbrooks`
- Permissions: `660` (rw-rw----)

**Access Control**:
- Elastic Agent user must be member of file owner's group
- See `tmp/985_spark_events_pipeline_fix.md` for details

---

### **Stage 3: Elastic Agent (Filebeat)**

**Actor**: Elastic Agent filestream input (`filestream-spark_events`)

**Inputs**:
- File path pattern: `/mnt/spark/events/app-*`
- Configuration: `elastic-agent/elastic-agent.linux.yml`

**Operations**:
- Scans directory every 10 seconds for new files
- Harvests each line as separate event
- Parses NDJSON → extracts JSON into `spark` field
- Tags with metadata (host, file path)
- Excludes `.tmp` and `.lock` files
- Closes inactive files after 5 minutes

**Outputs**:
- Protocol: Beats protocol (Lumberjack)
- Destination: `${LS_HOST}:${LS_SPARK_EVENTS_PORT}` (GaryPC.lan:5050)
- Target: `spark_events` output (type: logstash)

**Configuration** (See: `elastic-agent/elastic-agent.linux.yml`, lines 85-104):
```yaml
- id: spark-events
  type: filestream
  use_output: "spark_events"
  streams:
    - paths: ["/mnt/spark/events/app-*"]
      parsers:
        - ndjson:
            target: "spark"
```

---

### **Stage 4: Logstash (Ruby Filter)**

**Actor**: Logstash with custom Ruby filter

**Inputs**:
- Port: 5050 (Beats protocol)
- Format: Beats message with `spark` field containing parsed JSON
- Configuration: `observability/logstash/pipeline/logstash.conf`

**Operations**:
1. **Parse JSON**: Extract event from `message` field → `spark` field
2. **Event Classification**: Determine event type (App, Job, Stage, Task, SQL)
3. **Metadata Enrichment**:
   - Generate unique IDs (trace_uid, event_uid)
   - Calculate parent-child relationships
   - Extract timestamps
   - Create start/end event pairs
4. **Dual Output Creation**:
   - Original Spark event → `logs-spark-spark` datastream
   - Enriched batch event → `batch-events` index
5. **Fingerprinting**: SHA-1 hashing for document IDs and routing

**Key Processing** (See: `observability/logstash/pipeline/logstash.conf`, lines 14-362):
- Event type detection via `case` statement
- UID generation: `{realm}:{class}:{baseUID}`
- Parent tracking: `trace_parent_uid` for hierarchy
- Routing IDs: Ensures start/end events have matching routing for join-parent relationship

**Outputs**:
1. **Spark Events**: `logs-spark-spark` datastream (full event details)
2. **Batch Events**: `batch-events` index (enriched with UIDs, routing, start_end relationship)

---

### **Stage 5: Elasticsearch**

**Actor**: Elasticsearch cluster

**Inputs**:
- Index: `batch-events`
- Documents: Enriched events from Logstash

**Operations**:
- Index batch events with routing IDs
- Watchers aggregate unmatched events (See: `observability/elasticsearch/batch-events/batch-match-join.watcher.json`)
- Creates `batch-metrics-ds` datastream with aggregated metrics

**Key Fields** (See: `observability/elasticsearch/batch-events/batch-events.template.json`):
- `@timestamp`: Event occurrence time
- `class`: Event class (App, Job, Stage, Task, SQLQuery)
- `event_kind`: Start/End/Point
- `service_name`: Application/job/stage name
- `count`: Metric value (always 1 for individual events)

**Datastreams**:
- `batch-events`: Raw enriched events
- `batch-metrics-ds`: Aggregated metrics by class (created by Watchers)

---

### **Stage 6: Grafana Panel**

**Actor**: Grafana Elasticsearch datasource query

**Inputs**:
- Datasource: `spark-elasticsearch` (queries all indices)
- Index filter: `_index:batch-metrics-ds`
- Time range: Dashboard time picker

**Operations** (See: `observability/grafana/provisioning/dashboards/spark-system.json`, lines 100-138):

1. **Lucene Query**: Filter events
   ```
   _index:batch-metrics-ds AND NOT class:"Task"
   ```
   (Excludes Task class to reduce noise)

2. **Bucket Aggregation 1 (Terms)**:
   - Field: `class`
   - Purpose: Group by event class (App, Job, Stage, SQLQuery)
   - Size: Top 10 classes

3. **Bucket Aggregation 2 (Date Histogram)**:
   - Field: `@timestamp`
   - Interval: `auto` (dynamic based on time range)
   - Purpose: Time-series buckets

4. **Metric Aggregation**:
   - Type: `avg`
   - Field: `count`
   - Purpose: Average active items per time bucket

**Visualization**:
- Type: Time series line chart
- Y-axis: Average count of active items
- X-axis: Time
- Series: One line per class (App, Job, Stage, SQLQuery)

**Panel Configuration**:
```json
{
  "title": "Active Spark Jobs (Avg, excl Tasks)",
  "type": "timeseries",
  "targets": [{
    "query": "_index:batch-metrics-ds AND NOT class:\"Task\"",
    "bucketAggs": [
      {"type": "terms", "field": "class"},
      {"type": "date_histogram", "field": "@timestamp", "interval": "auto"}
    ],
    "metrics": [
      {"type": "avg", "field": "count"}
    ]
  }]
}
```

---

## **Data Transformation Example**

**Input (Spark Event)**:
```json
{
  "Event": "SparkListenerJobStart",
  "Job ID": 1,
  "Submission Time": 1760734820295,
  "...": "..."
}
```

**After Logstash Processing (Batch Event)**:
```json
{
  "@timestamp": "2025-10-17T21:00:20.295Z",
  "realm": "Spark",
  "class": "Job",
  "event_kind": "Start",
  "service_name": "1",
  "service_id": "1",
  "count": 1,
  "trace_uid": "Spark:Job:...",
  "matched": false
}
```

**After Watcher Aggregation (Batch Metrics)**:
```json
{
  "@timestamp": "2025-10-17T21:00:20.295Z",
  "class": "Job",
  "count": 3,  ← Aggregated count
  "matched": true
}
```

**Grafana Visualization**:
- X: 21:00:20
- Y: 3 (average active jobs)
- Series: "Job"

---

## **Key Design Points**

### **Why File-Based?**
- ✅ Proven Spark subsystem (EventLog)
- ✅ No custom code in Spark
- ✅ Supports all Spark deployment modes
- ✅ Historical analysis (files retained)

### **Limitations**
- ❌ Latency: 10-60 seconds (file scan + close_inactive)
- ❌ Resource overhead: File I/O, NFS
- ❌ Complexity: Multi-stage pipeline

### **Reliability**
- ✅ File registry prevents duplicate processing
- ✅ Logstash dead letter queue for failures
- ✅ Elasticsearch indices for durability

---

## **Related Documentation**

- **Logstash Configuration**: `observability/logstash/pipeline/logstash.conf`
- **Elastic Agent Config**: `elastic-agent/elastic-agent.linux.yml`
- **Grafana Dashboard**: `observability/grafana/provisioning/dashboards/spark-system.json`
- **Watcher Logic**: `observability/elasticsearch/batch-events/batch-match-join.watcher.json`
- **Troubleshooting**: `tmp/985_spark_events_pipeline_fix.md`

---

**Status**: ✅ Operational - provides reliable near-real-time Spark job metrics with ~30-60 second latency.

