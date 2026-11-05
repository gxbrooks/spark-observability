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

- **Ordered Bulk Transmission**: All three event types are queued in a single unified buffer in their arrival order. When flushed (every 2.5 seconds), events are extracted from the buffer and sent to Elasticsearch in a single bulk request, maintaining their original arrival order. This ensures that START events are indexed before their corresponding close updates are applied (the "Close Invariant").

- **Batching**: Events are flushed every 2.5 seconds (half the Grafana watcher polling interval of 5 seconds) to ensure continuous graph updates.

- **Refresh Policy**: All bulk requests use `refresh=wait_for` to ensure events are immediately searchable.

### 3. Index Structure

The `app-events-*` index contains documents with the following key fields:

- **`event.id`**: Unique identifier for each event document
- **`event.type`**: Either `"start"` or `"end"` - distinguishes START event documents from END event documents
- **`event.state`**: 
  - For START events: Initially `"open"`, updated to `"closed"` via CLOSE_START update operation
  - For END events: Always `"closed"` (never changes)
- **`event.closed_by`**: Present only on START events where `event.state = "closed"`. Values:
  - `"end"`: START event was closed because its corresponding END event was received (normal closure)
  - `"parent"`: START event was closed hierarchically by a parent event (residual event closure)
- **`event.duration`**: Present on END events. Duration of the operation in nanoseconds
- **`correlation.key`**: Hierarchical correlation key (e.g., `App:{appId}`, `Job:{appId}:{jobId}`) used to link START and END events. See [Spark_Event_Correlation_Keys.md](../../spark/otel-listener/docs/Spark_Event_Correlation_Keys.md) for the full specification.
- **`correlation.start.event.id`**: Present on END events. References the `event.id` of the corresponding START event that this END event closes
- **`operation.type`**: The type of Spark operation: `"app"`, `"job"`, `"stage"`, `"task"`, or `"sql"`
- **`operation.id`**: The identifier for the operation (appId, jobId, stageId, taskId, executionId)
- **`operation.name`**: Human-readable name for the operation
- **`operation.result`**: Present on END events. `"SUCCESS"` or `"FAILED"` indicating the operation result
- **`operation.parent.id`**: For child events (jobs, stages, tasks), references the parent operation ID

## Three Types of Events in the Index

### 1. START Events

- **Document Type**: Index operation (creates new document)
- **Initial State**: 
  - `event.type = "start"`
  - `event.state = "open"`
  - `event.id`: Unique START event ID
  - `correlation.key`: Hierarchical correlation key
- **Purpose**: Marks the beginning of a Spark operation (application, job, stage, task, or SQL execution)
- **Lifecycle**: Initially created with `state = "open"`. When the operation completes, the START event is updated via a CLOSE_START update operation to set `state = "closed"` and `event.closed_by` to indicate how it was closed.

### 2. CLOSE_START Updates

- **Document Type**: Update operation (modifies existing START event document)
- **Action**: Updates the START event document identified by `event.id`
- **Fields Updated**:
  - `event.state`: Changed from `"open"` to `"closed"`
  - `event.closed_by`: Set to either:
    - `"end"`: The START event was closed because its corresponding END event was received (normal closure)
    - `"parent"`: The START event was closed hierarchically because its parent event completed (used for residual events that didn't receive their own END event)
- **Purpose**: Closes START events when their corresponding END events arrive, or when parent events complete (for residual events)
- **Timing**: Emitted in the same flush cycle as the corresponding END event, maintaining order so START events are indexed before their updates

### 3. END Events

- **Document Type**: Index operation (creates new document)
- **Fields**:
  - `event.type = "end"`
  - `event.state = "closed"` (always, never changes)
  - `event.id`: Unique END event ID
  - `event.duration`: Duration of the operation in nanoseconds (if available)
  - `correlation.key`: Same correlation key as the corresponding START event
  - `correlation.start.event.id`: References the START event ID that this END event closes
- **Purpose**: Marks the completion of a Spark operation
- **Lifecycle**: Always created with `state = "closed"` (never needs updating)

### The `event.closed_by` Field

The `event.closed_by` field is present only on START events that have been closed (i.e., where `event.state = "closed"`). It indicates how the START event was closed:

- **`"end"`**: The normal case. The START event was closed because its corresponding END event was received. This indicates a successful, matched pair of START and END events.

- **`"parent"`**: Used for residual events (events that didn't receive their own `onEnd` callback due to application failures, errors, or other issues). When a parent event completes (e.g., application ends, job ends, stage ends), it closes all open child events hierarchically. These closures are marked with `closed_by = "parent"` to distinguish them from normal closures.

This field enables analysis of event closure patterns and identification of events that didn't complete normally (those with `closed_by = "parent"`).

## Why No Matching Watcher is Needed

Unlike the `batch-events-*` index, the `app-events-*` index does **not** require a matching watcher to pair START and END events. Here's why:

### 1. Synchronous Event Emission with Full Context

The OTel Listener has full context when both START and END events occur:
- When a Spark operation starts, the listener immediately creates and queues a START event
- When the operation ends, the listener:
  1. Creates an END event
  2. Immediately queues a close update for the corresponding START event
  3. All events (START, close updates, END) are queued in their arrival order in a single buffer

This synchronous emission with full context ensures START and END events are always paired correctly without needing to query the index.

### 2. Ordered Transmission

All events are queued in a single unified buffer in their arrival order. When flushed to Elasticsearch:
- Events are extracted from the buffer atomically
- They are sent in a single bulk request, maintaining their original arrival order
- The bulk request uses `refresh=wait_for` to ensure events are indexed before the request completes

This ordering guarantees that START events are indexed before their corresponding close updates, maintaining the "Close Invariant": START events exist in the index before they are updated.

### 3. Hierarchical Closure for Residual Events

For residual events (events that don't receive an `onEnd` callback due to application failures, errors, or other issues), the listener performs hierarchical closure:
- When an application ends, it closes all open jobs, stages, tasks, and SQL queries
- When a job ends, it closes all open stages and tasks  
- When a stage ends, it closes all open tasks

These hierarchical closures are marked with `event.closed_by = "parent"` in the index, distinguishing them from normal closures (`event.closed_by = "end"`).

### Comparison with Batch Events

The `batch-events-*` index requires a matching watcher because:
- Events come from **log files** parsed by Logstash
- START and END events arrive **asynchronously** and **independently**
- There is **no in-memory context** linking them
- A watcher must **query** the index to find matching START/END pairs

The `app-events-*` index does not have these limitations:
- Events come **directly from the Spark listener** with full context
- START and END events are emitted **synchronously** in the same execution context
- The listener maintains **in-memory correlation** between START and END events
- **No querying needed** - the listener knows exactly which START event corresponds to each END event and emits the close update immediately

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

