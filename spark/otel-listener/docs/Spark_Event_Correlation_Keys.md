# Spark Event Correlation Keys

## Overview

Correlation keys are used to uniquely identify and link START and END events for Spark application events (Application, Job, Stage, Task, and SQL Execution). These keys enable tracing events through the execution hierarchy and matching corresponding START and END events.

## Correlation Key Format

### Design Principles

1. **Event Type Prefix**: All correlation keys are prefixed with the event type (App, Job, Stage, Task, SQL) separated by a colon (`:`) to avoid name conflicts. For example, a Job ID could conflict with a SQL execution ID if they have the same numeric value. The type prefix ensures uniqueness.

2. **appId Inclusion**: All correlation keys include the `appId` to ensure uniqueness across different Spark application runs.

3. **Colon Separator**: Colons (`:`) are used as separators between key components for:
   - Shorter, more efficient key names
   - Better readability
   - Avoiding Elasticsearch field length limits (see [Elasticsearch Limits](#elasticsearch-limits) below)

## Correlation Key Patterns

### 1. Application Events
- **Pattern**: `App:{appId}`
- **Example**: `App:app-20251222104624-0178`
- **Components**: 2 (EventType:appId)
- **Definition**: Event type prefix "App" followed by the application ID (provided by Spark or generated if missing)

### 2. Job Events
- **Pattern**: `Job:{appId}:{jobId}`
- **Example**: `Job:app-20251222104624-0178:46`
- **Components**: 3 (EventType:appId:jobId)
- **Helper Function**: `jobKey(appId, jobId)`

### 3. Stage Events
- **Pattern**: `Stage:{appId}:{jobId}:{stageId}`
- **Example**: `Stage:app-20251222104624-0178:46:86`
- **Components**: 4 (EventType:appId:jobId:stageId)
- **Helper Function**: `stageKey(appId, jobId, stageId)`
- **Fallback**: `Stage:{appId}:{stageId}` if job context is unavailable

### 4. Task Events
- **Pattern**: `Task:{appId}:{stageId}:{taskId}`
- **Example**: `Task:app-20251222104624-0178:86:143`
- **Components**: 4 (EventType:appId:stageId:taskId)
- **Helper Function**: `taskKey(appId, stageId, taskId)`
- **Note**: StageId is unique within an application, so jobId is not required for task keys.

### 5. SQL Query Events
- **Pattern**: `SQL:{appId}:{executionId}`
- **Example**: `SQL:app-20251222104624-0178:15`
- **Components**: 3 (EventType:appId:executionId)
- **Helper Function**: `sqlKey(appId, executionId)`

## Event Hierarchy

The correlation keys reflect Spark's execution hierarchy:

```
Application: App:{appId}
├── Job: Job:{appId}:{jobId}
│   └── Stage: Stage:{appId}:{jobId}:{stageId}
│       └── Task: Task:{appId}:{stageId}:{taskId}
└── SQL: SQL:{appId}:{executionId}
```

### Component Count by Event Type

| Event Type | Components | Pattern |
|------------|-----------|---------|
| Application | 2 | `App:{appId}` |
| Job | 3 | `Job:{appId}:{jobId}` |
| Stage | 4 | `Stage:{appId}:{jobId}:{stageId}` |
| Task | 4 | `Task:{appId}:{stageId}:{taskId}` |
| SQL | 3 | `SQL:{appId}:{executionId}` |

### Why Event Type Prefixes Matter

Without event type prefixes, name conflicts can occur. For example:
- A Job with ID `46` and a SQL execution with execution ID `46` would both generate the key `app-20251222104624-0178:46`
- This would cause conflicts when storing metadata in maps or querying Elasticsearch

By prefixing with the event type, we ensure uniqueness:
- Job: `Job:app-20251222104624-0178:46`
- SQL: `SQL:app-20251222104624-0178:46`

## Elasticsearch Limits

When constructing correlation keys, it is essential to ensure their length does not exceed Elasticsearch field limits:

- **Keyword Field Default**: Elasticsearch `keyword` fields have an `ignore_above` parameter set to **256 characters** by default. Strings longer than 256 characters will not be indexed.

- **Lucene Term Limit**: Elasticsearch is built on Apache Lucene, which imposes a maximum term byte-length of **32,766 bytes**. This effectively means a single term cannot exceed this length.

### Example Key Lengths

**New Format Examples**:
- Application: `App:app-20251222104624-0178` (29 characters)
- Job: `Job:app-20251222104624-0178:46` (32 characters)
- Stage: `Stage:app-20251222104624-0178:46:86` (35 characters)
- Task: `Task:app-20251222104624-0178:86:143` (36 characters)
- SQL: `SQL:app-20251222104624-0178:15` (31 characters)

All examples stay well within the 256-character default limit while maintaining readability, uniqueness, and type safety.

## Implementation

Correlation key helper functions are defined in `OTelSparkListener.scala`. The current implementation uses event type prefixes, colon separators, and includes `appId` in all keys for hierarchical matching and uniqueness across application runs.

```scala
// Correlation key helpers using event type prefix, colon separator, and appId for uniqueness
// Format: EventType:{appId}:{id1}:{id2}... to avoid name conflicts and ensure uniqueness
private def taskKey(appId: String, stageId: Int, taskId: Long): String = s"Task:$appId:$stageId:$taskId"
private def stageKey(appId: String, jobId: Int, stageId: Int): String = s"Stage:$appId:$jobId:$stageId"
private def jobKey(appId: String, jobId: Int): String = s"Job:$appId:$jobId"
private def sqlKey(appId: String, executionId: Long): String = s"SQL:$appId:$executionId"
```

## Usage

Correlation keys are used to:

1. **Match START and END Events**: The same correlation key is used for both the START and END events of a given Spark operation, enabling reliable event pairing.

2. **Track Event Hierarchy**: The hierarchical structure allows tracing from application → job → stage → task, or application → SQL execution.

3. **Enable Event Correlation**: The `correlation.key` field in application events is used by Elasticsearch queries and Grafana dashboards to identify open events and calculate metrics.

4. **Ensure Uniqueness**: Including the event type prefix and `appId` in all keys ensures that events from different Spark application runs or different event types are distinct, even if they have the same numeric IDs.

5. **Hierarchical Event Closing**: When parent events complete (e.g., application ends), correlation keys enable finding and closing all child events (jobs, stages, tasks, SQL queries) by prefix matching on the correlation key structure. Events closed via hierarchical closure are marked with `event.closed_by = "parent"` to distinguish them from events closed by their matching END event (`event.closed_by = "end"`).
