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

## Building

### Prerequisites

- Java 17+
- Maven 3.6+
- Scala 2.13.16

### Build via Ansible

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/spark/build-otel-listener.yml
```

### Manual Build

```bash
cd spark/otel/spark-otel-listener
mvn clean package
```

This creates `target/spark-otel-listener-1.0.0.jar` with all dependencies bundled (~5MB).

## Deployment

Deployment is automated via Ansible playbooks:

1. **Build**: `ansible/playbooks/spark/build-otel-listener.yml`
2. **Deploy**: Integrated into `ansible/playbooks/spark/deploy.yml`
3. **Configure**: Integrated into Spark ConfigMap

The JAR is distributed to each managed node via Ansible at:
- **Managed nodes**: `/home/ansible/spark/otel/spark-otel-listener-1.0.0.jar`

## Configuration

Configuration is managed via Kubernetes ConfigMap (`spark-configmap.yaml`):

```yaml
OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel-collector.observability.svc.cluster.local:4317"
OTEL_SERVICE_NAME: "spark-application"
OTEL_SERVICE_NAMESPACE: "spark"
OTEL_DEPLOYMENT_ENVIRONMENT: "production"
```

Spark configuration in `spark-defaults.conf`:

```properties
spark.extraListeners=com.elastic.spark.otel.OTelSparkListener
spark.jars=/home/ansible/spark/otel/spark-otel-listener-1.0.0.jar
```

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
Elasticsearch
  ↓
Grafana / Kibana
```

## Captured Events

### Application-Level
- Application start/end, name, ID, user, total duration

### Job-Level
- Job start/end, number of stages, success/failure, error messages

### Stage-Level
- Stage submission/completion, name, attempt number
- Number of tasks, shuffle read/write bytes, input/output bytes
- Memory/disk spills, success/failure

### Task-Level (Failed Tasks Only)
- Task ID, index, attempt, executor ID
- Execution time, CPU time, result size, failure reason

## Benefits vs File-Based Telemetry

| Metric | File-Based | OTel Push | Improvement |
|--------|-----------|-----------|-------------|
| Latency | 15-20s | < 1s | **15-20x faster** |
| Components | 5 | 2 | **60% simpler** |
| File I/O | Heavy | None | **Eliminated** |
| Standards | Custom | OTLP | **Portable** |

## Troubleshooting

Check Spark driver logs:
```bash
kubectl logs spark-master-0 -n spark | grep OTel
```

Expected output:
```
INFO OTelSparkListener: OTelSparkListener initialized - OTLP endpoint: http://otel-collector:4317, service: spark-application
```

## Compatibility

| Component | Version |
|-----------|---------|
| Spark | 4.0.1 |
| Scala | 2.13.16 |
| Java | 17+ |
| OpenTelemetry | 1.33.0 |

## References

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Spark Listener API](https://spark.apache.org/docs/latest/api/scala/org/apache/spark/scheduler/SparkListener.html)
- [OTLP Specification](https://opentelemetry.io/docs/specs/otlp/)
- [Architecture Documentation](../../../docs/SPARK_OTEL_PUSH_TELEMETRY.md)

