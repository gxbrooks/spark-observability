# Spark OpenTelemetry Listener

Custom SparkListener that exports Spark application telemetry to OpenTelemetry Collector via OTLP (OpenTelemetry Protocol).

## Features

- **Real-time telemetry**: Events pushed as they occur (< 1 second latency)
- **Distributed tracing**: Job → Stage → Task hierarchies as trace spans
- **Rich metrics**: Shuffle bytes, memory spills, execution times
- **Failure tracking**: Captures errors with full context
- **Parent-child relationships**: Proper span hierarchy
- **Resource attributes**: Service name, namespace, environment
- **Configurable**: Environment-based configuration
- **Production-ready**: Batching, error handling, proper shutdown

## Architecture

```
Spark Application
  ↓
OTelSparkListener (this JAR)
  ↓
OTLP Exporter (gRPC)
  ↓
OpenTelemetry Collector
  ↓
Elasticsearch / Jaeger / Tempo
  ↓
Grafana / Jaeger UI
```

## Building

### Prerequisites

- Java 17+
- Maven 3.6+
- Scala 2.13.16

### Build Command

```bash
cd spark-otel-listener
mvn clean package
```

This creates `target/spark-otel-listener-1.0.0.jar` with all dependencies bundled.

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTel Collector endpoint | `http://otel-collector.observability.svc.cluster.local:4317` |
| `OTEL_SERVICE_NAME` | Service name for traces | `spark-application` |
| `OTEL_SERVICE_NAMESPACE` | Service namespace | `spark` |
| `OTEL_DEPLOYMENT_ENVIRONMENT` | Deployment environment | `production` |

### Spark Configuration

#### spark-defaults.conf

```properties
# Enable the listener
spark.extraListeners=com.elastic.spark.otel.OTelSparkListener

# Path to JAR
spark.jars=/mnt/spark/jars/spark-otel-listener-1.0.0.jar

# OpenTelemetry endpoint
spark.driver.extraJavaOptions=-Dotel.exporter.otlp.endpoint=http://otel-collector:4317
spark.executor.extraJavaOptions=-Dotel.exporter.otlp.endpoint=http://otel-collector:4317
```

#### spark-submit

```bash
spark-submit \
  --conf spark.extraListeners=com.elastic.spark.otel.OTelSparkListener \
  --jars /path/to/spark-otel-listener-1.0.0.jar \
  --conf spark.driver.extraJavaOptions="-Dotel.exporter.otlp.endpoint=http://otel-collector:4317" \
  your-application.jar
```

#### Kubernetes ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: spark-configmap
  namespace: spark
data:
  OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel-collector.observability.svc.cluster.local:4317"
  OTEL_SERVICE_NAME: "spark-application"
  OTEL_SERVICE_NAMESPACE: "spark"
  OTEL_DEPLOYMENT_ENVIRONMENT: "production"
```

## Deployment

### Step 1: Build the JAR

```bash
mvn clean package
```

### Step 2: Upload to Shared Storage

```bash
# Copy to NFS
cp target/spark-otel-listener-1.0.0.jar /mnt/spark/jars/

# Or upload to S3
aws s3 cp target/spark-otel-listener-1.0.0.jar s3://your-bucket/jars/
```

### Step 3: Update Spark Configuration

Add to `spark-defaults.conf` or `spark-configmap.yaml`:

```properties
spark.extraListeners=com.elastic.spark.otel.OTelSparkListener
spark.jars=/mnt/spark/jars/spark-otel-listener-1.0.0.jar
```

### Step 4: Restart Spark Applications

```bash
# For Kubernetes deployments
kubectl rollout restart deployment spark-master -n spark
kubectl rollout restart deployment spark-worker-lab1 -n spark
kubectl rollout restart deployment spark-worker-lab2 -n spark
```

## Captured Events

### Application-Level
- Application start/end
- Application name, ID, user
- Total duration

### Job-Level
- Job start/end
- Number of stages
- Job success/failure
- Error messages

### Stage-Level
- Stage submission/completion
- Stage name, attempt number
- Number of tasks
- Shuffle read/write bytes
- Input/output bytes
- Memory/disk spills
- Stage success/failure

### Task-Level (Failed Tasks Only)
- Task ID, index, attempt
- Executor ID
- Execution time, CPU time
- Result size
- Failure reason

## Trace Hierarchy Example

```
Trace ID: abc123...
├─ span: spark.application.Chapter_07 (15m 32s)
   ├─ span: spark.job.0 (12m 45s)
      ├─ span: spark.stage.0 (5m 12s)
      │  └─ span: spark.task.42 (FAILED) (1m 5s)
      ├─ span: spark.stage.1 (7m 33s)
      └─ span: spark.stage.2 (2m 15s)
   └─ span: spark.job.1 (2m 47s)
      └─ span: spark.stage.3 (2m 40s)
```

## Span Attributes

### Application Span
- `spark.app.name`: Application name
- `spark.app.id`: Application ID
- `spark.user`: Spark user
- `service.name`: Service name (from config)

### Job Span
- `spark.job.id`: Job ID
- `spark.job.stage.count`: Number of stages
- `spark.job.result`: SUCCESS or FAILED
- `spark.job.error`: Error message (if failed)

### Stage Span
- `spark.stage.id`: Stage ID
- `spark.stage.name`: Stage name
- `spark.stage.num.tasks`: Total tasks
- `spark.stage.attempt`: Attempt number
- `spark.stage.is.retry`: True if retry
- `spark.stage.tasks.completed`: Completed tasks
- `spark.stage.shuffle.read.bytes`: Shuffle read
- `spark.stage.shuffle.write.bytes`: Shuffle write
- `spark.stage.input.bytes`: Input data
- `spark.stage.output.bytes`: Output data
- `spark.stage.memory.spilled.bytes`: Memory spills
- `spark.stage.disk.spilled.bytes`: Disk spills
- `spark.stage.result`: SUCCESS or FAILED
- `spark.stage.error`: Error message (if failed)

### Task Span (Failed Tasks Only)
- `spark.task.id`: Task ID
- `spark.task.index`: Task index
- `spark.task.attempt`: Attempt number
- `spark.task.stage.id`: Parent stage ID
- `spark.task.executor.id`: Executor ID
- `spark.task.executor.run.time.ms`: Execution time
- `spark.task.executor.cpu.time.ms`: CPU time
- `spark.task.result.size.bytes`: Result size
- `spark.task.failure.reason`: Failure reason

## Performance Considerations

### Batching
- Spans are batched before export (512 per batch)
- Max queue size: 2048 spans
- Export interval: 1 second

### Memory
- Minimal memory overhead (~10MB for listener)
- Async export doesn't block Spark execution
- Automatic cleanup of completed spans

### Network
- gRPC binary protocol (efficient)
- Compression enabled
- Retry with exponential backoff

### Sampling
- All application/job/stage events: 100%
- Task events: Failed tasks only (reduces volume)
- Can be customized via OTel Collector sampling

## Troubleshooting

### Listener Not Starting

Check Spark driver logs:
```bash
kubectl logs spark-master-0 -n spark | grep OTel
```

Expected output:
```
INFO OTelSparkListener: OTelSparkListener initialized - OTLP endpoint: http://otel-collector:4317, service: spark-application
```

### No Traces in Backend

1. **Check OTel Collector logs**:
```bash
kubectl logs -l app=otel-collector -n observability
```

2. **Verify network connectivity**:
```bash
# From Spark pod
kubectl exec spark-master-0 -n spark -- nc -zv otel-collector.observability 4317
```

3. **Check Elasticsearch for traces**:
```bash
curl -k -u elastic:password "https://es01:9200/otel-traces-*/_count"
```

### High Memory Usage

Reduce batch size in code:
```scala
.setMaxQueueSize(1024)  // from 2048
.setMaxExportBatchSize(256)  // from 512
```

### Missing Parent-Child Relationships

Ensure application span is created before jobs:
```bash
# Check logs for "Application started" before "Job started"
kubectl logs spark-master-0 -n spark | grep -E "Application|Job" | head -20
```

## Testing

### Unit Tests

```bash
mvn test
```

### Integration Test with Local Collector

1. Start local OTel Collector:
```bash
docker run -p 4317:4317 -v $(pwd)/otel-collector-config.yaml:/etc/otel/config.yaml \
  otel/opentelemetry-collector-contrib:latest
```

2. Run Spark application locally:
```bash
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4317"
spark-submit --class YourApp \
  --conf spark.extraListeners=com.elastic.spark.otel.OTelSparkListener \
  --jars target/spark-otel-listener-1.0.0.jar \
  your-app.jar
```

3. Check traces:
```bash
# If using Jaeger backend
open http://localhost:16686
```

## Compatibility

| Component | Version |
|-----------|---------|
| Spark | 4.0.1 |
| Scala | 2.13.16 |
| Java | 17+ |
| OpenTelemetry | 1.33.0 |
| OTLP Protocol | 1.0.0 |

## License

Proprietary - Elastic-on-Spark Project

## Support

For issues or questions:
1. Check logs (Spark driver, OTel Collector)
2. Verify configuration (endpoints, network)
3. Test with simple Spark application first
4. Review OpenTelemetry documentation

## Roadmap

- [ ] Task-level sampling configuration
- [ ] Metrics export (executor metrics, GC stats)
- [ ] SQL query tracking
- [ ] Custom business metrics
- [ ] Trace context propagation from upstream services
- [ ] Performance optimization for high-throughput jobs

## References

- [OpenTelemetry Specification](https://opentelemetry.io/docs/specs/otel/)
- [Spark Listener API](https://spark.apache.org/docs/latest/api/scala/org/apache/spark/scheduler/SparkListener.html)
- [OTLP Protocol](https://opentelemetry.io/docs/specs/otlp/)

