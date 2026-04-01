# Kubernetes Metrics (Prometheus → OTel Collector → Elasticsearch)

## Data flow

Prometheus scrapes K8s targets → writes to OTel Collector via remote_write (port 9201) → OTel Collector exports to Elasticsearch using the `elasticsearchexporter`.

## Document structure

The OTel Elasticsearch exporter uses a **flat metric-per-document** format where the metric value is stored as a field whose key is the metric name:

```json
{
  "@timestamp": "2026-03-09T20:47:01Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kubernetes-apiservers",
    "node": { "name": "192.168.1.48:6443" }
  },
  "kubernetes_namespace": "default",
  "kubernetes_service": "kubernetes",
  "name": "AvailableConditionController",
  "workqueue_work_duration_seconds_bucket": 0.0
}
```

Each document contains **one metric** — the field key is the Prometheus metric name and the value is the measurement. Labels become top-level text fields.

## Common fields (present in most documents)

| Field | Label | Description |
|-------|-------|-------------|
| `@timestamp` | Timestamp | When the metric was scraped |
| `service.name` | Job (Prometheus) | Prometheus scrape job (`kubernetes-apiservers`, `kubernetes-nodes`, `kubernetes-cadvisor`, `kube-state-metrics`, `prometheus`, etc.) |
| `scrape_job` | Job (Prometheus) | Copy of `service.name` added by the OTel Collector for Grafana/Lucene parity; use for filters alongside dashboards |
| `service.node.name` | Instance | Prometheus target endpoint |
| `cluster` | Cluster | Cluster name (`spark-cluster`) |
| `environment` | Environment | Environment label (`production`) |
| `kubernetes_namespace` | Namespace (label) | K8s namespace (from metric labels) |
| `kubernetes_node` | Node (label) | K8s node name |
| `kubernetes_service` | Service (label) | K8s service name |
| `container` | Container | Container name (cadvisor metrics) |
| `pod` | Pod | Pod name (cadvisor/pod metrics) |
| `namespace` | Namespace | Namespace (from metric labels, alternate) |
| `node` | Node | Node name (alternate label) |

## Kibana objects

- **Data view**
  - Name (display): `Kubernetes Metrics`
  - ID: `kubernetes-metrics`
  - Index pattern: `metrics-kubernetes-*`
  - Time field: `@timestamp`

- **Saved search** (Discover → Open)
  - Title: `Kubernetes Metrics`
  - ID: `kubernetes-metrics-default`
  - Default columns: `@timestamp`, `service.name`, `service.node.name`, `cluster`, `kubernetes_namespace`, `kubernetes_node`, `container`

## Querying in Discover

Use the **Kubernetes Metrics** data view (index pattern `metrics-kubernetes-*`). Widen the time range if you see no documents.

### KQL (default in Discover)

**Always quote values that contain hyphens** (e.g. job names). Otherwise KQL can parse `-` as syntax, not as part of the string, and the query matches nothing.

Filter by Prometheus job / kube-state-metrics (same meaning as Grafana’s `scrape_job`):

```
scrape_job: "kube-state-metrics"
```

or (ECS `service` object — also use quotes):

```
service.name: "kube-state-metrics"
```

Other jobs:

```
service.name: "kubernetes-apiservers"
service.name: "kubernetes-nodes"
service.name: "kubernetes-cadvisor"
service.name: "prometheus"
```

To narrow to **kube-state-metrics pod / phase** style metrics, filter on a **concrete metric field** (there is no `kube_pod_*` field-name wildcard in KQL/Lucene):

```
scrape_job: "kube-state-metrics" and kube_pod_status_phase: *
```

Restart counters:

```
scrape_job: "kube-state-metrics" and kube_pod_container_status_restarts_total: *
```

To see a specific metric, add it as a column or use a numeric filter:

```
apiserver_request_total > 0
container_cpu_usage_seconds_total > 0
```

### Lucene (Discover: toggle language)

Use Lucene when you need `_index`, `_exists_`, or other classic query-string features. Examples:

```
_index:.ds-metrics-kubernetes-default* AND scrape_job:"kube-state-metrics"
```

```
scrape_job:"kube-state-metrics" AND _exists_:kube_pod_status_phase
```

### If you still see “no results”

1. **Data view** — Confirm you are on `metrics-kubernetes-*`, not logs-only views.
2. **Time range** — Metrics are continuous; a too-narrow window can look empty if ingestion paused.
3. **KQL vs Lucene** — `_index` and `_exists_` are not KQL; switch to Lucene for those.
4. **Hyphens** — In KQL, use `scrape_job: "kube-state-metrics"` (quoted), not `scrape_job:kube-state-metrics`.
