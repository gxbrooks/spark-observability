# Spark Push-Based Telemetry with OpenTelemetry

## Executive Summary

**Goal**: Replace file-based Spark event monitoring with push-based telemetry that bridges Spark's native instrumentation (SparkListener, History Server) into the OpenTelemetry ecosystem, then routes to Elasticsearch for storage and Grafana/Jaeger for visualization.

**Current State**: 
- Spark events written to files (`/mnt/spark/events`)
- Elastic Agent polls files every 10s
- Logstash processes events
- Elasticsearch stores with 5s watcher processing
- **Problem**: High latency (10-15s), file I/O overhead, complex processing pipeline

**Target State**:
- Spark emits telemetry directly via OTLP (OpenTelemetry Protocol)
- Real-time streaming to OpenTelemetry Collector
- Collector routes to multiple backends (Elasticsearch, Jaeger, Prometheus)
- Sub-second latency, simplified architecture

---

## Architecture Overview

### Current (File-Based)
```
Spark App → Event Log Files → Elastic Agent (10s poll) 
  → Logstash → Elasticsearch → Watchers (5s) 
  → batch-events/batch-metrics → Grafana
```

**Latency**: 15-20 seconds from event to visualization

### Proposed (Push-Based with OpenTelemetry)
```
Spark App → Custom SparkListener → OTLP Exporter 
  → OTel Collector → Elasticsearch/Jaeger/Tempo
  → Grafana/Jaeger UI
```

**Latency**: < 1 second from event to visualization

---

## Automated Deployment

The OpenTelemetry listener is fully automated via Ansible playbooks, following the project's "build from source" and "always automate" best practices.

### Build
```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/spark/otel-listener/build.yml
```

- Builds `spark-otel-listener-1.0.0.jar` using Maven
- Packages all dependencies (~5MB fat JAR)
- Copies to `spark/otel/` for distribution

### Deploy
```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/spark/otel-listener/deploy.yml
```

- Distributes JAR to all managed nodes via Ansible (not NFS)
- Copies to `/mnt/spark/data/spark-otel-listener-1.0.0.jar` (host path mounted into pods; matches `spark.jars` in cluster `spark-defaults`)
- See [FILE_DISTRIBUTION_STRATEGY.md](FILE_DISTRIBUTION_STRATEGY.md) for rationale

### Configure

Configuration is embedded in `spark-configmap.yaml` and `spark-defaults.conf.j2`:

```yaml
# spark-configmap.yaml
OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel-collector.observability.svc.cluster.local:4317"
OTEL_SERVICE_NAME: "spark-application"
OTEL_SERVICE_NAMESPACE: "spark"
OTEL_DEPLOYMENT_ENVIRONMENT: "production"
```

```properties
# spark-defaults.conf.j2
spark.extraListeners com.elastic.spark.otel.OTelSparkListener
spark.jars /mnt/spark/data/spark-otel-listener-1.0.0.jar
```

### Start/Stop

Standard Spark lifecycle:
```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/spark/stop.yml
ansible-playbook -i inventory.yml playbooks/spark/start.yml
```

---

## Key Components

### 1. Custom SparkListener

**Purpose**: Hook into Spark's internal event bus to capture all lifecycle events

**Events Captured**:
- Application start/end
- Job start/end
- Stage start/end
- Task start/end
- Executor add/remove
- SQL query execution
- Memory/GC metrics

**Implementation**: Scala/Java class implementing `org.apache.spark.scheduler.SparkListener`

### 2. OpenTelemetry Exporter

**Purpose**: Convert Spark events to OpenTelemetry spans/metrics

**Protocol**: OTLP (OpenTelemetry Protocol)
- OTLP/gRPC (preferred, efficient)
- OTLP/HTTP (fallback, firewall-friendly)

**Data Types**:
- **Traces**: Job/Stage/Task hierarchies as distributed traces
- **Metrics**: Executor metrics, memory, shuffle bytes
- **Logs**: Application logs (optional, can continue using Elastic Agent)

### 3. OpenTelemetry Collector

**Purpose**: Central hub for receiving, processing, and routing telemetry

**Capabilities**:
- Receive OTLP data from multiple Spark apps
- Enrich with resource attributes (cluster, namespace)
- Route to multiple backends simultaneously
- Buffer during backend downtime
- Sample high-volume data

**Deployment**: Kubernetes DaemonSet or standalone service

### 4. Storage Backends

#### Option A: Elasticsearch (Current)
- **Traces**: Stored as documents with parent-child relationships
- **Metrics**: Stored in time-series indices
- **Visualization**: Grafana dashboards (existing setup)

#### Option B: Jaeger (Trace-Specific)
- **Traces**: Native trace storage and UI
- **Benefits**: Purpose-built trace visualization, service maps
- **Limitation**: Traces only, not metrics

#### Option C: Grafana Tempo (Scalable)
- **Traces**: Object storage backend (S3, MinIO)
- **Benefits**: Cost-effective, massive scale
- **Integration**: Native Grafana support

#### Option D: Hybrid (Recommended)
- **Traces**: Jaeger or Tempo (fast queries, trace-optimized)
- **Metrics**: Elasticsearch (existing dashboards, complex queries)
- **Logs**: Elasticsearch (via Elastic Agent, unchanged)

---

## Implementation Phases

### Phase 1: Proof of Concept (1-2 weeks)

**Goal**: Demonstrate basic Spark → OTLP → Elasticsearch flow

**Deliverables**:
1. Custom SparkListener implementation
   - Capture Job/Stage/Task events
   - Generate OTLP spans
   - Export to local OTel Collector

2. OpenTelemetry Collector configuration
   - OTLP receiver (gRPC, port 4317)
   - Elasticsearch exporter
   - Basic resource attributes

3. Elasticsearch index templates
   - `otel-traces-*` for trace data
   - `otel-metrics-*` for metric data
   - Compatible with OpenTelemetry semantic conventions

4. Simple Grafana dashboard
   - Show Job execution traces
   - Display timing waterfalls
   - Compare with file-based data

**Success Criteria**:
- Spark job events appear in Elasticsearch within 1 second
- Trace spans show parent-child relationships
- Grafana displays trace data

### Phase 2: Production Deployment (2-3 weeks)

**Goal**: Deploy to Kubernetes cluster with all Spark applications

**Deliverables**:
1. OTel Collector as Kubernetes service
   - High availability (3 replicas)
   - Load balancing
   - Persistent queues for reliability

2. SparkListener JAR packaging
   - Custom JAR with dependencies
   - Upload to shared storage (NFS, S3)
   - Configure Spark to load JAR

3. Spark configuration updates
   - `spark.extraListeners` configuration
   - OTLP endpoint environment variables
   - Resource attributes (app name, cluster, etc.)

4. Elasticsearch mappings
   - Optimized for trace queries
   - ILM policies for retention
   - Index aliases for compatibility

5. Comprehensive Grafana dashboards
   - Job execution timelines
   - Stage/Task breakdowns
   - Resource utilization
   - Error rates and failures

**Success Criteria**:
- All Spark applications emit telemetry
- < 1 second latency end-to-end
- Zero data loss during normal operation
- Existing file-based monitoring can be disabled

### Phase 3: Advanced Features (3-4 weeks)

**Goal**: Enhanced observability with cross-service correlation

**Deliverables**:
1. Jaeger or Tempo integration
   - Dedicated trace backend
   - Service dependency maps
   - Trace search and filtering

2. Distributed tracing across services
   - Propagate trace context from client apps
   - Correlate Spark jobs with upstream services
   - End-to-end transaction tracking

3. Custom metrics
   - Business-level metrics (records processed, etc.)
   - Custom dimensions (dataset, partition, etc.)
   - Alerting rules

4. Sampling strategies
   - Head-based sampling for high-throughput jobs
   - Tail-based sampling for errors
   - Configurable sample rates

5. Integration with existing watchers
   - Trigger batch-match-join logic from OTLP data
   - Populate batch-traces via OTel spans
   - Backward compatibility with current dashboards

**Success Criteria**:
- Trace context flows from API → Spark → Database
- Service maps show complete application topology
- Advanced queries execute in < 5 seconds
- Sampling reduces data volume by 80% without losing errors

---

## Technical Design

### Custom SparkListener Implementation

```scala
package com.elastic.spark.otel

import org.apache.spark.scheduler._
import io.opentelemetry.api.trace._
import io.opentelemetry.sdk.trace.SdkTracerProvider
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor

class OTelSparkListener extends SparkListener {
  
  // Initialize OpenTelemetry
  private val spanExporter = OtlpGrpcSpanExporter.builder()
    .setEndpoint(sys.env.getOrElse("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317"))
    .build()
    
  private val tracerProvider = SdkTracerProvider.builder()
    .addSpanProcessor(BatchSpanProcessor.builder(spanExporter).build())
    .build()
    
  private val tracer = tracerProvider.get("spark-listener")
  
  // Track active spans
  private val jobSpans = collection.mutable.Map[Int, Span]()
  private val stageSpans = collection.mutable.Map[Int, Span]()
  
  override def onJobStart(jobStart: SparkListenerJobStart): Unit = {
    val span = tracer.spanBuilder(s"spark.job.${jobStart.jobId}")
      .setSpanKind(SpanKind.INTERNAL)
      .setAttribute("spark.job.id", jobStart.jobId)
      .setAttribute("spark.job.stage.count", jobStart.stageIds.length)
      .setAttribute("spark.app.name", sparkContext.appName)
      .startSpan()
    
    jobSpans(jobStart.jobId) = span
  }
  
  override def onJobEnd(jobEnd: SparkListenerJobEnd): Unit = {
    jobSpans.get(jobEnd.jobId).foreach { span =>
      span.setAttribute("spark.job.result", jobEnd.jobResult.toString)
      span.end()
      jobSpans.remove(jobEnd.jobId)
    }
  }
  
  override def onStageSubmitted(stageSubmitted: SparkListenerStageSubmitted): Unit = {
    val stageInfo = stageSubmitted.stageInfo
    val parentSpan = jobSpans.get(stageInfo.jobIds.head)
    
    val spanBuilder = tracer.spanBuilder(s"spark.stage.${stageInfo.stageId}")
      .setSpanKind(SpanKind.INTERNAL)
      .setAttribute("spark.stage.id", stageInfo.stageId)
      .setAttribute("spark.stage.name", stageInfo.name)
      .setAttribute("spark.stage.num.tasks", stageInfo.numTasks)
    
    parentSpan.foreach(parent => spanBuilder.setParent(Context.current().`with`(parent)))
    
    val span = spanBuilder.startSpan()
    stageSpans(stageInfo.stageId) = span
  }
  
  override def onStageCompleted(stageCompleted: SparkListenerStageCompleted): Unit = {
    val stageInfo = stageCompleted.stageInfo
    stageSpans.get(stageInfo.stageId).foreach { span =>
      span.setAttribute("spark.stage.tasks.completed", stageInfo.numTasks)
      span.setAttribute("spark.stage.tasks.failed", stageInfo.failureReason.size)
      span.setAttribute("spark.stage.shuffle.read.bytes", 
        stageInfo.taskMetrics.shuffleReadMetrics.totalBytesRead)
      span.setAttribute("spark.stage.shuffle.write.bytes",
        stageInfo.taskMetrics.shuffleWriteMetrics.bytesWritten)
      span.end()
      stageSpans.remove(stageInfo.stageId)
    }
  }
  
  override def onTaskStart(taskStart: SparkListenerTaskStart): Unit = {
    // Optionally emit task-level spans (can be high volume)
    // Consider sampling or only emitting failed tasks
  }
  
  override def onApplicationStart(applicationStart: SparkListenerApplicationStart): Unit = {
    // Emit application-level metrics
    val span = tracer.spanBuilder("spark.application")
      .setSpanKind(SpanKind.SERVER)
      .setAttribute("spark.app.name", applicationStart.appName)
      .setAttribute("spark.app.id", applicationStart.appId.getOrElse("unknown"))
      .setAttribute("spark.user", applicationStart.sparkUser)
      .startSpan()
    
    // Keep application span open for entire duration
    jobSpans(-1) = span
  }
  
  override def onApplicationEnd(applicationEnd: SparkListenerApplicationEnd): Unit = {
    jobSpans.get(-1).foreach { span =>
      span.end()
      jobSpans.remove(-1)
    }
    
    // Shutdown OpenTelemetry
    tracerProvider.shutdown()
  }
}
```

### OpenTelemetry Collector Configuration

```yaml
# otel-collector-config.yaml

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 1s
    send_batch_size: 1024
  
  resource:
    attributes:
      - key: service.namespace
        value: spark
        action: upsert
      - key: k8s.cluster.name
        value: lab-cluster
        action: upsert
  
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
  
  # Sample high-volume task spans
  probabilistic_sampler:
    sampling_percentage: 10
    hash_seed: 22

exporters:
  # Elasticsearch for traces
  elasticsearch:
    endpoints:
      - https://es01:9200
    auth:
      authenticator: basicauth
    user: elastic
    password: ${ELASTIC_PASSWORD}
    tls:
      insecure_skip_verify: true
    index: otel-traces
    mapping:
      mode: ecs
  
  # Elasticsearch for metrics
  elasticsearch/metrics:
    endpoints:
      - https://es01:9200
    auth:
      authenticator: basicauth
    user: elastic
    password: ${ELASTIC_PASSWORD}
    tls:
      insecure_skip_verify: true
    index: otel-metrics
  
  # Jaeger for trace visualization
  jaeger:
    endpoint: jaeger-collector:14250
    tls:
      insecure: true
  
  # Prometheus for metrics
  prometheusremotewrite:
    endpoint: http://prometheus:9090/api/v1/write
  
  # Debug logging
  logging:
    loglevel: info
    sampling_initial: 5
    sampling_thereafter: 200

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource, probabilistic_sampler]
      exporters: [elasticsearch, jaeger, logging]
    
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [elasticsearch/metrics, prometheusremotewrite]
```

### Spark Configuration

```properties
# spark-defaults.conf

# Enable custom listener
spark.extraListeners=com.elastic.spark.otel.OTelSparkListener

# JAR containing listener implementation
spark.jars=/mnt/spark/jars/spark-otel-listener-1.0.jar

# OpenTelemetry configuration
spark.driver.extraJavaOptions=-Dotel.exporter.otlp.endpoint=http://otel-collector.observability.svc.cluster.local:4317 \
  -Dotel.resource.attributes=service.name=spark-driver,deployment.environment=production

spark.executor.extraJavaOptions=-Dotel.exporter.otlp.endpoint=http://otel-collector.observability.svc.cluster.local:4317 \
  -Dotel.resource.attributes=service.name=spark-executor,deployment.environment=production

# OpenTelemetry environment variables (for Kubernetes deployment)
# Set via ConfigMap:
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.observability.svc.cluster.local:4317
OTEL_RESOURCE_ATTRIBUTES=service.namespace=spark,k8s.cluster.name=lab-cluster
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1
```

### Kubernetes Deployment

```yaml
# otel-collector-deployment.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
  namespace: observability
data:
  otel-collector-config.yaml: |
    # (Config from above)

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: otel-collector
  namespace: observability
spec:
  replicas: 3
  selector:
    matchLabels:
      app: otel-collector
  template:
    metadata:
      labels:
        app: otel-collector
    spec:
      containers:
      - name: otel-collector
        image: otel/opentelemetry-collector-contrib:0.91.0
        args: ["--config=/conf/otel-collector-config.yaml"]
        volumeMounts:
        - name: config
          mountPath: /conf
        ports:
        - containerPort: 4317  # OTLP gRPC
          name: otlp-grpc
        - containerPort: 4318  # OTLP HTTP
          name: otlp-http
        - containerPort: 8888  # Prometheus metrics
          name: metrics
        env:
        - name: ELASTIC_PASSWORD
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: password
        resources:
          requests:
            memory: "512Mi"
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      volumes:
      - name: config
        configMap:
          name: otel-collector-config

---
apiVersion: v1
kind: Service
metadata:
  name: otel-collector
  namespace: observability
spec:
  selector:
    app: otel-collector
  ports:
  - name: otlp-grpc
    port: 4317
    targetPort: 4317
  - name: otlp-http
    port: 4318
    targetPort: 4318
  - name: metrics
    port: 8888
    targetPort: 8888
  type: ClusterIP
```

---

## Elasticsearch Index Templates

### Traces Index Template

```json
{
  "index_patterns": ["otel-traces-*"],
  "template": {
    "settings": {
      "number_of_shards": 2,
      "number_of_replicas": 1,
      "index.lifecycle.name": "otel-traces-policy",
      "index.codec": "best_compression"
    },
    "mappings": {
      "properties": {
        "@timestamp": {"type": "date"},
        "trace_id": {"type": "keyword"},
        "span_id": {"type": "keyword"},
        "parent_span_id": {"type": "keyword"},
        "name": {"type": "keyword"},
        "kind": {"type": "keyword"},
        "start_time": {"type": "date"},
        "end_time": {"type": "date"},
        "duration_ms": {"type": "long"},
        "status_code": {"type": "keyword"},
        "attributes": {
          "type": "object",
          "dynamic": true,
          "properties": {
            "spark.job.id": {"type": "integer"},
            "spark.stage.id": {"type": "integer"},
            "spark.task.id": {"type": "long"},
            "spark.app.name": {"type": "keyword"},
            "service.name": {"type": "keyword"},
            "service.namespace": {"type": "keyword"}
          }
        },
        "resource": {
          "type": "object",
          "properties": {
            "service.name": {"type": "keyword"},
            "service.namespace": {"type": "keyword"},
            "k8s.cluster.name": {"type": "keyword"},
            "k8s.pod.name": {"type": "keyword"}
          }
        }
      }
    }
  }
}
```

---

## Migration Strategy

### Step 1: Parallel Operation (2-4 weeks)

Run both file-based and push-based systems simultaneously:
- Continue existing file-based monitoring
- Deploy OTel collector and custom listener
- Validate data consistency
- Compare latencies and data quality

### Step 2: Gradual Cutover (1-2 weeks)

Migrate dashboards one at a time:
- Create OTel-based versions of key dashboards
- Run A/B comparison
- Train users on new dashboards
- Keep file-based as fallback

### Step 3: Deprecation (1 week)

- Disable Elastic Agent file polling
- Remove Logstash event processing
- Disable batch-metrics watcher
- Keep file logging for disaster recovery

### Step 4: Cleanup (1 week)

- Remove old indices and mappings
- Archive historical file-based data
- Update documentation
- Optimize OTel configuration

---

## Benefits Analysis

### Current File-Based System

**Pros**:
- ✅ Well-understood, proven technology
- ✅ File-based audit trail
- ✅ Works with any Spark version

**Cons**:
- ❌ 15-20 second latency
- ❌ Complex processing pipeline (Agent → Logstash → ES → Watchers)
- ❌ File I/O overhead on shared NFS
- ❌ Difficult to correlate across services
- ❌ Limited to Spark-generated events

### Push-Based OpenTelemetry System

**Pros**:
- ✅ < 1 second latency
- ✅ Simplified architecture
- ✅ Industry-standard protocol (OTLP)
- ✅ Multi-backend support (ES, Jaeger, Tempo)
- ✅ Cross-service correlation (trace context propagation)
- ✅ Rich ecosystem of tools
- ✅ Better resource utilization (no file I/O)

**Cons**:
- ❌ Requires custom code (SparkListener)
- ❌ Additional JAR dependency
- ❌ Network dependency (OTLP endpoint must be available)
- ❌ Potential data loss if collector is down (mitigated by buffering)

---

## Risk Mitigation

### Risk 1: Data Loss During Collector Outage

**Mitigation**:
- OTel SDK has built-in retry and buffering
- Deploy collector with 3 replicas for high availability
- Use persistent queue exporter for critical data
- Keep file-based logging as backup for audit

### Risk 2: Performance Impact on Spark Jobs

**Mitigation**:
- Listener runs asynchronously
- Batch exporter reduces network calls
- Sampling reduces volume for high-throughput jobs
- Monitor listener overhead with metrics

### Risk 3: Compatibility with Spark Upgrades

**Mitigation**:
- Use stable Spark APIs (SparkListener interface rarely changes)
- Abstract OTel SDK behind interface layer
- Test with multiple Spark versions
- Maintain compatibility matrix

### Risk 4: Team Learning Curve

**Mitigation**:
- Comprehensive documentation
- Training sessions on OpenTelemetry concepts
- Side-by-side dashboards during migration
- Clear runbooks for troubleshooting

---

## Success Metrics

### Performance
- **Latency**: < 1 second from event to visualization
- **Throughput**: Handle 10,000 spans/second per collector
- **Overhead**: < 5% CPU impact on Spark executors
- **Availability**: 99.9% uptime for collector service

### Operational
- **Query Speed**: Trace queries in < 3 seconds
- **Data Retention**: 30 days hot, 90 days warm, 365 days cold
- **Dashboard Load Time**: < 2 seconds
- **Alert Latency**: < 30 seconds from event to alert

### Business
- **Mean Time to Detection (MTTD)**: < 2 minutes for job failures
- **Mean Time to Resolution (MTTR)**: Reduce by 40%
- **Developer Productivity**: 20% improvement in troubleshooting time
- **Cost**: Reduce storage costs by 30% through sampling

---

## Next Steps

### Immediate (This Sprint)
1. ✅ Research OpenTelemetry best practices
2. ✅ Design architecture and migration plan
3. ⏳ Set up development environment
4. ⏳ Implement basic SparkListener POC
5. ⏳ Deploy local OTel Collector

### Short Term (Next 2-4 Weeks)
1. Complete Phase 1 POC
2. Build SparkListener JAR
3. Deploy to test cluster
4. Create initial Grafana dashboards
5. Validate data accuracy vs file-based

### Medium Term (1-2 Months)
1. Production deployment (Phase 2)
2. Migrate existing dashboards
3. Deploy Jaeger for trace visualization
4. Implement sampling strategies
5. User training and documentation

### Long Term (3+ Months)
1. Cross-service tracing (Phase 3)
2. Advanced analytics and alerting
3. Cost optimization through tiered storage
4. Integration with other services (Kafka, databases)
5. Deprecate file-based monitoring

---

## References

### OpenTelemetry
- [OpenTelemetry Specification](https://opentelemetry.io/docs/specs/otel/)
- [OTLP Protocol](https://opentelemetry.io/docs/specs/otlp/)
- [Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)

### Spark
- [SparkListener API](https://spark.apache.org/docs/latest/api/scala/org/apache/spark/scheduler/SparkListener.html)
- [Monitoring Spark](https://spark.apache.org/docs/latest/monitoring.html)

### Visualization Tools
- [Jaeger](https://www.jaegertracing.io/)
- [Grafana Tempo](https://grafana.com/oss/tempo/)
- [SigNoz](https://signoz.io/)
- [Elastic APM](https://www.elastic.co/apm)

### Best Practices
- [OpenTelemetry Best Practices](https://opentelemetry.io/docs/concepts/instrumentation/)
- [Distributed Tracing Best Practices](https://newrelic.com/blog/best-practices/distributed-tracing-best-practices)

---

## Appendix: Example Traces

### Job Execution Trace
```
Trace ID: 7a8f3c2b9d1e4f5a
├─ Span: spark.application (15m 32s)
│  ├─ Span: spark.job.0 (12m 45s)
│  │  ├─ Span: spark.stage.0 (5m 12s)
│  │  │  └─ Span: spark.task.0 (45s)
│  │  │  └─ Span: spark.task.1 (42s)
│  │  │  └─ Span: spark.task.2 (48s)
│  │  ├─ Span: spark.stage.1 (7m 33s)
│  │  │  └─ Span: spark.task.3 (1m 15s)
│  │  │  └─ Span: spark.task.4 (1m 20s)
```

### Cross-Service Trace
```
Trace ID: a1b2c3d4e5f6g7h8
├─ Span: api.request (3.2s) [FastAPI]
│  ├─ Span: spark.application (2.8s) [Spark]
│  │  └─ Span: spark.job.0 (2.5s)
│  │     └─ Span: spark.stage.0 (2.2s)
│  │        └─ Span: postgres.query (0.5s) [PostgreSQL]
│  └─ Span: redis.cache (0.05s) [Redis]
```

This enables end-to-end visibility across your entire application stack!

