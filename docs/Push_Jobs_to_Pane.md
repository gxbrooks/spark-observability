# Push-Based Spark Telemetry - OpenTelemetry Architecture

## **Overview**

Push-based telemetry uses OpenTelemetry to export Spark lifecycle events as distributed traces in real-time, providing sub-second latency for observability dashboards.

---

## **Architecture Diagram**

```
Spark Application (with OTel Listener)
    ↓ (OTLP/gRPC)
OpenTelemetry Collector (K8s)
    ↓ (HTTPS)
Elasticsearch (otel-traces-* indices)
    ↓ (queried)
Grafana / Kibana (trace visualization)
```

---

## **Data Flow**

### **Stage 1: Spark Application**

**Actor**: Custom SparkListener (`OTelSparkListener`)

**Inputs**: 
- Spark internal events (`onApplicationStart`, `onJobStart`, etc.)
- Configuration: Environment variables

**Operations**:
- Converts Spark events → OpenTelemetry spans
- Maintains parent-child relationships (Application → Job → Stage → Task)
- Exports via OTLP/gRPC to collector endpoint

**Outputs**:
- Protocol: OTLP/gRPC  
- Destination: `OTEL_EXPORTER_OTLP_ENDPOINT`
- Format: OpenTelemetry spans with attributes

**Configuration** (See: `spark/otel-listener/src/main/scala/com/elastic/spark/otel/OTelSparkListener.scala`):
- Service name: `OTEL_SERVICE_NAME` (spark-application)
- Endpoint: `http://otel-collector.observability.svc.cluster.local:4317`

---

### **Stage 2: OpenTelemetry Collector**

**Actor**: OTel Collector deployment (3 replicas in K8s)

**Inputs**:
- Port: 4317 (gRPC), 4318 (HTTP)
- Format: OTLP spans

**Operations**:
- Receives spans from multiple Spark applications
- Batches for efficient export (batch size: 1024, timeout: 1s)
- Enriches with resource attributes (k8s.cluster.name, service.namespace)
- Memory limiting (512 MiB)

**Outputs**:
- Destination: Elasticsearch at `https://GaryPC.local:9200`
- Index: `otel-traces-<date>`
- Format: Elasticsearch documents

**Configuration** (See: `observability/otel-collector/otel-collector-deployment.yaml`, lines 17-66)

---

### **Stage 3: Elasticsearch**

**Actor**: Elasticsearch cluster

**Inputs**:
- Index pattern: `otel-traces-*`
- Documents: OpenTelemetry span documents

**Operations**:
- Indexes span data with trace hierarchy
- ILM policy manages retention (hot → warm → cold → delete)
- Supports distributed trace queries

**Key Fields**:
- `trace.id`: Unique trace identifier
- `span.id`: Unique span identifier  
- `parent.id`: Parent span for hierarchy
- `span.name`: Operation name (e.g., "spark.job.1")
- Custom attributes: `spark.app.id`, `spark.job.id`, etc.

**Configuration** (See: `observability/elasticsearch/otel-traces/`):
- Template: `otel-traces.template.json`
- ILM Policy: `otel-traces.ilm-policy.json`
- Data View: `otel-traces.dataview.json`

---

### **Stage 4: Visualization**

**Actors**: Grafana (future) / Kibana

**Inputs**:
- Index: `otel-traces-*`  
- Time range: Dashboard selection

**Operations**:
- Query spans by attributes
- Reconstruct trace hierarchy
- Calculate metrics (span count, duration, error rate)

**Visualization Options**:
- Trace timeline (Jaeger-style)
- Service map (APM-style)
- Custom panels (span count by app/job/stage)

**Status**: Infrastructure deployed, visualization TBD

---

## **Key Advantages**

| Aspect | File-Based | Push-Based (OTel) |
|--------|------------|-------------------|
| **Latency** | 30-60 seconds | < 1 second |
| **Complexity** | High (5 stages) | Low (3 stages) |
| **Resource Usage** | File I/O + NFS | Memory + Network |
| **Spark Integration** | Native (EventLog) | Custom listener |
| **Standards Compliance** | Proprietary | OpenTelemetry (vendor-agnostic) |
| **Client-Mode Support** | ✅ Yes | ❌ No (DNS issue) |
| **Cluster-Mode Support** | ✅ Yes | ✅ Yes |

---

## **Current Status**

### **Deployed Components**

✅ **OTel Listener**: Built and deployed  
✅ **OTel Collector**: Running in K8s (3 replicas)  
✅ **Elasticsearch**: Index template and ILM policy configured  
✅ **Kibana**: Data view created

### **Active For**

✅ **Cluster-mode apps**: Fully operational  
❌ **Client-mode apps**: Disabled (driver runs outside K8s, can't resolve internal DNS)

### **Next Steps**

1. Run cluster-mode Spark application to test
2. Build Grafana panels for OTel trace data
3. Consider NodePort for client-mode access (See: `tmp/986_requirements_and_otel_fixes.md`)

---

## **Related Documentation**

- **Implementation Details**: `docs/SPARK_OTEL_PUSH_TELEMETRY.md`
- **Listener Code**: `spark/otel-listener/src/main/scala/com/elastic/spark/otel/OTelSparkListener.scala`
- **Deployment Manifests**: `observability/otel-collector/otel-collector-deployment.yaml`
- **Compilation Fixes**: `tmp/989_otel_compilation_fixes.md`

---

**Status**: ✅ **Deployed** - Ready for cluster-mode Spark applications to export real-time telemetry.

