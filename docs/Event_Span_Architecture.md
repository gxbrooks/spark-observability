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

### Spark Event Schema

#### Spark Application Hierarchy

```
spark (application level)
├── app (Spark application instance)
│   ├── job (Spark job - collection of stages)
│   │   ├── stage (Spark stage - collection of tasks)
│   │   │   └── task (Spark task - single executor operation)
│   │   └── sql (SQL query execution)
│   └── executor (Compute resource)
```

#### Spark-Specific Fields

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
| `spark.sql.execution.id` | long | SQL execution ID | sql |
| `spark.sql.description` | text | SQL query text | sql |
| `spark.sql.query_plan.simplified` | text | Simplified physical plan | sql |
| `spark.sql.query_plan.verbose` | text | Verbose physical plan | sql |

#### Spark Metrics Fields (END events)

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

#### Enrichments

Spark events are enriched with semantic information automatically extracted from Spark internals. These enrichments provide context about **what** operations are being performed, not just **how** they execute.

##### Stage Name Parsing Enrichment

**Purpose**: Extract operation type and source code location from Spark stage names to enable debugging and performance analysis.

**Schema Representation**:
- `spark.semantic.operation.type` (keyword): Specific operation extracted from stage name
- `spark.semantic.source.file` (keyword): Source file name extracted from stage name
- `spark.semantic.source.line` (long): Line number extracted from stage name

**What It Means**: Spark stage names typically follow patterns like `"count at Chapter_03.py:41"` or `"mapPartitions at DataFrame.scala:3012"`. This enrichment parses these names to extract:
- The operation being performed (count, map, filter, groupBy, etc.)
- The source file where the operation was called
- The line number in the source file

**How Users Can Use It**:
- **Performance Debugging**: Find all stages from a specific file/line to identify bottlenecks
- **Code Analysis**: Track which operations are most frequently used
- **Error Correlation**: Link stage failures to specific source code locations
- **Query Examples**:
  - Find all stages from a specific file: `spark.semantic.source.file: "Chapter_03.py"`
  - Find all count operations: `spark.semantic.operation.type: "count"`
  - Find operations from a specific line: `spark.semantic.source.file: "Chapter_03.py" AND spark.semantic.source.line: 41`

**Value Domain**:
- `operation.type`: Common values include `count`, `map`, `filter`, `groupBy`, `reduceByKey`, `join`, `union`, `distinct`, `mapPartitions`, `flatMap`, `sortBy`, `repartition`, `coalesce`
- `source.file`: Any Python/Scala file name (e.g., `Chapter_03.py`, `DataFrame.scala`)
- `source.line`: Positive integer line number

**Example**:
```json
{
  "spark.stage.name": "count at Chapter_03.py:41",
  "spark.semantic.operation.type": "count",
  "spark.semantic.source.file": "Chapter_03.py",
  "spark.semantic.source.line": 41
}
```

**Coverage**: ~60% of stages (stages with parseable names)

**Status**: ✅ Implemented

---

##### RDD Type Analysis Enrichment

**Purpose**: Extract RDD types from the stage's RDD lineage to understand the transformation chain and classify operations.

**Schema Representation**:
- `spark.semantic.rdd.types` (keyword): Comma-separated list of RDD types in the stage
- `spark.semantic.rdd.count` (long): Number of RDDs in the stage

**What It Means**: Each Spark stage contains a chain of RDDs (Resilient Distributed Datasets) representing the transformation pipeline. This enrichment extracts the types of RDDs present (e.g., `MapPartitionsRDD`, `ShuffledRDD`, `CoGroupedRDD`) to understand:
- The nature of transformations (narrow vs wide)
- The presence of shuffles
- The complexity of the stage

**How Users Can Use It**:
- **Shuffle Detection**: Identify stages with `ShuffledRDD` (indicates shuffle operations)
- **Join Detection**: Identify stages with `CoGroupedRDD` (indicates join operations)
- **Transformation Analysis**: Understand the transformation chain complexity
- **Query Examples**:
  - Find all stages with shuffles: `spark.semantic.rdd.types: *ShuffledRDD*`
  - Find join operations: `spark.semantic.rdd.types: *CoGroupedRDD*`
  - Find complex stages: `spark.semantic.rdd.count: >5`

**Value Domain**:
- `rdd.types`: Common RDD types include:
  - `MapPartitionsRDD`: Narrow transformations (map, filter, flatMap)
  - `ShuffledRDD`: Wide transformations requiring shuffle
  - `CoGroupedRDD`: Join or cogroup operations
  - `UnionRDD`: Union of multiple RDDs
  - `HadoopRDD`: Input from HDFS
  - `ParallelCollectionRDD`: Input from local collection
  - `ZippedPartitionsRDD`: Zip operations
- `rdd.count`: Positive integer (typically 1-20)

**Example**:
```json
{
  "spark.semantic.rdd.types": "MapPartitionsRDD,ShuffledRDD,MapPartitionsRDD",
  "spark.semantic.rdd.count": 3
}
```

**Coverage**: ~95% of stages (stages with RDD information)

**Status**: ✅ Implemented

---

##### Operation Classification Enrichment

**Purpose**: Automatically classify the high-level operation type of a stage using multi-signal analysis (stage name, RDD types, shuffle patterns) with confidence scoring.

**Schema Representation**:
- `spark.semantic.operation` (keyword): High-level operation classification
- `spark.semantic.confidence` (double): Classification confidence score (0.0-1.0)
- `spark.semantic.low_confidence` (boolean): Flag indicating low confidence (< 0.7)

**What It Means**: This enrichment combines multiple signals to classify what operation a stage is performing:
- **Stage name parsing** (weight 0.4): Extracts operation from stage name
- **RDD type analysis** (weight 0.3): Infers operation from RDD types
- **Shuffle pattern analysis** (weight 0.3): Refines classification based on shuffle metrics

The confidence score indicates how certain the classification is. Low confidence (< 0.7) suggests the stage may be performing a complex or unusual operation.

**How Users Can Use It**:
- **Performance Analysis**: Group stages by operation type to identify expensive operations
- **Optimization**: Find stages with specific operation types that are slow
- **Anomaly Detection**: Flag low-confidence classifications for manual review
- **Query Examples**:
  - Find all aggregation stages: `spark.semantic.operation: "aggregation"`
  - Find high-confidence classifications: `spark.semantic.confidence: >=0.7`
  - Find stages needing review: `spark.semantic.low_confidence: true`
  - Aggregate by operation: `GROUP BY spark.semantic.operation`

**Value Domain**:
- `operation`: Possible values:
  - `aggregation`: GroupBy, count, reduceByKey operations
  - `join`: Join, cogroup operations
  - `filter`: Filter operations
  - `transformation`: Map, flatMap, mapPartitions operations
  - `union`: Union operations
  - `distinct`: Distinct operations
  - `unknown`: Unclassified operations
- `confidence`: Double between 0.0 and 1.0
  - `0.0-0.3`: Very low confidence
  - `0.3-0.7`: Low to medium confidence
  - `0.7-1.0`: High confidence
- `low_confidence`: Boolean (`true` if confidence < 0.7)

**Example**:
```json
{
  "spark.semantic.operation": "aggregation",
  "spark.semantic.confidence": 0.85,
  "spark.semantic.low_confidence": false
}
```

**Coverage**: ~90% of stages (stages with sufficient signals)

**Status**: ✅ Implemented

---

##### Shuffle Classification Enrichment

**Purpose**: Classify shuffle patterns and intensity to identify expensive data movement operations.

**Schema Representation**:
- `spark.semantic.shuffle.classification` (keyword): Shuffle pattern classification
- `spark.semantic.shuffle.intensity` (keyword): Shuffle data volume category
- `spark.semantic.shuffle.reason` (keyword): Inferred reason for shuffle (post-processing)

**What It Means**: Shuffles are expensive data movement operations in Spark. This enrichment classifies:
- **Pattern**: Whether the stage is producing shuffle data, consuming it, both, or neither
- **Intensity**: The volume of data being shuffled (categorized by size thresholds)
- **Reason**: Why the shuffle is occurring (groupBy, join, sort, repartition)

**How Users Can Use It**:
- **Performance Optimization**: Identify stages with high shuffle intensity for optimization
- **Cost Analysis**: Understand which operations cause the most data movement
- **Bottleneck Detection**: Find stages with very high shuffle volumes
- **Query Examples**:
  - Find shuffle producers: `spark.semantic.shuffle.classification: "shuffle_producer"`
  - Find high-intensity shuffles: `spark.semantic.shuffle.intensity: "very_high"`
  - Find groupBy shuffles: `spark.semantic.shuffle.reason: "groupby"`
  - Find expensive shuffles: `spark.semantic.shuffle.intensity: "very_high" AND spark.metrics.duration.ms: >60000`

**Value Domain**:
- `shuffle.classification`:
  - `shuffle_producer`: Stage writes shuffle data but doesn't read (groupBy, sort)
  - `shuffle_consumer`: Stage reads shuffle data but doesn't write (join right side)
  - `shuffle_exchange`: Stage both reads and writes shuffle data (repartition)
  - `narrow_transformation`: No shuffle (map, filter, flatMap)
- `shuffle.intensity`:
  - `very_high`: > 100 MB shuffle write
  - `high`: 10-100 MB shuffle write
  - `medium`: 1-10 MB shuffle write
  - `low`: < 1 MB shuffle write
  - `none`: No shuffle
- `shuffle.reason` (post-processing):
  - `groupby`: Shuffle for aggregation
  - `join`: Shuffle for join operation
  - `sort`: Shuffle for sorting
  - `repartition`: Shuffle for repartitioning
  - `none`: No shuffle

**Example**:
```json
{
  "spark.semantic.shuffle.classification": "shuffle_producer",
  "spark.semantic.shuffle.intensity": "high",
  "spark.semantic.shuffle.reason": "groupby"
}
```

**Coverage**: 100% of stages (all stages have shuffle metrics)

**Status**: ✅ Implemented (classification, intensity); ⏳ Pending (reason - post-processing)

---

##### SQL Execution Plan Enrichment

**Purpose**: Capture SQL query text and physical execution plans for DataFrame/SQL API operations.

**Schema Representation**:
- `spark.sql.execution.id` (long): SQL execution ID
- `spark.sql.description` (text): SQL query text
- `spark.sql.query_plan.simplified` (text): Simplified physical plan
- `spark.sql.query_plan.verbose` (text): Verbose physical plan

**What It Means**: When Spark executes DataFrame or SQL operations, it generates:
- A unique execution ID for the query
- The SQL query text (for SQL API) or DataFrame operation description
- The physical execution plan showing how Spark will execute the query

**How Users Can Use It**:
- **Query Analysis**: Understand what SQL queries are being executed
- **Plan Analysis**: Review physical plans to identify optimization opportunities
- **Performance Correlation**: Link slow stages to specific SQL queries
- **Query Examples**:
  - Find all stages for a SQL execution: `spark.sql.execution.id: 13`
  - Find stages with specific query: `spark.sql.description: *SELECT*`
  - Find complex plans: `spark.sql.query_plan.simplified: *Exchange*`

**Value Domain**:
- `sql.execution.id`: Positive long integer
- `sql.description`: SQL query string or DataFrame operation description
- `sql.query_plan.simplified`: Simplified physical plan string (e.g., `"Exchange hashpartitioning(word, 200)"`)
- `sql.query_plan.verbose`: Full physical plan tree

**Example**:
```json
{
  "spark.sql.execution.id": 13,
  "spark.sql.description": "SELECT word, COUNT(*) FROM words GROUP BY word",
  "spark.sql.query_plan.simplified": "HashAggregate(keys=[word], functions=[count(1)])"
}
```

**Coverage**: SQL/DataFrame operations only (~30-40% of stages)

**Status**: ✅ Implemented

---

##### RDD Lineage Graph Enrichment

**Purpose**: Capture the complete RDD dependency graph with parent-child relationships for detailed lineage analysis.

**Schema Representation**:
- `spark.rdd.lineage` (nested object array): Complete RDD dependency graph
  - `rdd.id` (long): RDD identifier
  - `rdd.name` (keyword): RDD name/type
  - `rdd.partitions` (long): Number of partitions
  - `rdd.parents` (long array): Parent RDD IDs
  - `rdd.callsite` (text): Where RDD was created

**What It Means**: The complete RDD lineage shows the full transformation chain from input to output, including:
- All RDDs in the stage
- Parent-child relationships between RDDs
- Partition counts at each level
- Call sites for each transformation

**How Users Can Use It**:
- **Lineage Tracing**: Follow data flow from input to output
- **Dependency Analysis**: Understand RDD dependencies
- **Optimization**: Identify opportunities to reduce RDD chain length
- **Query Examples**:
  - Find stages with specific RDD: `spark.rdd.lineage.rdd.name: "HadoopRDD"`
  - Find stages with many RDDs: `spark.rdd.lineage.length: >10`
  - Trace lineage: Follow `rdd.parents` chain

**Value Domain**:
- `rdd.lineage`: Array of RDD objects (typically 1-20 RDDs per stage)
- Each RDD object contains:
  - `rdd.id`: Positive integer
  - `rdd.name`: RDD type name (see RDD Type Analysis)
  - `rdd.partitions`: Positive integer
  - `rdd.parents`: Array of parent RDD IDs (may be empty for input RDDs)
  - `rdd.callsite`: String describing where RDD was created

**Example**:
```json
{
  "spark.rdd.lineage": [
    {
      "rdd.id": 5,
      "rdd.name": "MapPartitionsRDD",
      "rdd.partitions": 200,
      "rdd.parents": [4],
      "rdd.callsite": "at org.apache.spark.sql.Dataset.count(Dataset.scala:3012)"
    },
    {
      "rdd.id": 4,
      "rdd.name": "ShuffledRDD",
      "rdd.partitions": 200,
      "rdd.parents": [3],
      "rdd.callsite": "at org.apache.spark.rdd.RDD.groupBy(RDD.scala:701)"
    }
  ]
}
```

**Coverage**: ~95% of stages (stages with RDD information)

**Status**: ⏳ Pending (basic RDD types implemented, full lineage graph pending)

---

##### Performance Hints Enrichment

**Purpose**: Generate performance optimization hints based on operation patterns and metrics.

**Schema Representation**:
- `spark.semantic.performance.hint` (text): Human-readable performance optimization suggestions

**What It Means**: Post-processing analysis identifies common performance issues and suggests optimizations:
- High-cardinality groupBy operations
- Large join shuffles
- Long-running stages
- Task skew indicators

**How Users Can Use It**:
- **Optimization Guidance**: Get actionable suggestions for improving performance
- **Pattern Detection**: Identify common performance anti-patterns
- **Query Examples**:
  - Find stages with hints: `spark.semantic.performance.hint: *`
  - Find high-cardinality groupBy: `spark.semantic.performance.hint: *High-cardinality*`
  - Find large joins: `spark.semantic.performance.hint: *Large join*`

**Value Domain**:
- `performance.hint`: Semicolon-separated list of hint strings, common hints include:
  - `"High-cardinality groupBy - consider pre-aggregation"`
  - `"Large join shuffle - consider broadcast join if one side is small"`
  - `"Long-running stage (Xms) - investigate task skew"`
  - `"High shuffle volume - consider increasing partitions"`

**Example**:
```json
{
  "spark.semantic.performance.hint": "High-cardinality groupBy - consider pre-aggregation; Long-running stage (120000ms) - investigate task skew"
}
```

**Coverage**: Stages matching performance patterns (~10-20% of stages)

**Status**: ✅ Implemented (post-processing pipeline)

---

##### Execution Mode Enrichment

**Purpose**: Identify the execution mode used by Spark (codegen, shuffle exchange, etc.).

**Schema Representation**:
- `spark.semantic.execution.mode` (keyword): Execution mode
- `spark.semantic.partitioning.type` (keyword): Partitioning strategy (if applicable)

**What It Means**: Spark uses different execution modes:
- **Codegen**: Whole-stage code generation for optimized execution
- **Shuffle Exchange**: Shuffle-based data exchange
- **Hash Partitioning**: Hash-based partitioning for shuffles
- **Range Partitioning**: Range-based partitioning for shuffles

**How Users Can Use It**:
- **Performance Analysis**: Understand which execution modes are used
- **Optimization**: Identify opportunities to enable codegen
- **Query Examples**:
  - Find codegen stages: `spark.semantic.execution.mode: "codegen"`
  - Find hash partitioning: `spark.semantic.partitioning.type: "hash"`

**Value Domain**:
- `execution.mode`:
  - `codegen`: Whole-stage code generation
  - `shuffle_exchange`: Shuffle-based exchange
- `partitioning.type`:
  - `hash`: Hash partitioning
  - `range`: Range partitioning

**Example**:
```json
{
  "spark.semantic.execution.mode": "codegen",
  "spark.semantic.partitioning.type": "hash"
}
```

**Coverage**: Stages with identifiable execution modes (~50% of stages)

**Status**: ✅ Implemented (post-processing pipeline)

---

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

### Spark Span Schema

#### Spark-Specific Span Attributes

| Field | Type | Description | Operations |
|-------|------|-------------|------------|
| `spark.app.id` | keyword | Spark application ID | all |
| `spark.app.name` | keyword | Spark application name | all |
| `spark.user` | keyword | User running application | all |
| `spark.job.id` | long | Job ID | job, stage, task |
| `spark.job.stage.count` | long | Number of stages in job | job |
| `spark.job.result` | keyword | Job result | job |
| `spark.stage.id` | long | Stage ID | stage, task |
| `spark.stage.name` | text | Stage name | stage, task |
| `spark.stage.attempt` | long | Stage attempt number | stage |
| `spark.stage.num.tasks` | long | Number of tasks in stage | stage |
| `spark.stage.tasks.completed` | long | Tasks completed | stage |
| `spark.stage.result` | keyword | Stage result | stage |
| `spark.stage.is.retry` | boolean | Stage is a retry | stage |
| `spark.stage.shuffle.read.bytes` | long | Shuffle read bytes | stage |
| `spark.stage.shuffle.write.bytes` | long | Shuffle write bytes | stage |
| `spark.stage.input.bytes` | long | Input bytes read | stage |
| `spark.stage.output.bytes` | long | Output bytes written | stage |
| `spark.stage.memory.spilled.bytes` | long | Memory spilled to disk | stage |
| `spark.stage.disk.spilled.bytes` | long | Disk spilled | stage |
| `spark.task.id` | long | Task ID | task |
| `spark.task.index` | long | Task index within stage | task |
| `spark.task.executor.id` | keyword | Executor running task | task |
| `spark.sql.execution.id` | long | SQL execution ID | sql |

#### Enrichments

Spark spans are enriched with the same semantic information as events, stored as span attributes. These enrichments enable efficient querying and analysis of performance traces.

##### Stage Name Parsing Enrichment

**Purpose**: Extract operation type and source code location from Spark stage names for debugging and performance analysis.

**Schema Representation**:
- `spark.semantic.operation.type` (keyword): Specific operation extracted from stage name
- `spark.semantic.source.file` (keyword): Source file name extracted from stage name
- `spark.semantic.source.line` (long): Line number extracted from stage name

**What It Means**: Same as event enrichment - parses stage names to extract operation, file, and line number.

**How Users Can Use It**:
- **Trace Analysis**: Filter traces by source file or operation type
- **Performance Correlation**: Link slow spans to specific code locations
- **Query Examples**:
  - Find all spans from a file: `Attributes.spark.semantic.source.file: "Chapter_03.py"`
  - Find count operation spans: `Attributes.spark.semantic.operation.type: "count"`
  - Aggregate by operation: `GROUP BY Attributes.spark.semantic.operation.type`

**Value Domain**: Same as event enrichment (see Stage Name Parsing Enrichment in Event Schema)

**Example**:
```json
{
  "Attributes": {
    "spark.stage.name": "count at Chapter_03.py:41",
    "spark.semantic.operation.type": "count",
    "spark.semantic.source.file": "Chapter_03.py",
    "spark.semantic.source.line": 41
  }
}
```

**Coverage**: ~60% of stages

**Status**: ✅ Implemented

---

##### RDD Type Analysis Enrichment

**Purpose**: Extract RDD types from stage lineage to understand transformation chains.

**Schema Representation**:
- `spark.semantic.rdd.types` (keyword): Comma-separated list of RDD types
- `spark.semantic.rdd.count` (long): Number of RDDs in stage

**What It Means**: Same as event enrichment - extracts RDD types to understand transformation complexity.

**How Users Can Use It**:
- **Shuffle Detection**: Find spans with `ShuffledRDD` in attributes
- **Complexity Analysis**: Identify spans with many RDDs
- **Query Examples**:
  - Find shuffle spans: `Attributes.spark.semantic.rdd.types: *ShuffledRDD*`
  - Find complex spans: `Attributes.spark.semantic.rdd.count: >5`

**Value Domain**: Same as event enrichment (see RDD Type Analysis Enrichment in Event Schema)

**Example**:
```json
{
  "Attributes": {
    "spark.semantic.rdd.types": "MapPartitionsRDD,ShuffledRDD,MapPartitionsRDD",
    "spark.semantic.rdd.count": 3
  }
}
```

**Coverage**: ~95% of stages

**Status**: ✅ Implemented

---

##### Operation Classification Enrichment

**Purpose**: Automatically classify stage operations with confidence scoring.

**Schema Representation**:
- `spark.semantic.operation` (keyword): High-level operation classification
- `spark.semantic.confidence` (double): Classification confidence (0.0-1.0)
- `spark.semantic.low_confidence` (boolean): Flag for low confidence (< 0.7)

**What It Means**: Same as event enrichment - multi-signal classification with confidence scoring.

**How Users Can Use It**:
- **Performance Analysis**: Group spans by operation type
- **Anomaly Detection**: Flag low-confidence spans for review
- **Query Examples**:
  - Find aggregation spans: `Attributes.spark.semantic.operation: "aggregation"`
  - Find high-confidence spans: `Attributes.spark.semantic.confidence: >=0.7`
  - Find spans needing review: `Attributes.spark.semantic.low_confidence: true`

**Value Domain**: Same as event enrichment (see Operation Classification Enrichment in Event Schema)

**Example**:
```json
{
  "Attributes": {
    "spark.semantic.operation": "aggregation",
    "spark.semantic.confidence": 0.85,
    "spark.semantic.low_confidence": false
  }
}
```

**Coverage**: ~90% of stages

**Status**: ✅ Implemented

---

##### Shuffle Classification Enrichment

**Purpose**: Classify shuffle patterns and intensity for performance analysis.

**Schema Representation**:
- `spark.semantic.shuffle.classification` (keyword): Shuffle pattern
- `spark.semantic.shuffle.intensity` (keyword): Shuffle volume category
- `spark.semantic.shuffle.reason` (keyword): Inferred shuffle reason (post-processing)

**What It Means**: Same as event enrichment - classifies shuffle patterns and intensity.

**How Users Can Use It**:
- **Performance Optimization**: Find spans with high shuffle intensity
- **Cost Analysis**: Understand data movement patterns
- **Query Examples**:
  - Find shuffle producer spans: `Attributes.spark.semantic.shuffle.classification: "shuffle_producer"`
  - Find high-intensity shuffles: `Attributes.spark.semantic.shuffle.intensity: "very_high"`
  - Find expensive shuffles: `Attributes.spark.semantic.shuffle.intensity: "very_high" AND Duration: >60000000000`

**Value Domain**: Same as event enrichment (see Shuffle Classification Enrichment in Event Schema)

**Example**:
```json
{
  "Attributes": {
    "spark.semantic.shuffle.classification": "shuffle_producer",
    "spark.semantic.shuffle.intensity": "high",
    "spark.semantic.shuffle.reason": "groupby"
  }
}
```

**Coverage**: 100% of stages

**Status**: ✅ Implemented (classification, intensity); ⏳ Pending (reason - post-processing)

---

##### SQL Execution Plan Enrichment

**Purpose**: Capture SQL query information for DataFrame/SQL operations.

**Schema Representation**:
- `spark.sql.execution.id` (long): SQL execution ID
- `spark.sql.description` (text): SQL query text
- `spark.sql.physical_plan` (text): Physical execution plan

**What It Means**: Same as event enrichment - captures SQL execution details.

**How Users Can Use It**:
- **Query Analysis**: Understand SQL operations in traces
- **Plan Analysis**: Review execution plans
- **Query Examples**:
  - Find spans for SQL execution: `Attributes.spark.sql.execution.id: 13`
  - Find spans with SELECT: `Attributes.spark.sql.description: *SELECT*`

**Value Domain**: Same as event enrichment (see SQL Execution Plan Enrichment in Event Schema)

**Example**:
```json
{
  "Attributes": {
    "spark.sql.execution.id": 13,
    "spark.sql.description": "SELECT word, COUNT(*) FROM words GROUP BY word"
  }
}
```

**Coverage**: SQL/DataFrame operations only (~30-40% of stages)

**Status**: ✅ Implemented

---

##### Performance Hints Enrichment

**Purpose**: Generate performance optimization hints based on patterns.

**Schema Representation**:
- `spark.semantic.performance.hint` (text): Performance optimization suggestions

**What It Means**: Same as event enrichment - post-processing hints for optimization.

**How Users Can Use It**:
- **Optimization Guidance**: Get actionable suggestions
- **Query Examples**:
  - Find spans with hints: `Attributes.spark.semantic.performance.hint: *`
  - Find high-cardinality groupBy: `Attributes.spark.semantic.performance.hint: *High-cardinality*`

**Value Domain**: Same as event enrichment (see Performance Hints Enrichment in Event Schema)

**Example**:
```json
{
  "Attributes": {
    "spark.semantic.performance.hint": "High-cardinality groupBy - consider pre-aggregation"
  }
}
```

**Coverage**: Stages matching performance patterns (~10-20% of stages)

**Status**: ✅ Implemented (post-processing pipeline)

---

##### Execution Mode Enrichment

**Purpose**: Identify Spark execution modes (codegen, shuffle exchange).

**Schema Representation**:
- `spark.semantic.execution.mode` (keyword): Execution mode
- `spark.semantic.partitioning.type` (keyword): Partitioning strategy

**What It Means**: Same as event enrichment - identifies execution modes.

**How Users Can Use It**:
- **Performance Analysis**: Understand execution modes
- **Query Examples**:
  - Find codegen spans: `Attributes.spark.semantic.execution.mode: "codegen"`
  - Find hash partitioning: `Attributes.spark.semantic.partitioning.type: "hash"`

**Value Domain**: Same as event enrichment (see Execution Mode Enrichment in Event Schema)

**Example**:
```json
{
  "Attributes": {
    "spark.semantic.execution.mode": "codegen",
    "spark.semantic.partitioning.type": "hash"
  }
}
```

**Coverage**: Stages with identifiable execution modes (~50% of stages)

**Status**: ✅ Implemented (post-processing pipeline)

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
| 1.2 | 2025-11-17 | Restructured Spark schemas as subsections, added comprehensive enrichment documentation |


