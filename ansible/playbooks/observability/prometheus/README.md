# Prometheus Sub-Playbooks

Manages the Prometheus metrics pipeline and Kubernetes monitoring exporters.

## Playbooks

| Playbook | Purpose | Hosts |
|---|---|---|
| `deploy.yml` | Sync Prometheus config + deploy K8s exporters (node-exporter, kube-state-metrics) | `observability`, `kubernetes_master` |
| `start.yml` | Ensure Prometheus and OTel Collector containers are running; verify K8s exporter pods | `observability`, `kubernetes_master` |
| `stop.yml` | Stop Prometheus and OTel Collector containers (targeted, does not touch the rest of the stack) | `observability` |
| `diagnose.yml` | Full pipeline health check: containers, Prometheus targets, key metrics in Prometheus and Elasticsearch | `observability`, `kubernetes_master` |
| `uninstall.yml` | Remove K8s exporters from cluster; stop Prometheus and OTel containers | `observability`, `kubernetes_master` |

## Usage

All playbooks can be run standalone from the project root:

```bash
# Deploy K8s exporters (node-exporter + kube-state-metrics) to the cluster
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/observability/prometheus/deploy.yml

# Start Prometheus and OTel Collector + verify K8s exporters
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/observability/prometheus/start.yml

# Diagnose the full Prometheus pipeline
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/observability/prometheus/diagnose.yml

# Stop Prometheus and OTel Collector only (leaves ES/Kibana/Grafana running)
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/observability/prometheus/stop.yml

# Uninstall K8s exporters from cluster
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/observability/prometheus/uninstall.yml

# Uninstall including monitoring namespace removal
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/observability/prometheus/uninstall.yml \
  -e remove_monitoring_namespace=true
```

## Integration with top-level playbooks

Each sub-playbook is automatically called via `import_playbook` at the end of the corresponding top-level observability playbook:

```
observability/deploy.yml    → imports prometheus/deploy.yml
observability/start.yml     → imports prometheus/start.yml
observability/stop.yml      → imports prometheus/stop.yml
observability/diagnose.yml  → imports prometheus/diagnose.yml
observability/uninstall.yml → imports prometheus/uninstall.yml
```

## Architecture

```
Prometheus (Docker)
  ├── Scrapes K8s API Server    → apiserver_request_duration_seconds, etc.
  ├── Scrapes Kubelet (nodes)   → kubelet_volume_stats_used_bytes, etc.
  ├── Scrapes cAdvisor          → container_memory_working_set_bytes, etc.
  ├── Scrapes kube-state-metrics → kube_pod_status_phase, kube_pod_container_resource_requests, etc.
  └── Scrapes node-exporter     → node_cpu_seconds_total, node_memory_MemAvailable_bytes, etc.
         ↓ remote_write
OTel Collector (Docker)
         ↓ elasticsearchexporter
Elasticsearch → index: metrics-kubernetes-*
         ↓
Kibana Discover / Grafana dashboards
```

## Key Metrics Matrix

| Metric Group | Metric | Source | Exporter |
|---|---|---|---|
| Node Health | `node_cpu_seconds_total` | node-exporter | DaemonSet in `monitoring` ns |
| Node Health | `node_memory_MemAvailable_bytes` | node-exporter | DaemonSet in `monitoring` ns |
| Node Health | `node_disk_read_bytes_total`, `node_disk_written_bytes_total` | node-exporter | DaemonSet in `monitoring` ns |
| Node Health | `node_network_receive_bytes_total`, `node_network_transmit_bytes_total` | node-exporter | DaemonSet in `monitoring` ns |
| Node Health | `node_filesystem_avail_bytes` | node-exporter | DaemonSet in `monitoring` ns |
| Cluster State | `kube_pod_status_phase` | kube-state-metrics | Deployment in `kube-system` |
| Cluster State | `kube_node_status_condition` | kube-state-metrics | Deployment in `kube-system` |
| Cluster State | `kube_namespace_status_phase` | kube-state-metrics | Deployment in `kube-system` |
| Pod Resources | `kube_pod_container_resource_requests` | kube-state-metrics | Deployment in `kube-system` |
| Pod Resources | `kube_pod_container_resource_limits` | kube-state-metrics | Deployment in `kube-system` |
| Pod Resources | `container_memory_working_set_bytes` | cAdvisor (kubelet) | Built-in (no deployment needed) |
| Pod Resources | `container_cpu_usage_seconds_total` | cAdvisor (kubelet) | Built-in (no deployment needed) |
| Spark-Specific | `kube_deployment_spec_replicas` | kube-state-metrics | Deployment in `kube-system` |
| Spark-Specific | `kube_deployment_status_replicas_available` | kube-state-metrics | Deployment in `kube-system` |
| Scheduling | `kube_pod_container_status_waiting_reason` | kube-state-metrics | Deployment in `kube-system` |
| Scheduling | `kube_pod_container_status_running` | kube-state-metrics | Deployment in `kube-system` |
| K8s API | `apiserver_request_duration_seconds` | API Server | Built-in (no deployment needed) |
| K8s API | `apiserver_request_total` | API Server | Built-in (no deployment needed) |
| Storage | `kubelet_volume_stats_used_bytes` | Kubelet | Built-in (no deployment needed) |
| Storage | `kubelet_volume_stats_capacity_bytes` | Kubelet | Built-in (no deployment needed) |

## K8s Manifests

Source manifests are in `k8s/monitoring/`:

- `k8s/monitoring/node-exporter.yaml` — DaemonSet + Service in `monitoring` namespace
- `k8s/monitoring/kube-state-metrics.yaml` — Deployment + Service + RBAC in `kube-system`
- `k8s/monitoring/README.md` — Detailed documentation

## Prometheus Configuration

Prometheus scrape jobs are in `observability/prometheus/prometheus.yml`:

| Job | Target | Discovery |
|---|---|---|
| `kubernetes-apiservers` | K8s API Server | endpoints role |
| `kubernetes-nodes` | Kubelet (via API proxy) | node role |
| `kubernetes-cadvisor` | cAdvisor (via API proxy) | node role |
| `kubernetes-pods` | Annotated pods | pod role (annotation-based) |
| `kube-state-metrics` | KSM service in kube-system | endpoints role |
| `node-exporter` | node-exporter pods in monitoring | pod role (label-based) |
| `prometheus` | Prometheus itself | static |

## Troubleshooting

**Prometheus targets are DOWN:**
```bash
# Check Prometheus UI
open http://GaryPC.lan:9090/targets

# Check cert paths are correct in container
docker exec prometheus ls /etc/ssl/certs/kubernetes/

# Check K8s API is reachable from Prometheus
docker exec prometheus curl -sk --cacert /etc/ssl/certs/kubernetes/ca.crt \
  --cert /etc/ssl/certs/kubernetes/client.crt \
  --key /etc/ssl/certs/kubernetes/client.key \
  https://lab2.lan:6443/api/v1/namespaces/kube-system/endpoints/kube-state-metrics
```

**node-exporter or kube-state-metrics not found in Prometheus targets:**
```bash
# Deploy them
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/observability/prometheus/deploy.yml

# Verify pods are running
kubectl get pods -n monitoring
kubectl get pods -n kube-system -l app=kube-state-metrics
```

**Metrics not in Elasticsearch:**
```bash
# Check OTel Collector logs
docker logs otel-collector --tail 50

# Check Prometheus remote write queue
curl http://GaryPC.lan:9090/api/v1/status/tsdb
```
