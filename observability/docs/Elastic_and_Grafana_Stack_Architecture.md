# Elastic and Grafana Stack Architecture

## Overview

This document describes the **Elastic/Grafana observability path**: how
telemetry is collected, stored in **Elasticsearch**, and visualized in
**Grafana** and **Kibana**. Elasticsearch is the central long-term repository
for metrics, traces, logs, and application events. Grafana composes queries
across Elasticsearch data views (and optionally Prometheus or Tempo for
real-time or specialized views).

The parallel **Dynatrace** path is documented in
[Dynatrace Architecture](../dynatrace/docs/Dynatrace_Architecture.md). Both
backends can receive Spark OTLP metrics and traces simultaneously via the
OTel Collector dual-feed.

**Lab topology and resource budgets:** see
[architecture-and-resources.md](../../docs/architecture-and-resources.md).

## Goals

1. **Unified storage** — Metrics, traces, logs, and Spark application events
   in Elasticsearch with ILM downsampling and retention.
2. **Grafana dashboards** — Spark System Metrics, host drilldowns, Kubernetes
   golden signals, and trace/log viewers from Elasticsearch (and Tempo where
   configured).
3. **Spark application metrics via OTLP** — Active executions, shuffle,
   failures, and spills as time series without Elasticsearch Trial Watchers.
4. **Kubernetes metrics** — Prometheus scrapes cluster nodes; remote write
   lands in Elasticsearch for primary dashboards and retention.
5. **Trace visualization** — OTLP traces in Elasticsearch and optionally Grafana
   Tempo for Grafana-native trace UI.

## Component architecture

| Component | Location | Inputs | Outputs / consumers |
|-----------|----------|--------|---------------------|
| **OTelSparkListener** | Spark driver/workers (Lab1, Lab2) | SparkListener callbacks | OTLP traces + metrics to Collector; HTTP bulk app-events to ES |
| **OTel Collector** | Lab3 (observability) | OTLP (:4317/:4318), Prometheus remote write (:9201) | ES traces, ES metrics (spark, kubernetes, default), Tempo traces, Dynatrace OTLP (dual-feed) |
| **Elasticsearch** | Lab3 | Collector exporters, Elastic Agent, Logstash, listener bulk | Kibana, Grafana datasources, Elasticsearch Watchers |
| **Elasticsearch Watcher** | Lab3 (ES) | Polls `app-events-*` for open START docs | Writes aggregated counts to `application-events-metrics` (legacy active-execution path) |
| **Elastic Agent** | Lab1–Lab3 | Host metrics, GPU (where configured) | ES system and GPU metric data streams |
| **Prometheus** | Lab3 | Scrapes K8s API server, kubelet proxy, kube-state-metrics, node-exporter | Remote write → OTel Collector → ES `metrics-kubernetes-default`; local TSDB is a short buffer |
| **Grafana Tempo** | Lab3 | OTLP traces from Collector | Grafana trace datasource (complements ES-backed traces) |
| **Grafana** | Lab3 | ES data views, Prometheus, Tempo | Dashboards: Spark System Metrics, Hosts, K8s, logs |
| **Kibana** | Lab3 | ES indices / data views | Ad-hoc exploration, Watcher management |

## End-to-end data flow

### Spark and application telemetry

```
Spark driver/worker (OTelSparkListener)
  ├─ OTLP traces ──► OTel Collector ──► Elasticsearch (traces)
  │                                    └─► Tempo (optional)
  │                                    └─► Dynatrace OTLP (dual-feed)
  ├─ OTLP metrics ──► OTel Collector ──► Elasticsearch (spark metrics)
  │                                    └─► Dynatrace OTLP (dual-feed)
  └─ HTTP bulk ──► Elasticsearch (app-events)
                        │
                        ▼ (Watcher every 5s — legacy)
                 application-events-metrics
                        │
                        ▼
                 Grafana "Active Spark Executions" (Watcher panel)
```

The listener maintains in-memory maps of open operations and emits START/END
documents for applications, jobs, stages, tasks, and SQL executions. Stage END
documents carry shuffle, spill, duration, and result fields in
`spark.metrics.*`. OTLP metrics mirror the same lifecycle with UpDownCounters
and stage completion counters.

### Host, GPU, and infrastructure metrics

```
Lab hosts (Lab1–Lab3)
  └─ Elastic Agent ──► Elasticsearch (system-metrics, gpu-metrics)
                              │
                              ▼
                       Grafana / Kibana host panels
```

### Kubernetes metrics

```
K8s cluster (Lab1 workers, Lab2 workers, Lab3 control plane)
  └─ Prometheus scrape (API server, node proxy, cadvisor, kube-state-metrics, node-exporter)
         │
         │ Remote Write v2
         ▼
  OTel Collector (prometheusremotewrite receiver)
         │
         ▼
  Elasticsearch (metrics-kubernetes-default)
         │
         ▼
  ILM downsampling ──► Grafana K8s dashboards
```

Prometheus uses the **API server on Lab3** for service discovery and kubelet
proxy paths (`/api/v1/nodes/<name>/proxy/metrics`). Long-term retention and
dashboards treat **Elasticsearch as the source of truth**; local Prometheus
TSDB is for short-term debugging only.

### Traces

```
Spark / other OTLP clients
  └─ OTel Collector
         ├─► Elasticsearch (traces data stream)
         └─► Tempo (Grafana trace UI)
```

## Dual path: Watcher vs OTel for active executions

During transition, Grafana **Spark System Metrics** may show two active-execution panels:

| Aspect | Watcher (legacy) | OTel metrics (target) |
|--------|------------------|------------------------|
| Source | Open START documents in `app-events-*` | OTLP UpDownCounter aggregated in ES spark-metrics index |
| Sampling | 5 s poll | Push interval (~10 s export) |
| ES license | Requires Watcher (Trial+ for production Watcher) | Works on ES Basic — no Watcher |
| Semantics | Count of `event.state=open` docs by `operation.type` | Same open/close logic as event emitter |

Stage shuffle, failure, and spill panels use **OTLP counters** in the
spark-metrics index (rate queries in Grafana). The Watcher path does not
aggregate these; they previously existed only on stage END documents.

## Spark metrics in Elasticsearch

OTLP metrics from the listener land in a dedicated spark-metrics data stream.
Typical instruments:

| Metric | Kind | Grafana query pattern |
|--------|------|----------------------|
| Active executions | UpDownCounter → gauge in queries | `max(opened) − max(closed)` or last value by `operation_type` |
| Shuffle read/write bytes | Counter | `rate()` over window |
| Stage failures | Counter | `rate()` or increase |
| Spill memory/disk bytes | Counter | `rate()` over window |

Labels stay low-cardinality: `operation_type`, `spark.app.id`, cluster, and
environment — never per-stage or per-task ids on metrics.

## Kubernetes metrics in Elasticsearch

All Prometheus scrape jobs write to a **single** data stream
(`metrics-kubernetes-default`). The `job` label (stored under `labels.job`)
distinguishes apiservers, nodes, cadvisor, kube-state-metrics, node-exporter,
and pod targets. One index template and one ILM policy simplify operations and
cross-job dashboards.

**Intended scrape coverage:**

| Job | Signal |
|-----|--------|
| kubernetes-apiservers | API server request rates, latency |
| kubernetes-nodes | Kubelet node health |
| kubernetes-cadvisor | Per-container CPU, memory, fs, network |
| kube-state-metrics | Cluster object state (pods, deployments, nodes) |
| node-exporter | Host-level CPU, memory, disk, network |
| kubernetes-pods | Opt-in pod metrics (`prometheus.io/scrape`) |

Jobs without deployed targets (e.g. kube-state-metrics, node-exporter DaemonSet)
produce no samples until the cluster-side component exists.

## Retention and downsampling

Elasticsearch ILM applies tiered downsampling similar across metric families:

| Phase | Typical age | Downsample interval | Retention |
|-------|-------------|---------------------|-----------|
| Hot | 0–4 d | 5 m | ~7 d |
| Warm | 4–8 d | 15 m | ~30 d |
| Cold | 8 d+ | 60 m | up to ~365 d |
| Delete | policy-dependent | — | purge |

Spark and Kubernetes metric volumes in the lab are modest (cluster-level
aggregates and standard K8s scrape cardinality).

## Grafana visualization layers

Grafana dashboards map to Elasticsearch data views by domain:

| Dashboard domain | Primary ES source | Notes |
|------------------|-------------------|-------|
| Spark System Metrics (aggregated) | system-metrics, gpu-metrics, spark-metrics, application-events-metrics, logs | Host golden signals + Spark execution/stage OTLP + legacy Watcher panel |
| Host drilldowns | system-metrics, gpu-metrics | Per-host CPU, memory, NIC, disk, page faults, GPU |
| Spark logs | Spark log indices | Level and host breakdown |
| Kubernetes | metrics-kubernetes-default | Golden signals: latency, traffic, errors, saturation |

Tempo datasource enables trace exploration linked from metrics where
configured. Kibana provides complementary ad-hoc search on the same indices.

## Design principles (Elastic path)

1. **Elasticsearch as system of record** — Dashboards and retention policies
   assume ES data streams, not Prometheus TSDB alone.
2. **Single instrumentation, multiple stores** — Spark listener emits once;
   Collector fans out to ES (and Dynatrace).
3. **Same semantics across event and metric paths** — START/END documents and
   OTLP UpDownCounters share listener close logic.
4. **Low cardinality on metrics** — Per-task and per-stage detail in traces
   and app-events documents, not metric labels.

## Related documentation

- [Dynatrace Architecture](../dynatrace/docs/Dynatrace_Architecture.md) — Grail, OneAgent, DQL, and dual-feed from the same Spark instruments
- [Elasticsearch indices](../elasticsearch/docs/Elasticsearch_indices.md) — Index names, data views, and field conventions
- [architecture-and-resources.md](../../docs/architecture-and-resources.md) — Host roles, RAM/CPU budgets, Lab3 stack layout
- [Grafana README](../grafana/README.md) — Dashboard inventory and datasource provisioning
