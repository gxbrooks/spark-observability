# K8s Monitoring Exporters

These manifests deploy the two standard Prometheus exporters needed for
complete Kubernetes observability. Both are configured in `prometheus.yml`
but must be deployed separately into the cluster.

## Deploy

```bash
# From Lab2 (the K8s control-plane node):
kubectl apply -f k8s/monitoring/kube-state-metrics.yaml
kubectl apply -f k8s/monitoring/node-exporter.yaml

# Verify
kubectl get pods -n kube-system | grep kube-state-metrics
kubectl get pods -n monitoring | grep node-exporter

# Check Prometheus targets picked up (wait ~30s)
# http://GaryPC.lan:9090/targets
```

## kube-state-metrics

**Namespace:** `kube-system` (required — Prometheus job filters on this)
**Metrics include:**
- `kube_pod_container_resource_requests` — CPU/memory requests per container
- `kube_pod_container_resource_limits` — CPU/memory limits per container
- `kube_pod_status_phase` — Pod phase (Running, Pending, Failed…)
- `kube_deployment_status_replicas` — Running vs desired replicas
- `kube_node_status_condition` — Node Ready/NotReady status
- `kube_namespace_status_phase` — Namespace status

**ES document example** (after deploying):
```json
{
  "@timestamp": "...",
  "service": { "name": "kube-state-metrics", "node": { "name": "10.244.x.x:8080" } },
  "cluster": "spark-cluster",
  "environment": "production",
  "container": "spark-kubernetes-executor",
  "namespace": "spark-jobs",
  "pod": "spark-pi-7f89b5d4-exec-1",
  "node": "lab2",
  "resource": "memory",
  "unit": "byte",
  "kube_pod_container_resource_requests": 2147483648.0
}
```

## node-exporter

**Namespace:** `monitoring` (DaemonSet — runs on every node)
**Metrics include:**
- `node_cpu_seconds_total` — CPU usage per mode (user/system/idle/iowait…)
- `node_memory_MemTotal_bytes` / `node_memory_MemAvailable_bytes`
- `node_disk_read_bytes_total` / `node_disk_written_bytes_total`
- `node_network_receive_bytes_total` / `node_network_transmit_bytes_total`
- `node_filesystem_size_bytes` / `node_filesystem_free_bytes`
- `node_load1`, `node_load5`, `node_load15`

**ES document example** (after deploying):
```json
{
  "@timestamp": "...",
  "service": { "name": "node-exporter", "node": { "name": "192.168.1.76:9100" } },
  "cluster": "spark-cluster",
  "environment": "production",
  "kubernetes_node": "lab1",
  "kubernetes_namespace": "monitoring",
  "cpu": "0",
  "mode": "user",
  "node_cpu_seconds_total": 12345.67
}
```

## What you already have (no deployment needed)

The `kubernetes-cadvisor` job scrapes **container-level** resource usage directly
from each kubelet — no extra deployment required:

| cAdvisor metric | Equivalent node-exporter metric |
|---|---|
| `container_cpu_usage_seconds_total` | `node_cpu_seconds_total` |
| `container_memory_rss` | `node_memory_MemTotal_bytes` |
| `container_fs_reads_bytes_total` | `node_disk_read_bytes_total` |
| `container_network_receive_bytes_total` | `node_network_receive_bytes_total` |

cAdvisor metrics have richer labels (namespace, pod, container, image) so
you can drill from node → pod → container. node-exporter gives you raw OS-level
metrics without the K8s context.
