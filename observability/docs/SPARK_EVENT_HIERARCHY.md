# Spark Event Pairs and Hierarchy

## Overview

This document maps SparkListener events to OpenTelemetry spans and defines the parent-child relationships in the Job-Stage-Task hierarchy.

## Event Pairs (Start/End)

### 1. Application Level
**Parent**: None (root of hierarchy)

| Event | Method | Status | Parent |
|-------|--------|--------|--------|
| `SparkListenerApplicationStart` | `onApplicationStart` | ✅ Implemented | None |
| `SparkListenerApplicationEnd` | `onApplicationEnd` | ✅ Implemented | None |

**Span Name**: `spark.application.{appName}`  
**Attributes**: `spark.app.name`, `spark.app.id`, `spark.user`

---

### 2. Job Level
**Parent**: Application

| Event | Method | Status | Parent |
|-------|--------|--------|--------|
| `SparkListenerJobStart` | `onJobStart` | ✅ Implemented | Application |
| `SparkListenerJobEnd` | `onJobEnd` | ✅ Implemented | Application |

**Span Name**: `spark.job.{jobId}`  
**Attributes**: `spark.job.id`, `spark.job.stage.count`, `spark.job.stages`, `spark.job.result`

**Note**: In Spark 4.0, stages don't directly reference their parent job ID. The relationship is maintained by tracking active jobs when stages are submitted.

---

### 3. Stage Level
**Parent**: Job (or Application if job context unavailable)

| Event | Method | Status | Parent |
|-------|--------|--------|--------|
| `SparkListenerStageSubmitted` | `onStageSubmitted` | ✅ Implemented | Job |
| `SparkListenerStageCompleted` | `onStageCompleted` | ✅ Implemented | Job |

**Span Name**: `spark.stage.{stageId}`  
**Attributes**: `spark.stage.id`, `spark.stage.name`, `spark.stage.num.tasks`, `spark.stage.attempt`, `spark.stage.shuffle.read.bytes`, `spark.stage.shuffle.write.bytes`, `spark.stage.input.bytes`, `spark.stage.output.bytes`, `spark.stage.memory.spilled.bytes`, `spark.stage.disk.spilled.bytes`, `spark.stage.result`

**Note**: Stage attempts are tracked separately. Retries create new spans with `spark.stage.is.retry=true`.

---

### 4. Task Level
**Parent**: Stage

| Event | Method | Status | Parent |
|-------|--------|--------|--------|
| `SparkListenerTaskStart` | `onTaskStart` | ✅ Implemented | Stage |
| `SparkListenerTaskEnd` | `onTaskEnd` | ✅ Implemented | Stage |

**Span Name**: `spark.task.{taskId}`  
**Attributes**: `spark.task.id`, `spark.task.index`, `spark.task.attempt`, `spark.task.stage.id`, `spark.task.executor.id`, `spark.task.executor.run.time.ms`, `spark.task.executor.cpu.time.ms`, `spark.task.result.size.bytes`, `spark.task.failure.reason`

**Note**: Currently creates spans for all tasks. Can be configured to only track failed tasks to reduce volume.

---

### 5. SQL Execution Level
**Parent**: Application (or Job if job context available)

| Event | Method | Status | Parent |
|-------|--------|--------|--------|
| `SparkListenerSQLExecutionStart` | `onSQLExecutionStart` | ✅ Implemented | Application |
| `SparkListenerSQLExecutionEnd` | `onSQLExecutionEnd` | ✅ Implemented | Application |

**Span Name**: `spark.sql.{executionId}`  
**Attributes**: `spark.sql.execution.id`, `spark.sql.description`, `spark.sql.details`, `spark.sql.physical.plan`

**Note**: SQL executions are independent of the Job-Stage-Task hierarchy. They can spawn jobs, but the relationship is not directly tracked in events.

**Linking Strategy**: SQL executions can be linked to jobs by:
- Matching SQL execution ID to job properties (if available)
- Using timestamps to correlate SQL start with job start
- Future enhancement: Track job IDs created by SQL execution

---

## Point-in-Time Events (No Pairs)

### Executor Lifecycle
**Parent**: Application

| Event | Method | Status | Parent |
|-------|--------|--------|--------|
| `SparkListenerExecutorAdded` | `onExecutorAdded` | ✅ Implemented | Application |
| `SparkListenerExecutorRemoved` | `onExecutorRemoved` | ✅ Implemented | Application |

**Span Name**: `spark.executor.{executorId}` / `spark.executor.{executorId}.removed`  
**Attributes**: `spark.executor.id`, `spark.executor.host`, `spark.executor.total.cores`, `spark.executor.removal.reason`

**Note**: These are point-in-time events (span created and ended immediately).

---

## Events Not Currently Implemented

### Block Manager Events
- `SparkListenerBlockManagerAdded` - Point-in-time
- `SparkListenerBlockManagerRemoved` - Point-in-time

**Rationale**: Low-level infrastructure events, not directly related to execution hierarchy.

### Environment Events
- `SparkListenerEnvironmentUpdate` - Point-in-time

**Rationale**: Configuration snapshot, not execution-related.

### Resource Profile Events
- `SparkListenerResourceProfileAdded` - Point-in-time

**Rationale**: Resource configuration, not execution-related.

### SQL Adaptive Execution Updates
- `SparkListenerSQLAdaptiveExecutionUpdate` - Point-in-time

**Rationale**: Query plan updates during execution. Could be added as span events (not separate spans).

### Driver Accumulator Updates
- `SparkListenerDriverAccumUpdates` - Point-in-time

**Rationale**: Metric updates, better suited for metrics than spans.

---

## Hierarchy Visualization

```
Application (root)
├── Job
│   ├── Stage
│   │   ├── Task
│   │   ├── Task
│   │   └── Task
│   └── Stage
│       ├── Task
│       └── Task
├── SQL Execution (independent, may spawn jobs)
│   └── [Jobs spawned by SQL are tracked separately]
└── Executor Added/Removed (point-in-time)
```

## Implementation Status

| Event Pair | Start Method | End Method | Status | Notes |
|------------|--------------|------------|--------|-------|
| Application | ✅ | ✅ | Complete | Root of hierarchy |
| Job | ✅ | ✅ | Complete | Parent: Application |
| Stage | ✅ | ✅ | Complete | Parent: Job (or Application) |
| Task | ✅ | ✅ | Complete | Parent: Stage |
| SQL Execution | ✅ | ✅ | Complete | Parent: Application (independent) |
| Executor | ✅ | ✅ | Complete | Point-in-time events |

## Linking SQL Executions to Jobs

**Current Limitation**: SQL executions are tracked independently from the Job-Stage-Task hierarchy.

**Potential Solutions**:

1. **Job Properties**: Check if `SparkListenerJobStart` includes SQL execution ID in properties
   ```scala
   jobStart.properties.getProperty("spark.sql.execution.id")
   ```

2. **Timestamp Correlation**: Match SQL execution start time with job start time (within tolerance)

3. **Stage Properties**: Check if stages include SQL execution ID
   ```scala
   stageInfo.properties.getProperty("spark.sql.execution.id")
   ```

4. **Future Enhancement**: Track SQL execution → Job mapping when jobs are created

## Recommendations

### High Priority
1. ✅ **Task Start/End**: Already implemented
2. ✅ **SQL Execution**: Already implemented
3. ✅ **Executor Lifecycle**: Already implemented

### Medium Priority
1. **SQL → Job Linking**: Implement correlation between SQL executions and spawned jobs
2. **Task Sampling**: Add configuration to sample tasks (only failed, or percentage-based)

### Low Priority
1. **Block Manager Events**: Add if infrastructure monitoring is needed
2. **SQL Adaptive Updates**: Add as span events (not separate spans) for query plan changes

## References

- [Spark Listener API](https://spark.apache.org/docs/latest/api/scala/org/apache/spark/scheduler/SparkListener.html)
- [Spark SQL Execution Listener](https://spark.apache.org/docs/latest/api/scala/org/apache/spark/sql/execution/ui/SparkListenerSQLExecutionStart.html)
- Logstash Pipeline: `observability/logstash/pipeline/logstash.conf` (lines 38-240)

