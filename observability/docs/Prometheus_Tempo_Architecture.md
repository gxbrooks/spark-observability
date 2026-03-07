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

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│  Lab1 (16 cores)          Lab2 (16 cores)                   │
│  ┌─────────────┐         ┌─────────────┐                   │
│  │ kube-state- │         │ kube-state- │                   │
│  │   metrics   │         │   metrics   │                   │
│  └──────┬──────┘         └──────┬──────┘                   │
│         │                       │                           │
│  ┌──────▼───────────────────────▼──────┐                   │
│  │  Prometheus Node Exporter (per node) │                   │
│  └──────┬───────────────────────────────┘                   │
└─────────┼───────────────────────────────────────────────────┘
          │
          │ Scrape (15-30s interval)
          ▼
┌─────────────────────────────────────────────────────────────┐
│              GaryPC (Docker Node)                            │
│                                                              │
│  ┌──────────────────────────────────────────────────┐      │
│  │           Prometheus                             │      │
│  │  - Scrapes K8s API and node exporters           │      │
│  │  - Local TSDB (15 day retention)                │      │
│  │  - Remote write → Elasticsearch                 │      │
│  └──────┬───────────────────────┬──────────────────┘      │
│         │                       │                          │
│         │ Remote Write          │                          │
│         ▼                       │                          │
│  ┌──────────────┐               │                          │
│  │ Elasticsearch│               │                          │
│  │ (ILM Downsamp)│               │                          │
│  └──────────────┘               │                          │
│                                 │                          │
│  ┌──────────────────────────────▼──┐                      │
│  │      Grafana Tempo              │                      │
│  │  - Receives OTel spans          │                      │
│  │  - Object storage backend       │                      │
│  └──────┬───────────────────────┘                        │
│         │                                                 │
│         ▼                                                 │
│  ┌─────────────────────────────────┐                    │
│  │      Grafana                    │                    │
│  │  - Prometheus datasource        │                    │
│  │  - Tempo datasource             │                    │
│  │  - Elasticsearch datasource     │                    │
│  └─────────────────────────────────┘                    │
│                                                          │
│  ┌─────────────────────────────────┐                    │
│  │   OTel Collector                │                    │
│  │  - OTLP receiver (spans)        │                    │
│  │  → Tempo exporter               │                    │
│  └─────────────────────────────────┘                    │
└──────────────────────────────────────────────────────────┘
```

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
Prometheus → Remote Write → Elasticsearch
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

## References

- [Prometheus Remote Write](https://prometheus.io/docs/prometheus/latest/storage/#remote-storage-integrations)
- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [Kubernetes Golden Signals](https://sre.google/workbook/monitoring-distributed-systems/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)


