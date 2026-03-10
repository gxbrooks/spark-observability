# Prometheus and Grafana Tempo Architecture

## Overview

This document outlines the architecture for integrating **Prometheus** (Kubernetes metrics collection) and **Grafana Tempo** (distributed tracing backend) into the existing Spark Observability stack.

**Telemetry repository:** Elasticsearch is the central repository for telemetry in this architecture. Metrics (including Prometheus remote write), traces (via OTel and Elasticsearch exporter), and logs flow into Elasticsearch for long-term storage, downsampling (ILM), and querying. Grafana and Kibana consume from Elasticsearch (and from Prometheus/Tempo for real-time or specialized views).

## Goals

1. **Grafana Tempo**: Visualize Spark spans collected by the OpenTelemetry collector
2. **Prometheus**: Collect and visualize Kubernetes metrics from Lab1 and Lab2 (2 x 16-core hosts)
3. **Downsampling**: Apply consistent downsampling strategy to Prometheus metrics (similar to Elasticsearch ILM)
4. **Golden Signals**: Monitor K8s golden signals (latency, traffic, errors, saturation)

## Resource Constraints

### Current Observability Stack

| Service | Memory Limit | CPU |
|---------|-------------|-----|
| Elasticsearch | 4GB | ~1 core |
| Kibana | 2GB | ~0.5 core |
| Grafana | 2GB | ~0.25 core |
| Logstash | 2GB | ~0.25 core |
| OTel Collector | 256MB | ~0.1 core |
| **Total** | **~10.5GB** | **~2.1 cores** |

### Available for New Services

- **Memory**: ~5.5GB remaining (out of 16GB total)
- **CPU**: ~0.9 cores remaining (out of 3 cores / 6 logical threads)

### Resource Allocation Plan

| Service | Memory Limit | CPU Limit | Rationale |
|---------|-------------|-----------|-----------|
| **Prometheus** | 3GB | 0.5 cores | Medium K8s cluster (2 x 16-core hosts), ~15s scrape interval |
| **Grafana Tempo** | 2GB | 0.4 cores | Single-node deployment, OTel span storage |

**Total New**: 5GB / 0.9 cores (fits within constraints)

**⚠️ Resource Assessment**: The allocation is **tight but feasible** for:
- 2 x 16-core Kubernetes hosts (32 cores total)
- Moderate scrape frequency (15-30s)
- Limited retention (15 days raw, 1 year downsampled)

**If insufficient**:
- Reduce Prometheus retention period
- Increase scrape interval to 30s
- Consider external long-term storage (e.g., Thanos Compact)

## Architecture Overview

Containers and processes use **single-line** boxes; **double-line** boxes (`=` top/bottom, `||` sides) denote different nodes (hosts).

```
=================================================================
||  Kubernetes Cluster (nodes)                                  ||
||  ========================  ========================           ||
||  || Lab1 (worker)       ||  || Lab2 (master)            ||   ||
||  ||  +----------------+ ||  ||  +------------------------+||   ||
||  ||  | kubelet        | ||  ||  | API Server (apiserver) |||   ||
||  ||  | (metrics:10250)| ||  ||  | :6443                  |||   ||
||  ||  +----------------+ ||  ||  | - discovery, proxy     |||   ||
||  ||  +----------------+ ||  ||  |   to node metrics      |||   ||
||  ||  | node-exporter  | ||  ||  +-----------+------------+||   ||
||  ||  | (if deployed)  | ||  ||  | kubelet   | kube-state |||   ||
||  ||  +----------------+ ||  ||  | :10250    | (if deploy)|||   ||
||  ||                     ||  ||  +-----------+------------+||   ||
||  ========================  ========================           ||
||           ^                          ^                         ||
||           | scrape (HTTPS, client cert)                        ||
||           | discovery + node proxy via API Server              ||
=================================================================
             |
             | Scrape (30s) + Remote Write
             v
=================================================================
||  GaryPC (Docker host / observability node)                    ||
||                                                               ||
||  +------------------+     Remote Write (v2)                   ||
||  | Prometheus       |     http://otel-collector:9201          ||
||  | :9090            |----------------------+                  ||
||  | - scrapes API     |                      v                  ||
||  |   Server :6443   |     +--------------------------------+  ||
||  | - node proxy via |     | OTel Collector                  |  ||
||  |   API Server     |     | Inputs:  OTLP :4317/:4318       |  ||
||  +------------------+     |          prometheusremotewrite  |  ||
||                            |                 :9201           |  ||
||  OTLP (traces)             | Outputs: Elasticsearch (traces,|  ||
||  :4317 / :4318  ---------->|          metrics)              |  ||
||  (Spark, etc.)             |          Tempo :4317 (traces)  |  ||
||                            +-----------+--------+------------+  ||
||                                       |        |                ||
||  +------------------+                 v        v               ||
||  | Tempo            |<-------- traces  |        | metrics      ||
||  | :3200/:4317      |                  |        v               ||
||  | (trace store)    |           +------+------+                 ||
||  +------------------+           | Elasticsearch |               ||
||                                 | (ILM, datastreams)            ||
||  +------------------+           +---------------+              ||
||  | Grafana          |----------- Prometheus, Tempo, ES         ||
||  | :3000            |           datasources                     ||
||  +------------------+                                           ||
=================================================================
```

**API Server**: The **Kubernetes API Server** (container/process on Lab2, port 6443) is the control-plane endpoint. Prometheus does **not** scrape it as “metrics from a box named API Server”; it uses the API Server for (1) **service discovery** (nodes, pods, endpoints) and (2) **proxy** to each node’s kubelet (`/api/v1/nodes/<name>/proxy/metrics`). So all scrape traffic from Prometheus to the cluster goes to **lab2.lan:6443** (API Server); the API Server then proxies to kubelets or to the API server’s own metrics endpoint (`default/kubernetes:https`).

## Component Details

### 1. Prometheus

**Purpose**: Collect Kubernetes and node-level metrics

**Configuration**:
- **Scrape Targets**:
  - Kubernetes API server (`/metrics`)
  - `kube-state-metrics` (deployed per node or as DaemonSet)
  - `node-exporter` (per-node metrics: CPU, memory, disk, network)
  - Kubernetes service discovery for pods/services
- **Scrape Interval**: 15-30 seconds (configurable based on resource pressure)
- **Retention**: 15 days local TSDB (balancing disk usage vs. query performance)
- **Remote Write**: Continuous export to Elasticsearch for long-term storage

**Storage Strategy**:
- **Short-term (0-15 days)**: Local Prometheus TSDB for fast queries
- **Long-term (15+ days)**: Elasticsearch via remote write + ILM downsampling

### 2. Grafana Tempo

**Purpose**: Store and query distributed traces (Spark OTel spans)

**Configuration**:
- **Receiver**: OTLP gRPC (already exposed by OTel Collector)
- **Storage Backend**: Local filesystem (single-node deployment)
- **Retention**: 30 days (configurable based on disk space)
- **Block Duration**: 1 hour (default)

**Integration**:
- OTel Collector already configured → add Tempo exporter
- Grafana already provisioned → add Tempo datasource

### 3. Prometheus → Elasticsearch Integration

**Approach**: Use **Prometheus Remote Write** to export metrics to Elasticsearch

**Why Elasticsearch**:
- Consistent with existing metrics infrastructure
- Leverage existing ILM downsampling policies
- Single query interface (Grafana) for all metrics
- Unified retention management

**Components**:
1. **Prometheus Remote Write**: Native feature, configured in `prometheus.yml`
2. **Remote-storage adapter**: The stack uses **prometheus-es-adapter** (Docker service `prometheus-es-adapter`), which receives Prometheus remote write on `/write` and indexes metrics into Elasticsearch. The adapter uses the `metrics-kubernetes-default` alias so indices match the `metrics-kubernetes-*` index template and ILM policy.
3. **Elasticsearch**: Long-term storage with ILM downsampling (no native Prometheus remote write protocol; the adapter bridges the two).

**Data Flow**:
```
Prometheus → Remote Write (v2) → OTel Collector (prometheusremotewrite) → Elasticsearch (metrics-kubernetes-default)
                                                                                    ↓
                                                                            ILM Downsampling
                                                                                    ↓
                                                                            Hot → Warm → Cold → Delete
                                                                           (5m → 15m → 60m → 730d)
```

### 4. Downsampling Strategy

**Elasticsearch ILM Policy** (similar to `system-metrics-downsampled`):

| Phase | Age | Downsample Interval | Retention | Priority |
|-------|-----|-------------------|-----------|----------|
| Hot | 0-4d | 5m | 7 days | 100 |
| Warm | 4-8d | 15m | 30 days | 50 |
| Cold | 8d+ | 60m | 365 days | 25 |
| Delete | 365d+ | - | - | - |

**Metrics Collected**:
- Kubernetes API server metrics
- `kube-state-metrics` (pods, nodes, deployments, services)
- Node exporter (CPU, memory, disk, network per node)
- Kubernetes control plane components (if exposed)

**Note**: Prometheus recording rules can be used for additional aggregation before remote write, reducing Elasticsearch ingestion load.

### 5. Kubernetes Dashboard Requirements

**Golden Signals** for Kubernetes:

#### Latency
- **Pod startup time**: Time from `PodScheduled` to `Running`
- **API server latency**: Request latency (p50, p95, p99)
- **Scheduler latency**: Time to assign pods to nodes

#### Traffic
- **Requests per second**: API server request rate
- **Network I/O**: Bytes in/out per pod/node
- **Pod creation rate**: New pods per second

#### Errors
- **Error rates**: API server 4xx/5xx responses
- **Failed pods**: Pods in `Failed` or `CrashLoopBackOff` state
- **Pod restarts**: Container restart counts

#### Saturation
- **CPU utilization**: Per node, per pod (requested vs. used)
- **Memory utilization**: Per node, per pod (requested vs. used)
- **Disk I/O**: Per node, per pod
- **Pod density**: Pods per node

**Recommended Dashboards**:
1. **Kubernetes Cluster Overview** (high-level golden signals)
2. **Kubernetes Node Metrics** (per-node resource utilization)
3. **Kubernetes Pod Metrics** (per-pod resource usage and health)
4. **Kubernetes Control Plane** (API server, scheduler, controller manager)

**Dashboard Sources**:
- **Grafana Kubernetes Dashboard** (dashboard ID: 7249) - Official Grafana K8s dashboard
- **Kubernetes Cluster Monitoring** (dashboard ID: 8588) - Comprehensive K8s metrics
- **Custom Dashboard**: Based on golden signals above

## Implementation Plan

### Phase 1: Prometheus Setup

1. **Create Prometheus configuration**:
   - `observability/prometheus/prometheus.yml` - Main config
   - `observability/prometheus/rules/` - Recording/alerting rules
   - `observability/prometheus/targets/` - Static scrape targets

2. **Update `docker-compose.yml`**:
   - Add `prometheus` service with resource limits (3GB, 0.5 cores)
   - Configure volumes for config and data

3. **Deploy kube-state-metrics** (if not already deployed):
   - Via Helm or Kubernetes manifests
   - One instance per cluster (not per node)

4. **Deploy node-exporter** (if not already deployed):
   - Via DaemonSet to collect per-node metrics
   - One instance per node (Lab1, Lab2)

### Phase 2: Elasticsearch Integration

1. **Create ILM policy**:
   - `observability/elasticsearch/config/kubernetes-metrics/kubernetes-metrics.ilm.json`
   - Mirror `system-metrics-downsampled` structure

2. **Configure remote write**:
   - Update `prometheus.yml` with Elasticsearch remote write endpoint
   - Test remote write connectivity

3. **Update `init-index.sh`**:
   - Add step to create `kubernetes-metrics` ILM policy
   - Create index template for Prometheus metrics

4. **Create data view**:
   - `observability/elasticsearch/config/kubernetes-metrics/kubernetes-metrics.dataview.json`
   - For Kibana exploration

### Phase 3: Grafana Tempo Setup

1. **Create Tempo configuration**:
   - `observability/tempo/tempo.yml` - Single-node config
   - Local filesystem storage backend

2. **Update `docker-compose.yml`**:
   - Add `tempo` service with resource limits (2GB, 0.4 cores)
   - Configure volumes for config and data

3. **Update OTel Collector**:
   - Add Tempo exporter to `otel-collector-config.yaml`
   - Configure OTLP → Tempo pipeline

4. **Update Grafana datasources**:
   - Add Tempo datasource to `grafana/provisioning/datasources/datasources.yaml`
   - Enable trace-to-metrics correlation

### Phase 4: Dashboard Deployment

1. **Import K8s dashboards**:
   - Deploy recommended Grafana dashboards (IDs: 7249, 8588)
   - Customize for golden signals

2. **Create custom dashboard**:
   - Build `kubernetes-golden-signals.json` dashboard
   - Focus on latency, traffic, errors, saturation

3. **Configure provisioning**:
   - Add dashboards to `grafana/provisioning/dashboards/`

## Configuration Files

### Prometheus Configuration Structure

```
observability/
├── prometheus/
│   ├── prometheus.yml          # Main configuration
│   ├── rules/
│   │   ├── kubernetes.yml      # Recording/alerting rules
│   │   └── node.yml            # Node exporter rules
│   └── targets/
│       └── kubernetes.yml      # Static scrape targets (if needed)
```

### Tempo Configuration Structure

```
observability/
├── tempo/
│   ├── tempo.yml               # Tempo configuration
│   └── data/                   # Local storage (volume)
```

### Elasticsearch Configuration

```
observability/elasticsearch/config/kubernetes-metrics/
├── kubernetes-metrics.ilm.json         # ILM downsampling policy
├── kubernetes-metrics.template.json    # Index template
└── kubernetes-metrics.dataview.json    # Kibana data view
```

## Resource Monitoring

### Prometheus Disk Usage

**Estimate** for 2 x 16-core hosts:
- **Per-sample size**: ~2 bytes (compressed)
- **Samples per scrape**: ~5000 (K8s API + node + kube-state-metrics)
- **Scrape interval**: 15s
- **Samples per day**: (5000 samples × 4 scrapes/min × 1440 min) = 28.8M samples
- **Disk per day**: 28.8M × 2 bytes ≈ 58MB/day
- **15-day retention**: 58MB × 15 ≈ 870MB

**With head compaction**: ~400MB for 15 days (reasonable)

### Tempo Disk Usage

**Estimate** for Spark spans:
- **Span size**: ~500 bytes (average)
- **Spans per Spark job**: ~1000 (approximate)
- **Jobs per day**: Variable (assume 100 jobs/day)
- **Spans per day**: 100 × 1000 = 100K spans
- **Disk per day**: 100K × 500 bytes ≈ 50MB/day
- **30-day retention**: 50MB × 30 ≈ 1.5GB

**Total new disk usage**: ~2GB (acceptable)

## Security Considerations

1. **Prometheus Scraping**:
   - Use Kubernetes service account with read-only permissions
   - Configure RBAC for Prometheus service account

2. **Remote Write**:
   - Use TLS for Prometheus → Elasticsearch communication
   - Authenticate with Elasticsearch user credentials

3. **Tempo Storage**:
   - Ensure filesystem permissions restrict access
   - Consider encryption at rest (if sensitive data in traces)

## Next Steps

1. ✅ Review and approve architecture
2. ⬜ Create Prometheus configuration files
3. ⬜ Create Tempo configuration files
4. ⬜ Update `docker-compose.yml` with new services
5. ⬜ Create Elasticsearch ILM policy for Kubernetes metrics
6. ⬜ Update OTel Collector configuration
7. ⬜ Deploy and test integration
8. ⬜ Import K8s dashboards into Grafana
9. ⬜ Document operational procedures

## Kubernetes metrics – what we collect and what’s needed for full telemetry

Prometheus is configured with six scrape jobs for Kubernetes. Together they form the intended “full suite” of K8s telemetry; several jobs only yield targets if the cluster has the right components deployed.

| Job | Purpose | Status / requirement |
|-----|---------|----------------------|
| **kubernetes-apiservers** | API server metrics (request rates, latency, etc.) | ✅ Working. Scrapes `default/kubernetes:https` via API server. |
| **kubernetes-nodes** | Kubelet /metrics per node (node health, volume, runtime) | Fixed: now uses **API server proxy** (`lab2.lan:6443` → `/api/v1/nodes/<name>/proxy/metrics`). Was down when we targeted kubelet port 10250 directly (wrong host/path). Needs API server RBAC: `nodes`, `nodes/proxy` with `get`. |
| **kubernetes-cadvisor** | Container metrics (CPU, memory, fs, network per container) | Same proxy as nodes; path `/metrics/cadvisor`. Requires same RBAC as nodes. |
| **kubernetes-pods** | App metrics from pods that opt in | Only pods with `prometheus.io/scrape: "true"` (and optional port/path) become targets. No targets until you add the annotation. |
| **kube-state-metrics** | Cluster object state (deployments, pods, nodes, etc.) | Requires **kube-state-metrics** deployed in the cluster (e.g. in `kube-system` with service `kube-state-metrics`). Job keeps only that endpoint. |
| **node-exporter** | Host-level metrics (CPU, memory, disk, network) | Requires **node-exporter** DaemonSet with pods labeled `app=node-exporter`. Job discovers those pods. |
| **prometheus** | Prometheus self-metrics | ✅ Working. |

**Are all metrics currently being collected?** No. Only jobs that have at least one **target** produce samples. Jobs with **“No Targets”** do not produce any metrics until you add targets:

- **kubernetes-pods**: No targets until some pod has `prometheus.io/scrape: "true"`. No metrics from this job until then.
- **kube-state-metrics**: No targets until the service `kube-state-metrics` (e.g. in `kube-system`) is deployed. No metrics from this job until then.
- **node-exporter**: No targets until a DaemonSet (or similar) runs pods with label `app=node-exporter`. No metrics from this job until then.

So the jobs that **are** currently collecting are: **kubernetes-apiservers**, **kubernetes-nodes**, **kubernetes-cadvisor**, and **prometheus**. The other three jobs are configured but have zero targets until you deploy the components or add the annotations above.

So we are **not** missing jobs in the config; we’re missing **cluster-side components and/or RBAC** for some of them. Summary:

- **kubernetes-nodes (and cadvisor) down:** Caused by scraping the kubelet port (10250) with the API server proxy path. Fixed by sending scrapes to the **API server** (`lab2.lan:6443`) with path `/api/v1/nodes/<name>/proxy/metrics` (and `/metrics/cadvisor`). After fix, the API server proxies to the kubelet; same client cert works. Ensure the Prometheus service account (or the cert user) has RBAC for `nodes` and `nodes/proxy` (e.g. `get`).
- **Full K8s telemetry** needs:
  1. **API server proxy for nodes/cadvisor** – config change above.
  2. **RBAC** – cluster role with `get` on `nodes` and `nodes/proxy` for the principal used by Prometheus (when using in-cluster SA) or equivalent for the client cert.
  3. **kube-state-metrics** – deploy in the cluster so the `kube-state-metrics` job has a target.
  4. **node-exporter** – deploy as a DaemonSet (and optional Service) so the `node-exporter` job has targets.
  5. **kubernetes-pods** – add `prometheus.io/scrape: "true"` (and optionally port/path) to any pod that should expose app metrics.

## Single datastream for all K8s metrics: is it correct? Best practice?

**Yes.** Having a single Elasticsearch datastream, **`metrics-kubernetes-default`**, for all Prometheus Kubernetes metrics is correct and is the intended design. Prometheus remote write sends all scrape results (all jobs) to one endpoint; the OTel Collector’s `prometheusremotewrite` receiver receives them and the Elasticsearch exporter writes to a single `metrics_index` (metrics-kubernetes-default). Splitting by job would require either multiple remote-write endpoints or post-processing (e.g. Logstash/ingest) to route by `job`; a single datastream with a **job** dimension (as a label/field) is the usual and recommended approach. You filter by `labels.job` (or the ECS equivalent) in Kibana or Grafana. Benefits: one index template, one ILM policy, simpler operations, and all K8s metrics in one place for cross-job dashboards.

## Elasticsearch field names for K8s metrics (by Prometheus job)

All jobs write into the same datastream **metrics-kubernetes-default**. Each document is a metric sample. The **job** is stored as the Prometheus label `job`, which in Elastic appears under the **labels** object (or as a top-level attribute depending on OTel→ECS mapping). Below are the Elastic JSON field names that appear for Kubernetes metrics (from the index template and ECS/OTel mapping). Grouped by the Prometheus **job** that produces them:

| Prometheus job | Elastic field names (common) | Notes |
|----------------|------------------------------|--------|
| **kubernetes-apiservers** | `@timestamp`, `prometheus.metric.name`, `prometheus.metric.type`, `value`, `labels` | `labels.job` = `kubernetes-apiservers`; often `kubernetes.namespace` = default, `kubernetes.service.name` = kubernetes. |
| **kubernetes-nodes** | `@timestamp`, `prometheus.metric.name`, `prometheus.metric.type`, `value`, `labels`, `kubernetes.node.name` | `labels.job` = kubernetes-nodes; node in `labels.kubernetes_node` or `kubernetes.node.name`. |
| **kubernetes-cadvisor** | `@timestamp`, `prometheus.metric.name`, `prometheus.metric.type`, `value`, `labels`, `kubernetes.node.name`, `kubernetes.pod.name`, `kubernetes.namespace` | `labels.job` = kubernetes-cadvisor; container/pod dimensions when present. |
| **kubernetes-pods** | `@timestamp`, `prometheus.metric.name`, `prometheus.metric.type`, `value`, `labels`, `kubernetes.namespace`, `kubernetes.pod.name` | `labels.job` = kubernetes-pods; from pods with prometheus.io/scrape. |
| **kube-state-metrics** | `@timestamp`, `prometheus.metric.name`, `prometheus.metric.type`, `value`, `labels`, `kubernetes.*` | `labels.job` = kube-state-metrics; deployment/service/node in labels or kubernetes.*. |
| **node-exporter** | `@timestamp`, `prometheus.metric.name`, `prometheus.metric.type`, `value`, `labels`, `kubernetes.node.name`, `kubernetes.pod.name` | `labels.job` = node-exporter; host metrics per node. |
| **prometheus** | `@timestamp`, `prometheus.metric.name`, `prometheus.metric.type`, `value`, `labels` | `labels.job` = prometheus, `labels.instance`. |

**Common fields in every document** (from template and ECS mapping):

- **`@timestamp`** (date): sample time
- **`prometheus.metric.name`** (keyword): Prometheus metric name (e.g. `http_requests_total`, `container_cpu_usage_seconds_total`)
- **`prometheus.metric.type`** (keyword): counter, gauge, etc.
- **`value`** (float): numeric value
- **`labels`** (object): all Prometheus labels, including **`labels.job`** (job name), **`labels.instance`**, **`labels.kubernetes_node`**, **`labels.kubernetes_namespace`**, **`labels.kubernetes_pod_name`**, and any other labels from the scrape

**Kubernetes-specific ECS fields** (when present): **`kubernetes.namespace`**, **`kubernetes.pod.name`**, **`kubernetes.pod.uid`**, **`kubernetes.node.name`**, **`kubernetes.service.name`**, **`kubernetes.deployment.name`**. These are populated when the OTel exporter maps resource attributes from the Prometheus labels into ECS Kubernetes fields.

To see only one job in Kibana: filter on **`labels.job`** (or **`prometheus.labels.job`** if nested) equals e.g. `kubernetes-apiservers` or `kubernetes-nodes`.

## Kubernetes metrics – validation and troubleshooting

- **Remote write path:** Prometheus is configured to send metrics to the OTel Collector (`prometheusremotewrite` receiver on port 9201), which exports to Elasticsearch index `metrics-kubernetes-default`. The legacy `prometheus-es-adapter` is not used because it creates an ES 5–style index template and fails on Elasticsearch 8.
- **415 Unsupported Media Type:** The OTel `prometheusremotewrite` receiver only supports Remote Write **v2**. If Prometheus sends v1 (default), the receiver returns 415. In `prometheus.yml`, `send_native_histograms: true` and `protobuf_message: io.prometheus.write.v2.Request` are set to request v2; if the running Prometheus still sends v1, no samples will reach Elasticsearch until Prometheus supports and uses v2 for this endpoint.
- **K8s scrape failures:** All Kubernetes scrape jobs (apiservers, nodes, pods, kube-state-metrics, node-exporter) require client TLS under `/etc/ssl/certs/kubernetes/` (`ca.crt`, `client.crt`, `client.key`). This is **not** the same as the Elastic CA: Prometheus has two cert mounts—`certs:/etc/ssl/certs/elastic` (Elastic CA) and `./k8s-certs:/etc/ssl/certs/kubernetes` (K8s API client certs). The observability deploy playbook populates `k8s-certs` from the Kubernetes master (e.g. Lab2) when `kubernetes_master` is in inventory; the path is relative to the compose project directory on the observability host.

**To validate K8s metrics in Elastic:** (1) Mount K8s client certs into the Prometheus container and confirm K8s targets are up in the Prometheus UI. (2) Ensure remote write uses v2 (check Prometheus logs for 415; if present, fix Prometheus config or receiver compatibility). (3) In Kibana, open the `metrics-kubernetes-default` data view (or index) and confirm recent `@timestamp` and metric names.

## Version recommendations

- **Prometheus:** Use **Prometheus 3.8.0 or later** when sending metrics to Elastic via the OpenTelemetry Collector’s Prometheus remote write receiver. OTel contrib v0.142.0+ expects **Remote Write 2.0**; Prometheus 3.8+ supports the v2 protocol. Pin the image in `docker-compose.yml` (e.g. `prom/prometheus:v3.8.0`) to avoid regressions.
- **Elasticsearch / Elastic Stack:** Use **Elasticsearch 8.x** (e.g. 8.15+ or 8.16+) for production. For Prometheus remote write via OTel, **Elasticsearch 9.x** (and Kibana 9.0+) offers the best integration (Prometheus integration GA), but 8.x works with the OTel Collector path. Stay on a supported 8.x release that matches your Elastic Agent and Beats versions.

## References

- [Prometheus Remote Write](https://prometheus.io/docs/prometheus/latest/storage/#remote-storage-integrations)
- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [Kubernetes Golden Signals](https://sre.google/workbook/monitoring-distributed-systems/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)


