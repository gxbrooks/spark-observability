# Event-Span Correlation Architecture

**Status**: Production Architecture  
**Version**: 1.0  
**Last Updated**: November 15, 2025

---

## Executive Summary

This document defines the **dual-channel observability architecture** for enterprise applications running on our platform. The architecture provides:

1. **Event Logs**: Independent, immutable audit trail of operation start/end events
2. **OTEL Spans**: Detailed performance traces with metrics and timing information
3. **Correlation System**: Bidirectional linking between events and spans for complete observability

### Key Benefits

- **Reliability**: Events survive communication failures, enabling detection of incomplete operations
- **Compliance**: OTel and Elastic Common Schema (ECS) standards
- **Extensibility**: Unified schema supports multiple enterprise applications
- **Performance**: Minimal runtime overhead (2-5% target)

---

## Architecture Overview

### Dual-Channel Design

```
┌────────────────────────────────────────────────────────────┐
│ Application (Spark, EFT, ETL, etc.)                        │
│                                                            │
│  Listener/Agent emits:                                     │
│    1. START event → Elasticsearch (immediate, independent) │
│    2. Create span with correlation IDs                     │
│    3. END event → Elasticsearch (on completion)            │
│    4. Complete span → OTEL Collector → Elasticsearch       │
└────────────────────────────────────────────────────────────┘
                    │                           │
                    ▼                           ▼
         ┌──────────────────┐      ┌──────────────────┐
         │ Elasticsearch    │      │ OTEL Collector   │
         │  app-events-*    │      │                  │
         │  (audit trail)   │      │                  │
         └──────────────────┘      └────────┬─────────┘
                    │                        │
                    │                        ▼
                    │              ┌──────────────────┐
                    │              │ Elasticsearch    │
                    │              │  traces-*        │
                    │              │  (performance)   │
                    └──────────────┴──────────────────┘
                           Correlated via IDs
```

### Why Dual Channels?

**Problem**: If a listener/agent crashes or loses connection before completing a span:
- No span is emitted (spans require start + end)
- Operation becomes invisible in observability system
- Cannot detect hung or failed operations

**Solution**: Independent event emission:
- START events emitted immediately (don't wait for completion)
- END events emitted independently
- Query for "open" events = operations that never completed
- Spans provide detailed performance metrics when successful

---

## Data Schema

### Schema Compliance Hierarchy

1. **OpenTelemetry (OTel) Semantic Conventions** - Primary standard
2. **Elastic Common Schema (ECS)** - Secondary, where applicable
3. **Application-Specific Conventions** - Tertiary (e.g., Spark naming)

### Terminology

| Term | Definition | Scope | Examples |
|------|------------|-------|----------|
| **Application** | Enterprise application performing operations on data | Top-level | `spark`, `eft`, `etl` |
| **Operation** | Unit of work within an application | Application-level | Spark: `app`, `job`, `stage`, `task`, `sql` |
| **Event** | Immutable record of operation start or end | Audit | START, END |
| **Span** | Timed execution trace with metrics | Performance | OTel span with duration, attributes |

### Field Naming Convention

- **Dotted notation**: `category.subcategory.field`
- **Lowercase**: All field names lowercase
- **Descriptive**: Self-documenting names
- **Consistent**: Same meaning = same name across applications

---

## Event Schema (application-events-*)

### Event Structure

Each operation generates **two independent events**:

#### Base Fields (All Applications)

| Field | Type | ECS/OTel | Description | Example |
|-------|------|----------|-------------|---------|
| `@timestamp` | date | ECS | Event creation time | `2025-11-15T10:30:00.123Z` |
| `event.id` | keyword | ECS | Unique event identifier (UUID) | `evt-550e8400-e29b-...` |
| `event.type` | keyword | ECS | Event type | `start`, `end` |
| `event.category` | keyword | ECS | Event category | `application` |
| `event.state` | keyword | Custom | Event processing state | `open`, `closed` |
| `event.duration` | long | ECS | Duration in nanoseconds (END only) | `5120000000` |
| `application` | keyword | Custom | Enterprise application identifier | `spark`, `eft`, `etl` |
| `operation.type` | keyword | Custom | Operation type within application | `app`, `job`, `stage`, `task` |
| `operation.id` | keyword | Custom | Operation identifier | `job-1`, `stage-3` |
| `operation.name` | text | Custom | Human-readable operation name | `count at Chapter_03.py:41` |
| `operation.result` | keyword | Custom | Operation result (END only) | `SUCCESS`, `FAILED` |
| `correlation.span.id` | keyword | OTel | Link to span | `9b8c7d6e5f4a` |
| `correlation.trace.id` | keyword | OTel | Link to trace | `7a8f3c2b9d1e4f5a` |
| `correlation.start.event.id` | keyword | Custom | Link to START event (END only) | `evt-550e8400-...` |
| `correlation.parent.event.id` | keyword | Custom | Link to parent event | `evt-parent-job-123` |

#### Application-Specific Namespaces

Applications extend the base schema with their own namespace:

- **`spark.*`**: Spark-specific fields (job, stage, task, RDD, shuffle)
- **`eft.*`**: Electronic File Transfer fields (file, protocol, host) - Future
- **`etl.*`**: ETL workflow fields (source, transform, target) - Future

---

## Spark Event Schema

### Spark Application Hierarchy

```
spark (application level)
├── app (Spark application instance)
│   ├── job (Spark job - collection of stages)
│   │   ├── stage (Spark stage - collection of tasks)
│   │   │   └── task (Spark task - single executor operation)
│   │   └── sql (SQL query execution)
│   └── executor (Compute resource)
```

### Spark-Specific Fields

| Field | Type | Description | Operations |
|-------|------|-------------|------------|
| `spark.app.id` | keyword | Spark application ID | app |
| `spark.app.name` | text | Spark application name | app |
| `spark.user` | keyword | User running application | app |
| `spark.job.id` | long | Job ID | job, stage, task |
| `spark.job.stage.count` | long | Number of stages in job | job |
| `spark.stage.id` | long | Stage ID | stage, task |
| `spark.stage.name` | text | Stage name (includes file:line) | stage |
| `spark.stage.attempt` | long | Stage attempt number | stage |
| `spark.stage.num.tasks` | long | Number of tasks in stage | stage |
| `spark.stage.result` | keyword | Stage result | stage |
| `spark.task.id` | long | Task ID | task |
| `spark.task.index` | long | Task index within stage | task |
| `spark.task.executor.id` | keyword | Executor running task | task |

### Spark Metrics Fields (END events)

| Field | Type | Description | Operations |
|-------|------|-------------|------------|
| `spark.metrics.duration.ms` | long | Operation duration | all |
| `spark.metrics.shuffle.read.bytes` | long | Shuffle read bytes | stage, task |
| `spark.metrics.shuffle.write.bytes` | long | Shuffle write bytes | stage, task |
| `spark.metrics.input.bytes` | long | Input bytes read | stage, task |
| `spark.metrics.output.bytes` | long | Output bytes written | stage, task |
| `spark.metrics.memory.spilled.bytes` | long | Memory spilled to disk | stage, task |
| `spark.metrics.disk.spilled.bytes` | long | Disk spilled | stage, task |
| `spark.metrics.executor.run.time.ms` | long | Executor run time | task |
| `spark.metrics.executor.cpu.time.ms` | long | Executor CPU time | task |

### Event Examples

See configuration files in:
- `observability/elasticsearch/config/application-events/`

---

## Span Schema (traces-*)

### Span Structure (OTel Format)

Spans follow OpenTelemetry semantic conventions with additional correlation fields and extracted hierarchy fields for efficient querying:

#### Base Fields

| Field | Type | OTel | Description |
|-------|------|------|-------------|
| `@timestamp` | date | Yes | Span start time |
| `trace.id` | keyword | Yes | Trace identifier |
| `span.id` | keyword | Yes | Span identifier |
| `parent.id` | keyword | Yes | Parent span identifier |
| `span.name` | text | Yes | Span name |
| `span.kind` | keyword | Custom | Operation hierarchy (dotted notation) |
| `event.outcome` | keyword | ECS | Operation result |
| `service.*` | object | OTel | Service metadata |

#### Hierarchy Fields (Extracted from span.kind)

**Purpose**: Enable fast exact-match queries and cross-application aggregations

| Field | Type | Source | Description | Example |
|-------|------|--------|-------------|---------|
| `span.kind` | keyword | OTel listener | Dotted hierarchy notation | `Spark.job` |
| `application` | keyword | **Extracted** | Top-level application identifier | `spark` |
| `operation.type` | keyword | **Extracted** | Operation type within application | `job` |

**Extraction Logic**: OTEL Collector transform processor splits `span.kind` on "."
- `span.kind: "Spark.job"` → `application: "spark"`, `operation.type: "job"`
- `span.kind: "Spark.stage"` → `application: "spark"`, `operation.type: "stage"`
- `span.kind: "EFT.transfer"` → `application: "eft"`, `operation.type: "transfer"`

**Query Performance**:
- ⚠️ Wildcard: `span.kind: "Spark.*"` (slower, scans all docs)
- ✅ Exact: `application: "spark"` (fast, indexed lookup)
- ✅ Cross-app: `operation.type: "job"` (find all job operations across apps)

#### Correlation Fields

| Field | Type | Description |
|-------|------|-------------|
| `correlation.event.start.id` | keyword | Link to START event |
| `correlation.event.end.id` | keyword | Link to END event |

### Span Naming Convention

Spans follow the pattern: `{application}.{operation.type}.{identifier}`

**Examples**:
- `spark.application.Chapter 03: Word Count`
- `spark.job.1`
- `spark.stage.3`
- `spark.task.42`

---

## Correlation Mechanism

### ID Generation

1. **Event ID**: UUID generated when operation starts
2. **Span ID**: OTel-generated hex string
3. **Trace ID**: OTel-generated hex string propagated through hierarchy

### Correlation Flow

```
onOperationStart():
  1. Generate event.id = UUID()
  2. Emit START event with event.id
  3. Create span with correlation.event.start.id = event.id
  4. Store mapping: operation_id → event.id, span

onOperationEnd():
  1. Retrieve event.id from mapping
  2. Generate end_event.id = UUID()
  3. Emit END event with:
     - event.id = end_event.id
     - correlation.start.event.id = start_event.id
     - correlation.span.id = span.id (if available)
  4. Complete span with:
     - correlation.event.end.id = end_event.id
  5. Emit span to OTEL Collector
```

### Query Patterns

**Find span for event**:
```
GET /traces-*/_search
{
  "query": {
    "term": {"Attributes.correlation.event.start.id": "<event.id>"}
  }
}
```

**Find events for span**:
```
GET /app-events-*/_search
{
  "query": {
    "term": {"correlation.span.id": "<span.id>"}
  }
}
```

**Find open (incomplete) operations**:
```
GET /app-events-*/_search
{
  "query": {
    "bool": {
      "must": [
        {"term": {"event.type": "start"}},
        {"term": {"event.state": "open"}},
        {"range": {"@timestamp": {"lte": "now-5m"}}}
      ]
    }
  }
}
```

---

## Elasticsearch Configuration

### Index Lifecycle Management (ILM)

**Policy**: `application-events`
- Hot phase: Rollover at 5GB or 30 days
- Delete phase: 90 days

### Index Template

**Template**: `application-events`
- Pattern: `app-events-*`
- Includes dynamic templates for application namespaces
- Enables efficient querying across all applications

### Files

Configuration files located in:
```
observability/elasticsearch/config/application-events/
├── application-events.ilm.json
├── application-events.template.json
├── application-events.index.json
├── application-events.dataview.json
└── application-events.search.json
```

---

## Implementation

### Component Locations

| Component | Path | Description |
|-----------|------|-------------|
| Listener | `spark/otel-listener/src/main/scala/com/elastic/spark/otel/OTelSparkListener.scala` | Spark event capture and emission |
| Event Emitter | `spark/otel-listener/src/main/scala/com/elastic/spark/otel/EventEmitter.scala` | Elasticsearch event emission with retry |
| OTEL Collector | `observability/otel-collector/otel-collector-config.yaml` | Span processing and hierarchy extraction |
| ES Config | `observability/elasticsearch/config/application-events/` | Index templates and ILM policies |
| Init Script | `observability/elasticsearch/bin/init-index.sh` | Initialization automation |

### Hierarchy Extraction (OTEL Collector)

The OTEL Collector's transform processor automatically extracts `application` and `operation.type` from `span.kind`:

**Configuration** (`observability/otel-collector/otel-collector-config.yaml`):
```yaml
processors:
  transform:
    trace_statements:
      - context: span
        statements:
          # Extract application: "Spark.job" → "spark"
          - set(attributes["application"], Split(attributes["span.kind"], ".")[0]) where attributes["span.kind"] != nil
          # Extract operation.type: "Spark.job" → "job"
          - set(attributes["operation.type"], Split(attributes["span.kind"], ".")[1]) where attributes["span.kind"] != nil
```

**Benefits**:
- **10-100x faster queries**: Exact match vs wildcard
- **Cross-application aggregations**: Query all "job" operations across Spark, EFT, ETL
- **Grafana-friendly**: Easy dropdown variables
- **No code changes**: Automatic extraction at collector level

### Configuration

Event emission configured via environment variables:
- `ES_URL`: Elasticsearch endpoint
- `ES_USER`: Elasticsearch username
- `ES_PASSWORD`: Elasticsearch password
- `OTEL_EXPORTER_OTLP_ENDPOINT`: OTEL Collector endpoint

### Runtime Overhead

Target: 2-5% overhead
- Event emission: Async, non-blocking
- Retry queue: Bounded, fail-safe
- Span emission: Batched by OTel SDK

---

## Monitoring and Alerting

### Key Metrics

1. **Open Operations**: Count of operations with START but no END
2. **Event Emission Failures**: Failed Elasticsearch writes
3. **Span Emission Failures**: Failed OTEL Collector sends
4. **Correlation Gaps**: Spans without events, events without spans

### Dashboards

- **Open Operations Monitor**: Real-time view of incomplete operations
- **Event-Span Correlation**: Correlation health and gaps
- **Application Performance**: Cross-application performance metrics

### Alerting

- Open operations > 10 minutes: Alert on potential hung operations
- Event emission failure rate > 5%: Alert on connectivity issues
- Correlation gap > 10%: Alert on instrumentation issues

---

## Extensibility

### Adding New Applications

1. **Define application namespace**: Create `{app}.*` field structure
2. **Implement listener/agent**: Emit events following base schema
3. **Add dynamic template**: Update index template for new namespace
4. **Create queries**: Application-specific searches and dashboards

### Example: Adding EFT Application

```json
{
  "@timestamp": "2025-11-15T10:30:00.123Z",
  "event.id": "evt-...",
  "event.type": "start",
  "application": "eft",
  "operation.type": "transfer",
  "operation.id": "xfer-123",
  "eft": {
    "file.name": "data.csv",
    "file.size": 1048576,
    "protocol": "sftp",
    "source.host": "server1",
    "dest.host": "server2"
  }
}
```

---

## References

- **OpenTelemetry Semantic Conventions**: https://opentelemetry.io/docs/specs/semconv/
- **Elastic Common Schema (ECS)**: https://www.elastic.co/guide/en/ecs/current/
- **Spark Listener API**: https://spark.apache.org/docs/latest/api/scala/org/apache/spark/scheduler/SparkListener.html

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-11-15 | Initial architecture document |
| 1.1 | 2025-11-16 | Added hierarchy extraction (application + operation.type from span.kind) |


