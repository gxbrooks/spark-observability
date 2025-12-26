# Spark Event Correlation Keys

## Overview

Correlation keys are used to uniquely identify and link START and END events for Spark application events (Application, Job, Stage, Task, and SQL Execution). These keys enable tracing events through the execution hierarchy and matching corresponding START and END events.

## Correlation Key Format

### Design Principles

1. **Hierarchical Structure**: Correlation keys use a hierarchical format where each level includes its type prefix and ID, separated by pipe (`|`) characters. This allows for clear prefix matching when identifying child events.

2. **Type Prefixes**: Each component in the correlation key is prefixed with its type (App, Job, Stage, Task, SQL) followed by a colon (`:`) and its ID. This avoids name conflicts (e.g., a Job ID could conflict with a SQL execution ID).

3. **Pipe Separator**: Pipe characters (`|`) are used as level separators between key components, while colons (`:`) separate type names from IDs. This format:
   - Makes hierarchical relationships explicit and easy to parse
   - Enables reliable prefix matching for finding child events
   - Avoids string slicing and parsing errors
   - Stays within Elasticsearch field length limits (see [Elasticsearch Limits](#elasticsearch-limits) below)

## Correlation Key Patterns

### 1. Application Events
- **Pattern**: `App:{appId}`
- **Example**: `App:app-20251222104624-0178`
- **Definition**: Event type prefix "App" followed by the application ID (provided by Spark or generated if missing)

### 2. Job Events
- **Pattern**: `App:{appId}|Job:{jobId}`
- **Example**: `App:app-20251222104624-0178|Job:46`
- **Helper Function**: `jobKey(appId, jobId)`

### 3. Stage Events
- **Pattern**: `App:{appId}|Job:{jobId}|Stage:{stageId}`
- **Example**: `App:app-20251222104624-0178|Job:46|Stage:86`
- **Helper Function**: `stageKey(appId, jobId, stageId)`
- **Note**: Stages always have a parent Job per SPARK_EVENT_HIERARCHY.md

### 4. Task Events
- **Pattern**: `App:{appId}|Job:{jobId}|Stage:{stageId}|Task:{taskId}`
- **Example**: `App:app-20251222104624-0178|Job:46|Stage:86|Task:143`
- **Helper Function**: `taskKey(stageCorrelationKey, taskId)`
- **Note**: Task keys extend the stage's correlation key by appending `|Task:{taskId}`

### 5. SQL Query Events
- **Pattern**: `App:{appId}|SQL:{executionId}`
- **Example**: `App:app-20251222104624-0178|SQL:15`
- **Helper Function**: `sqlKey(appId, executionId)`

## Event Hierarchy

The correlation keys reflect Spark's execution hierarchy with explicit type prefixes at each level:

```
Application: App:{appId}
├── Job: App:{appId}|Job:{jobId}
│   └── Stage: App:{appId}|Job:{jobId}|Stage:{stageId}
│       └── Task: App:{appId}|Job:{jobId}|Stage:{stageId}|Task:{taskId}
└── SQL: App:{appId}|SQL:{executionId}
```

### Key Structure by Event Type

| Event Type | Levels | Pattern |
|------------|--------|---------|
| Application | 1 | `App:{appId}` |
| Job | 2 | `App:{appId}\|Job:{jobId}` |
| Stage | 3 | `App:{appId}\|Job:{jobId}\|Stage:{stageId}` |
| Task | 4 | `App:{appId}\|Job:{jobId}\|Stage:{stageId}\|Task:{taskId}` |
| SQL | 2 | `App:{appId}\|SQL:{executionId}` |

### Why Type Prefixes and Pipe Separators Matter

The hierarchical format with type prefixes and pipe separators provides several benefits:

1. **Uniqueness**: Without type prefixes, name conflicts can occur. For example, a Job with ID `46` and a SQL execution with execution ID `46` would conflict. With prefixes:
   - Job: `App:app-20251222104624-0178|Job:46`
   - SQL: `App:app-20251222104624-0178|SQL:46`

2. **Hierarchical Matching**: The pipe-separated format enables reliable prefix matching. To find all child stages of a job, we can search for keys that start with the job's correlation key followed by `|Stage:`. This avoids string slicing and parsing errors.

3. **Clear Structure**: Each level's type is explicit, making the hierarchy immediately apparent and eliminating ambiguity about which component is which.

## Elasticsearch Limits

When constructing correlation keys, it is essential to ensure their length does not exceed Elasticsearch field limits:

- **Keyword Field Default**: Elasticsearch `keyword` fields have an `ignore_above` parameter set to **256 characters** by default. Strings longer than 256 characters will not be indexed.

- **Lucene Term Limit**: Elasticsearch is built on Apache Lucene, which imposes a maximum term byte-length of **32,766 bytes**. This effectively means a single term cannot exceed this length.

### Example Key Lengths

**Pipe-Separated Format Examples**:
- Application: `App:app-20251222104624-0178` (29 characters)
- Job: `App:app-20251222104624-0178|Job:46` (38 characters)
- Stage: `App:app-20251222104624-0178|Job:46|Stage:86` (49 characters)
- Task: `App:app-20251222104624-0178|Job:46|Stage:86|Task:143` (60 characters)
- SQL: `App:app-20251222104624-0178|SQL:15` (38 characters)

All examples stay well within the 256-character default limit while maintaining clear hierarchical structure, uniqueness, and type safety.

## Implementation

Correlation key helper functions are defined in `OTelSparkListener.scala`. The implementation uses type prefixes at each level, pipe separators between levels, and colons to separate type names from IDs.

```scala
// Correlation key helpers using hierarchical format with pipe separators
// Format: App:{AppID}|Job:{JobId}|Stage:{StageID}|Task:{TaskID}
private def appKey(appId: String): String = s"App:$appId"
private def jobKey(appId: String, jobId: Int): String = s"App:$appId|Job:$jobId"
private def stageKey(appId: String, jobId: Int, stageId: Int): String = s"App:$appId|Job:$jobId|Stage:$stageId"
private def taskKey(stageCorrelationKey: String, taskId: Long): String = s"$stageCorrelationKey|Task:$taskId"
private def sqlKey(appId: String, executionId: Long): String = s"App:$appId|SQL:$executionId"
```

Note: The `taskKey` function takes the stage's correlation key as input, extending it to include the task ID. This ensures the full hierarchy is preserved.

## Usage

Correlation keys are used to:

1. **Match START and END Events**: The same correlation key is used for both the START and END events of a given Spark operation, enabling reliable event pairing.

2. **Track Event Hierarchy**: The hierarchical structure allows tracing from application → job → stage → task, or application → SQL execution.

3. **Enable Event Correlation**: The `correlation.key` field in application events is used by Elasticsearch queries and Grafana dashboards to identify open events and calculate metrics.

4. **Ensure Uniqueness**: Including the event type prefix and `appId` in all keys ensures that events from different Spark application runs or different event types are distinct, even if they have the same numeric IDs.

5. **Hierarchical Event Closing**: When parent events complete (e.g., application ends), correlation keys enable finding and closing all residual child events (jobs, stages, tasks, SQL queries) by prefix matching on the correlation key structure. The pipe-separated format makes prefix matching reliable and efficient. Events closed via hierarchical closure are marked with `event.closed_by = "parent"` to distinguish them from events closed by their matching END event (`event.closed_by = "end"`).

6. **Residual Event Closure**: The hierarchical closing functions (`appCloseResidualChildren`, `jobCloseResidualChildren`, `stageCloseResidualChildren`) use TrieMap iterators to find events that still exist in metadata maps (indicating they have START events but no corresponding END events). These are closed with `closed_by = "parent"` before the parent event itself is closed with `closed_by = "end"`.
