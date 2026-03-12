# Running Pod Count Panel — Data Flow and Structure

This document describes how pod-count data moves from its source through Elasticsearch to the **Running Pod Count by Namespace** Grafana panel, and how format and structure change at each step.

---

## 1. Source: kube-state-metrics (Kubernetes)

**Location:** kube-state-metrics Deployment in `kube-system`, scraped by Prometheus (observability host).

**Metric:** `kube_pod_status_phase`  
- **Type:** Gauge  
- **Semantics:** One time series per (namespace, pod, phase). Value is `1` if the pod is in that phase at scrape time, otherwise `0`.  
- **Phases:** `Running`, `Pending`, `Failed`, `Succeeded`, `Unknown`.

**Format at source:** Prometheus exposition format. Example:

```
kube_pod_status_phase{namespace="spark",pod="spark-driver-abc",phase="Running"} 1
kube_pod_status_phase{namespace="spark",pod="spark-exec-1",phase="Running"} 1
...
```

**Structure:** Many samples per scrape; one sample per (namespace, pod, phase). All samples from a single scrape share the same timestamp.

---

## 2. Prometheus scrape and remote write

**Scrape:** Prometheus scrapes kube-state-metrics on an interval (e.g. 30s). One HTTP request → one response → one **scrape timestamp** for all samples in that response.

**Remote write:** Prometheus sends samples to the OpenTelemetry Collector (`prometheusremotewrite` receiver on port 9201). Each sample carries: metric name, labels (job, instance, namespace, pod, phase, …), timestamp, value.

**Format:** Prometheus remote-write protocol (e.g. Snappy-compressed protobuf). Structure is still “samples with labels and one value each”; no document model yet.

---

## 3. OpenTelemetry Collector → Elasticsearch

**Receiver:** `prometheusremotewrite` turns each Prometheus sample into an OTLP metric data point. The `job` label becomes the resource attribute `service.name`.

**Exporter:** Elasticsearch exporter with `mapping.mode: ecs` and `metrics_index: metrics-kubernetes-default`. It writes one **Elasticsearch document per metric sample**.

**Format and structure in Elasticsearch:**

- **Index / data stream:** `metrics-kubernetes-default` (backing indices like `.ds-metrics-kubernetes-default-YYYY.MM.DD-NNNNNN`).
- **One document = one (namespace, pod, phase)** at one `@timestamp`.
- **Key fields for pod count:**

| Field | Type | Description |
|-------|------|-------------|
| `@timestamp` | date | Scrape time (UTC). Same for all samples from one scrape. |
| `service.name` | keyword (nested under `service` in ECS) | Prometheus job; for KSM: `kube-state-metrics`. |
| `namespace` | keyword | The **observed** pod’s namespace (e.g. `spark`, `kube-system`). |
| `pod` | keyword | Pod name. |
| `phase` | keyword | `Running`, `Pending`, `Failed`, `Succeeded`, or `Unknown`. |
| `kube_pod_status_phase` | float | Metric value: `1.0` or `0.0`. |

- **Filtering in ES:** Use `service.name.keyword: kube-state-metrics` (or `service.name` where the mapping is keyword). Use `phase: Running` (not `phase.keyword` in the current mapping). Use `kube_pod_status_phase:*` or `exists: kube_pod_status_phase` to restrict to this metric.

So in Elasticsearch the “format” is **one JSON document per (scrape time, namespace, pod, phase)** with the above flat (or ECS-nested) fields. There are no pre-aggregated “pod count” documents; counts are derived by aggregation.

---

## 4. Grafana panel query (Elasticsearch)

The **Running Pod Count by Namespace** panel uses the Elasticsearch datasource and builds one time series per namespace.

**Query (Lucene):**

```
service.name.keyword:kube-state-metrics AND kube_pod_status_phase:* AND phase:Running
```

This returns only documents that represent “this pod is Running” at that timestamp.

**Bucket aggregations (order matters):**

1. **Terms** on `namespace.keyword`  
   - Splits data by namespace; each bucket is one namespace (one series).  
   - Settings: `min_doc_count: 1`, order by `_count`, size 20.

2. **Date histogram** on `@timestamp`  
   - Splits each namespace’s docs into time buckets (interval = `$__interval`, e.g. 30s).  
   - Settings: `min_doc_count: 1` so empty buckets are not returned (avoids false zeros).

**Metrics (pipeline):**

1. **Sum** of `kube_pod_status_phase` (id `1`, hidden)  
   - Per (namespace, time bucket): total of all `kube_pod_status_phase` values.  
   - One scrape in bucket → sum = number of running pods. Two scrapes in same bucket → sum = 2 × that count (causes spikes).

2. **Cardinality** of `@timestamp` (id `2`, hidden)  
   - Per (namespace, time bucket): number of distinct scrape timestamps.  
   - 1 or 2 (sometimes more) when multiple scrapes fall in the same interval.

3. **Bucket script** (id `3`, displayed)  
   - Script: `params._sum / params._card` when `_card > 0`, else `params._sum`.  
   - Variables: `_sum` ← metric `1`, `_card` ← metric `2`.  
   - **Effect:** Normalizes by number of scrapes in the bucket (sum ÷ cardinality), so double scrapes in one interval no longer double the value and the chart is smooth.

**Alias:** `{{term namespace.keyword}}` so the legend shows the namespace name.

**Format at panel level:** Grafana receives one time series per namespace bucket. Each point is (time bucket start, normalized pod count). The panel displays these as a time series (e.g. stacked area or line) with time on the X-axis and “Pods” on the Y-axis.

---

## 5. End-to-end structure summary

| Stage | Format / structure |
|-------|--------------------|
| **kube-state-metrics** | Prometheus gauge: one sample per (namespace, pod, phase); value 0 or 1. |
| **Prometheus** | Same samples with one scrape timestamp per HTTP response; remote-write payload. |
| **OTel → Elasticsearch** | One ES document per sample: `@timestamp`, `service.name`, `namespace`, `pod`, `phase`, `kube_pod_status_phase`. |
| **Grafana (ES query)** | Lucene filter + terms(namespace) + date_histogram(time) + sum, cardinality(@timestamp), bucket_script(sum/card). |
| **Grafana (panel)** | One time series per namespace; each point = (bucket start time, normalized pod count). |

---

## 6. Dashboard and provisioning

- **Dashboard:** K8s by Namespace (`uid: k8s-namespace`).  
- **Panel:** “Running Pod Count by Namespace” (type: timeseries).  
- **Provisioning:** `observability/grafana/provisioning/dashboards/k8s-namespace.json`; deployed to the observability host so Grafana loads it from the provisioning path.

For the full K8s metrics schema and other panels, see `observability/prometheus/docs/k8s-metrics-document-structure.md`.
