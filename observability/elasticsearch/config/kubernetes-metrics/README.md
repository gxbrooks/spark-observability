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
| `service.name` | Job (Prometheus) | Prometheus scrape job (`kubernetes-apiservers`, `kubernetes-nodes`, `kubernetes-cadvisor`, `prometheus`, etc.) |
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

To filter by job type, use KQL:
```
service.name : "kubernetes-apiservers"
service.name : "kubernetes-nodes"
service.name : "kubernetes-cadvisor"
service.name : "prometheus"
```

To see a specific metric, add it as a column in Discover or filter by its field name:
```
apiserver_request_total > 0
container_cpu_usage_seconds_total > 0
```
