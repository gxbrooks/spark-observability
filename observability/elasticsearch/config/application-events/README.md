# Application Events Dataflow

## Overview

The `app-events-*` index contains Spark application events (Application, Job, Stage, Task, and SQL Execution) that are emitted directly from the Spark OTel Listener. Unlike the `batch-events-*` index which requires a matching watcher to pair START and END events from log files, the application events index is built from three types of events that are emitted synchronously by the OTel Listener with full context, eliminating the need for a matching watcher.

## Dataflow: Spark OTel Listener → Application Events Index

### 1. Event Generation in Spark OTel Listener

The `OTelSparkListener` captures Spark lifecycle events (application start/end, job start/end, stage start/end, task start/end, SQL execution start/end) and converts them into application events. For each Spark operation, the listener:

1. **On Start**: Creates a START event with `event.type = "start"` and `event.state = "open"`
2. **On End**: Creates an END event with `event.type = "end"` and `event.state = "closed"`, then immediately closes the corresponding START event
3. **Close Update**: Emits a close update operation to change the START event's state from "open" to "closed"

### 2. Event Emission via EventEmitter

The `EventEmitter` class handles batching and transmission of events to Elasticsearch:

- **Three Event Types**:
  1. **START Events**: Full application event documents with `event.type = "start"` and `event.state = "open"`
  2. **CLOSE_START Updates**: Update operations that modify existing START events, setting `event.state = "closed"` and `event.closed_by` ("end" or "parent")
  3. **END Events**: Full application event documents with `event.type = "end"` and `event.state = "closed"`

- **Ordered Bulk Transmission**: Events are buffered and sent in a single ordered bulk request:
  ```
  START events → CLOSE_START updates → END events
  ```
  
  This ordering ensures the "Close Invariant": START events are indexed before their close updates are applied.

- **Batching**: Events are flushed every 2.5 seconds (half the Grafana watcher polling interval of 5 seconds) to ensure continuous graph updates.

- **Refresh Policy**: All bulk requests use `refresh=wait_for` to ensure events are immediately searchable.

### 3. Index Structure

The `app-events-*` index contains documents with the following key fields:

- **`event.id`**: Unique identifier for each event
- **`event.type`**: Either "start" or "end"
- **`event.state`**: "open" (for start events) or "closed" (for start events that have been closed, or end events)
- **`event.closed_by`**: For start events, indicates how they were closed: "end" (matched END event) or "parent" (hierarchical closure)
- **`correlation.key`**: Hierarchical correlation key (e.g., `App:{appId}`, `Job:{appId}:{jobId}`) used to link START and END events
- **`correlation.start.event.id`**: In END events, references the corresponding START event ID
- **`operation.type`**: The type of Spark operation (app, job, stage, task, sql)
- **`operation.id`**: The identifier for the operation (appId, jobId, stageId, taskId, executionId)

## Three Types of Events in the Index

### 1. START Events

- **Document Type**: Index operation (creates new document)
- **Fields**:
  - `event.type = "start"`
  - `event.state = "open"`
  - `event.id`: Unique START event ID
  - `correlation.key`: Hierarchical correlation key
- **Purpose**: Marks the beginning of a Spark operation (application, job, stage, task, or SQL execution)
- **Lifecycle**: Initially created with `state = "open"`, later updated to `state = "closed"` when the operation completes

### 2. CLOSE_START Updates

- **Document Type**: Update operation (modifies existing START event)
- **Action**: Updates the START event document identified by `event.id`
- **Changes**:
  - Sets `event.state = "closed"`
  - Sets `event.closed_by = "end"` (when matched with END event) or `"parent"` (when closed hierarchically)
- **Purpose**: Closes START events when their corresponding END events arrive, or when parent events complete
- **Timing**: Emitted immediately after the corresponding END event is created

### 3. END Events

- **Document Type**: Index operation (creates new document)
- **Fields**:
  - `event.type = "end"`
  - `event.state = "closed"`
  - `event.id`: Unique END event ID
  - `event.duration`: Duration of the operation (if available)
  - `correlation.key`: Same correlation key as the corresponding START event
  - `correlation.start.event.id`: References the START event ID
- **Purpose**: Marks the completion of a Spark operation
- **Lifecycle**: Always created with `state = "closed"` (never needs updating)

## Why No Matching Watcher is Needed

Unlike the `batch-events-*` index, the `app-events-*` index does **not** require a matching watcher to pair START and END events. Here's why:

### 1. Synchronous Event Emission

The OTel Listener has full context when both START and END events occur:
- When a Spark operation starts, the listener immediately creates and queues a START event
- When the operation ends, the listener:
  1. Creates an END event
  2. Immediately calls `closeStartEvent()` to queue a close update
  3. Both events are sent in the same ordered bulk request

This synchronous emission ensures START and END events are always paired correctly.

### 2. In-Memory Correlation

The OTel Listener maintains in-memory metadata maps (`appEventMetadata`, `jobEventMetadata`, `stageEventMetadata`, `taskEventMetadata`, `sqlEventMetadata`) that store:
- The correlation key
- The START event ID
- The event type

When an END event is created, the listener:
1. Looks up the START event metadata using the correlation key
2. Retrieves the START event ID
3. Emits both the END event and the close update in the same flush cycle

### 3. Ordered Bulk Transmission

The `EventEmitter` maintains strict ordering in bulk requests:
```
[START events] → [CLOSE_START updates] → [END events]
```

This ordering, combined with `refresh=wait_for`, ensures:
- START events are indexed before their close updates
- The "Close Invariant" is maintained: START events exist before they are updated
- No "document missing" errors occur

### 4. Hierarchical Closure

For residual events (events that don't receive an `onEnd` callback due to errors), the listener performs hierarchical closure:
- When an application ends, it closes all open jobs, stages, tasks, and SQL queries
- When a job ends, it closes all open stages and tasks
- When a stage ends, it closes all open tasks

These closures are marked with `event.closed_by = "parent"` to distinguish them from normal closures (`event.closed_by = "end"`).

### Comparison with Batch Events

The `batch-events-*` index requires a matching watcher because:
- Events come from **log files** parsed by Logstash
- START and END events arrive **asynchronously** and **independently**
- There is **no in-memory context** linking them
- A watcher must **query** the index to find matching START/END pairs

The `app-events-*` index does not have these limitations:
- Events come **directly from the Spark listener** with full context
- START and END events are emitted **synchronously** in the same execution context
- **In-memory metadata** maintains the correlation
- **No querying needed** - the listener knows exactly which START event corresponds to each END event

## Event Correlation Keys

Events are correlated using hierarchical correlation keys. See [Spark_Event_Correlation_Keys.md](../../spark/otel-listener/docs/Spark_Event_Correlation_Keys.md) for details.

Key patterns:
- Application: `App:{appId}`
- Job: `Job:{appId}:{jobId}`
- Stage: `Stage:{appId}:{jobId}:{stageId}`
- Task: `Task:{appId}:{stageId}:{taskId}`
- SQL: `SQL:{appId}:{executionId}`

## Querying Open Events

To find open (unclosed) events in the index:

```json
{
  "query": {
    "bool": {
      "filter": [
        {"term": {"event.type": "start"}},
        {"term": {"event.state": "open"}}
      ]
    }
  }
}
```

These queries are used by:
- The `application-events-metrics` watcher to aggregate open event counts
- Grafana dashboards to display active operations
- Monitoring systems to track application health

## Summary

The application events index is built from three types of events (START, CLOSE_START update, END) that are emitted synchronously by the Spark OTel Listener with full in-memory context. This eliminates the need for a matching watcher, unlike the batch events index which processes asynchronous log file events. The ordered bulk transmission and in-memory correlation ensure reliable event pairing and closure.

