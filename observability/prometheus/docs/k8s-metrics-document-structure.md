# Kubernetes Metrics — Elasticsearch Document Structure Reference

**Index pattern:** `metrics-kubernetes-*`  
**Kibana Data View:** `Kubernetes Metrics`  
**Prometheus config:** `observability/prometheus/prometheus.yml`

---

## Service Areas Overview

Each Prometheus scrape job maps to a **service area** — a distinct source of metrics with its own
exporter, target discovery method, and set of Prometheus metric families. All metrics land in the
same Elasticsearch index (`metrics-kubernetes-*`), differentiated by `service.name`.

| `service.name` (job) | Exporter | Deployment Required? | Architectural Layer | What It Measures |
|---|---|---|---|---|
| `node-exporter` | node-exporter DaemonSet | **YES** — `prometheus/deploy.yml` | OS / Hardware | Per-node CPU, RAM, disk I/O, network, filesystem. Raw kernel counters — the ground truth for physical resource consumption. |
| `kube-state-metrics` | kube-state-metrics Deployment | **YES** — `prometheus/deploy.yml` | K8s Control Plane State | Desired vs actual state of K8s objects: pod phases, resource requests/limits, deployment replica counts, node conditions. Tells you *what K8s thinks* is happening. |
| `kubernetes-cadvisor` | cAdvisor (built into kubelet) | No — always running | Container Runtime | Per-container CPU seconds, working-set memory, filesystem bytes, network bytes. Tells you *what containers are actually consuming*. |
| `kubernetes-nodes` | Kubelet (built into each node) | No — always running | Node Agent | Kubelet health, running pod/container counts, PersistentVolume disk usage, volume inode stats. |
| `kubernetes-apiservers` | K8s API Server (built in) | No — always running | K8s Control Plane | API request counts, latency histograms, etcd operation latency, in-flight request gauges. Reveals control-plane health and contention. |
| `kubernetes-pods` | Any annotated pod | No — annotation-based | Application | Ad-hoc metrics from any pod that opts in via `prometheus.io/scrape: "true"` annotation. Used for application-specific instrumentation. |
| `prometheus` | Prometheus itself | No — self-scrape | Monitoring Infrastructure | Prometheus's own scrape duration, remote write queue depth, TSDB size. Useful for monitoring-pipeline health. |

---

## Multi-Node Kubernetes Architecture & Metric Mapping

### Cluster topology (two-node example)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        KUBERNETES CLUSTER (spark-cluster)                    │
│                                                                              │
│  ┌──────────────────────────────────┐  ┌──────────────────────────────────┐  │
│  │   Control-plane node (Lab2)      │  │   Worker node (Lab1)             │  │
│  │                                  │  │                                  │  │
│  │  ┌────────────────────────────┐  │  │  ┌────────────────────────────┐  │  │
│  │  │   K8s Control Plane        │  │  │  │   Kubelet + cAdvisor       │  │  │
│  │  │  ┌──────────┐ ┌────────┐   │  │  │  │  (node agent)              │  │  │
│  │  │  │kube-api  │ │  etcd  │   │  │  │  └────────────────────────────┘  │  │
│  │  │  │ server   │ │        │   │  │  │                                  │  │
│  │  │  └──────────┘ └────────┘   │  │  │  ┌────────────────────────────┐  │  │
│  │  │  ┌──────────┐ ┌────────┐   │  │  │  │   Container Runtime (CRI)  │  │  │
│  │  │  │scheduler │ │c-mgr   │   │  │  │  │   (containerd / docker)    │  │  │
│  │  │  └──────────┘ └────────┘   │  │  │  └────────────────────────────┘  │  │
│  │  └────────────────────────────┘  │  │                                  │  │
│  │                                  │  │  ┌────────────────────────────┐  │  │
│  │  ┌────────────────────────────┐  │  │  │   Workloads (Spark pods)   │  │  │
│  │  │   System pods (kube-sys)   │  │  │  │  ┌──────┐  ┌──────────┐    │  │  │
│  │  │  ┌────────────┐            │  │  │  │  │driver│  │executor  │    │  │  │
│  │  │  │kube-state  │            │  │  │  │  └──────┘  └──────────┘    │  │  │
│  │  │  │-metrics    │            │  │  │  └────────────────────────────┘  │  │
│  │  │  └────────────┘            │  │  │                                  │  │
│  │  └────────────────────────────┘  │  │  ┌────────────────────────────┐  │  │
│  │                                  │  │  │   node-exporter (DaemonSet)│  │  │
│  │  ┌────────────────────────────┐  │  │  └────────────────────────────┘  │  │
│  │  │   node-exporter (DaemonSet)│  │  └──────────────────────────────────┘  │
│  │  └────────────────────────────┘  │                                        │
│  └──────────────────────────────────┘                                        │
└──────────────────────────────────────────────────────────────────────────────┘

       ↑ scraped by Prometheus (running on GaryPC.lan in Docker)
       ↓ remote-written via OTel Collector → Elasticsearch
```

### Which metrics cover which architectural component

| Architectural Component | Description | Prometheus Service Area(s) | Key Metrics |
|---|---|---|---|
| **Hardware / OS** | Physical CPU, RAM, disks, NICs on each bare-metal or VM node | `node-exporter` | `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes`, `node_disk_read_bytes_total`, `node_network_receive_bytes_total`, `node_filesystem_avail_bytes` |
| **K8s API Server** | REST gateway for all cluster operations; backed by etcd | `kubernetes-apiservers` | `apiserver_request_total`, `apiserver_request_duration_seconds_*`, `etcd_request_duration_seconds_*`, `apiserver_current_inflight_requests` |
| **etcd** | Distributed key-value store holding all cluster state | `kubernetes-apiservers` | `etcd_object_counts`, `etcd_request_duration_seconds_*` (exposed via apiserver) |
| **Scheduler / Controller Manager** | Assigns pods to nodes; reconciles desired vs actual state | `kubernetes-apiservers` | `workqueue_depth`, `workqueue_adds_total`, `workqueue_work_duration_seconds_*` |
| **Kubelet (node agent)** | Runs on every node; manages pod lifecycle, volume mounts | `kubernetes-nodes` | `kubelet_running_pods`, `kubelet_running_containers`, `kubelet_volume_stats_used_bytes`, `kubelet_volume_stats_capacity_bytes` |
| **cAdvisor (container advisor)** | Embedded in kubelet; reports per-container resource usage | `kubernetes-cadvisor` | `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes`, `container_memory_rss`, `container_network_receive_bytes_total` |
| **K8s Object State** | Declared intent: resource requests, limits, replica counts, pod phases | `kube-state-metrics` | `kube_pod_status_phase`, `kube_pod_container_resource_requests`, `kube_pod_container_resource_limits`, `kube_deployment_spec_replicas`, `kube_node_status_condition` |
| **Spark Driver** | Master coordinator of a Spark job | `kubernetes-cadvisor`, `kube-state-metrics` | Filter by `pod` label containing "driver"; `container_memory_working_set_bytes`, `kube_pod_status_phase` |
| **Spark Executors** | Distributed workers; subject to OOM, scheduling failures | `kubernetes-cadvisor`, `kube-state-metrics`, `node-exporter` | `container_memory_working_set_bytes`, `kube_pod_container_resource_requests`, `kube_pod_container_status_waiting_reason` |
| **PersistentVolumes (shuffle)** | Disk volumes used for Spark shuffle spill | `kubernetes-nodes` | `kubelet_volume_stats_used_bytes`, `kubelet_volume_stats_capacity_bytes`, `kubelet_volume_stats_available_bytes` |
| **Monitoring infrastructure** | Prometheus itself (scrape pipeline health) | `prometheus` | `prometheus_remote_storage_queue_highest_sent_timestamp_seconds`, `prometheus_tsdb_head_samples_appended_total` |

### Standard references

- [Kubernetes Monitoring Architecture (kubernetes.io)](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
- [Prometheus Kubernetes Monitoring Guide (prometheus.io)](https://prometheus.io/docs/guides/kubernetes-monitoring/)
- [node-exporter GitHub — full metric catalog](https://github.com/prometheus/node_exporter#collectors)
- [kube-state-metrics exposed metrics (GitHub)](https://github.com/kubernetes/kube-state-metrics/blob/main/docs/metrics/workload/pod-metrics.md)
- [cAdvisor metrics reference (Google)](https://github.com/google/cadvisor/blob/master/docs/storage/prometheus.md)
- [USE Method for Kubernetes (Brendan Gregg)](https://www.brendangregg.com/usemethod.html) — maps utilization/saturation/errors to metric groups
- [Kubernetes SLIs / SLOs (kubernetes.io)](https://github.com/kubernetes/community/blob/master/sig-scalability/slos/slos.md)

---

## How Documents Are Created

The OTel Elasticsearch exporter writes one document **per Prometheus time-series sample**.
Each document represents a single metric at a single point in time:

- The **metric value** is stored as a field whose key is the exact Prometheus metric name.
- Prometheus **labels** from that time series become top-level string fields.
- External labels from `prometheus.yml` (`cluster`, `environment`) appear on every document.
- Relabeling rules in the scrape job add routing fields (`kubernetes_node`, `kubernetes_service`, etc.).

### Histogram metrics — naming convention

Prometheus histogram metric families explode into three per-bucket document types:

| Prometheus family | ES field key suffix | Meaning |
|---|---|---|
| `apiserver_request_duration_seconds` | `_bucket` | one document per histogram bucket; carries `le` label |
| `apiserver_request_duration_seconds` | `_count` | total number of observations |
| `apiserver_request_duration_seconds` | `_sum` | sum of all observed values |

Search tip — to find histogram data for a metric family, use the `_count` variant:
```
apiserver_request_duration_seconds_count : *
```

Counters and gauges (`apiserver_request_total`, `node_cpu_seconds_total`, `kube_pod_status_phase`)
appear with the exact metric name as the field key — no suffix.

---

## Universal Common Fields

Present on **every** document regardless of metric group or scrape job.

| Field | Type | Example Value | Description |
|---|---|---|---|
| `@timestamp` | date | `2026-03-05T14:30:00.000Z` | Scrape time (UTC ISO-8601) |
| `cluster` | keyword | `spark-cluster` | Cluster name; set in `prometheus.yml` `external_labels` |
| `environment` | keyword | `production` | Environment name; set in `prometheus.yml` `external_labels` |
| `service.name` | keyword | `kubernetes-cadvisor` | Prometheus scrape **job name** — use this to filter by service area |
| `service.node.name` | keyword | `192.168.1.48:6443` | Prometheus scrape **target instance** (host:port) |

The five fields above are the only fields guaranteed on every document.
All other fields depend on which scrape job produced the document and which labels the specific metric carries.

---

## Per-Job Routing Fields

Added by `relabel_configs` in `prometheus.yml`. Consistent within a job regardless of the individual metric.

| `service.name` | Routing fields always present |
|---|---|
| `kubernetes-apiservers` | `kubernetes_namespace="default"`, `kubernetes_service="kubernetes"`, `kubernetes_pod_name=<node FQDN>` |
| `kubernetes-nodes` | `kubernetes_node=<node name>` + any node labels via `labelmap` |
| `kubernetes-cadvisor` | `kubernetes_node=<node name>` + any node labels via `labelmap` |
| `kube-state-metrics` | `kubernetes_namespace="kube-system"`, `kubernetes_service="kube-state-metrics"`, `kubernetes_pod_name=<KSM pod name>` |
| `node-exporter` | `kubernetes_node=<node name>`, `kubernetes_namespace="monitoring"`, `kubernetes_pod_name=<DaemonSet pod name>`, `node=<node name>` |

---

## Metric Group Detail

---

### Group 1 — Node Health (`service.name = "node-exporter"`)

**Exporter:** `node-exporter` DaemonSet in `monitoring` namespace  
**Deployment required:** YES — `ansible/playbooks/observability/prometheus/deploy.yml`  
**Architectural layer:** OS / Hardware

#### Routing fields (always present for this job)

| Field | Value |
|---|---|
| `service.name` | `node-exporter` |
| `service.node.name` | `<node_ip>:9100` (e.g. `192.168.1.76:9100`) |
| `kubernetes_node` | Node hostname (e.g. `lab2`) |
| `kubernetes_namespace` | `monitoring` |
| `kubernetes_pod_name` | DaemonSet pod name (e.g. `node-exporter-r7x9k`) |
| `node` | Same as `kubernetes_node` — convenience duplicate |

#### Metric-specific label fields

| Metric | Extra fields | Notes |
|---|---|---|
| `node_cpu_seconds_total` | `cpu`, `mode` | One doc per CPU×mode combination. `mode` values: `user`, `system`, `idle`, `iowait`, `irq`, `softirq`, `steal`, `nice` |
| `node_memory_MemAvailable_bytes` | *(none)* | Single gauge per node |
| `node_memory_MemTotal_bytes` | *(none)* | Single gauge per node |
| `node_memory_MemFree_bytes` | *(none)* | |
| `node_memory_Cached_bytes` | *(none)* | |
| `node_memory_Buffers_bytes` | *(none)* | |
| `node_disk_read_bytes_total` | `device` | e.g. `sda`, `nvme0n1` |
| `node_disk_written_bytes_total` | `device` | |
| `node_disk_io_time_seconds_total` | `device` | |
| `node_network_receive_bytes_total` | `device` | Interface name, e.g. `eth0` |
| `node_network_transmit_bytes_total` | `device` | |
| `node_network_receive_packets_total` | `device` | |
| `node_network_transmit_packets_total` | `device` | |
| `node_filesystem_avail_bytes` | `device`, `fstype`, `mountpoint` | e.g. `sda1`, `ext4`, `/` |
| `node_filesystem_size_bytes` | `device`, `fstype`, `mountpoint` | |
| `node_filesystem_free_bytes` | `device`, `fstype`, `mountpoint` | |
| `node_load1` | *(none)* | 1-minute load average |
| `node_load5` | *(none)* | |
| `node_load15` | *(none)* | |

#### JSON examples

**`node_cpu_seconds_total` (CPU usage by mode — counter)**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "node-exporter",
    "node": { "name": "192.168.1.76:9100" }
  },
  "kubernetes_node": "lab2",
  "kubernetes_namespace": "monitoring",
  "kubernetes_pod_name": "node-exporter-r7x9k",
  "node": "lab2",
  "cpu": "0",
  "mode": "user",
  "node_cpu_seconds_total": 48213.67
}
```

**`node_memory_MemAvailable_bytes` (available memory — gauge)**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "node-exporter",
    "node": { "name": "192.168.1.76:9100" }
  },
  "kubernetes_node": "lab2",
  "kubernetes_namespace": "monitoring",
  "kubernetes_pod_name": "node-exporter-r7x9k",
  "node": "lab2",
  "node_memory_MemAvailable_bytes": 12884901888
}
```

**`node_filesystem_avail_bytes` (disk available — gauge)**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "node-exporter",
    "node": { "name": "192.168.1.76:9100" }
  },
  "kubernetes_node": "lab2",
  "kubernetes_namespace": "monitoring",
  "kubernetes_pod_name": "node-exporter-r7x9k",
  "node": "lab2",
  "device": "/dev/sda1",
  "fstype": "ext4",
  "mountpoint": "/",
  "node_filesystem_avail_bytes": 107374182400
}
```

---

### Group 2 — Cluster State (`service.name = "kube-state-metrics"`)

**Exporter:** `kube-state-metrics` Deployment in `kube-system` namespace  
**Deployment required:** YES — `ansible/playbooks/observability/prometheus/deploy.yml`  
**Architectural layer:** K8s Control Plane — Object State

#### Routing fields (always present for this job)

| Field | Value |
|---|---|
| `service.name` | `kube-state-metrics` |
| `service.node.name` | `<pod_ip>:8080` (e.g. `10.244.0.5:8080`) |
| `kubernetes_namespace` | `kube-system` — this is the **KSM service** namespace, NOT the observed resource namespace |
| `kubernetes_service` | `kube-state-metrics` |
| `kubernetes_pod_name` | KSM pod name (e.g. `kube-state-metrics-7d9b5c4f6-xr2nt`) |

> ⚠️ **Important:** `kubernetes_namespace` is always `kube-system` on kube-state-metrics documents
> because that is where the KSM service lives. The **observed K8s resource's** namespace is in the
> `namespace` field (lower-case, no `kubernetes_` prefix) added by KSM as a metric label.

#### Metric-specific label fields

| Metric | Extra fields | Notes |
|---|---|---|
| `kube_pod_status_phase` | `namespace`, `pod`, `phase` | `phase`: `Running`, `Pending`, `Failed`, `Succeeded`, `Unknown`. Value is `1` (true) or `0` (false) per phase variant |
| `kube_node_status_condition` | `node`, `condition`, `status` | `condition`: `Ready`, `MemoryPressure`, `DiskPressure`, `PIDPressure`, `NetworkUnavailable` |
| `kube_namespace_status_phase` | `namespace`, `phase` | |

#### JSON examples

**`kube_pod_status_phase` (pod phase indicator — gauge)**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kube-state-metrics",
    "node": { "name": "10.244.0.5:8080" }
  },
  "kubernetes_namespace": "kube-system",
  "kubernetes_service": "kube-state-metrics",
  "kubernetes_pod_name": "kube-state-metrics-7d9b5c4f6-xr2nt",
  "namespace": "spark-jobs",
  "pod": "spark-pi-7f89b5d4-exec-1",
  "phase": "Running",
  "kube_pod_status_phase": 1
}
```

**`kube_node_status_condition` (node readiness — gauge)**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kube-state-metrics",
    "node": { "name": "10.244.0.5:8080" }
  },
  "kubernetes_namespace": "kube-system",
  "kubernetes_service": "kube-state-metrics",
  "kubernetes_pod_name": "kube-state-metrics-7d9b5c4f6-xr2nt",
  "node": "lab2",
  "condition": "Ready",
  "status": "true",
  "kube_node_status_condition": 1
}
```

---

### Group 3 — Pod Resources

This group spans **two scrape jobs**: resource requests/limits come from kube-state-metrics;
actual in-use memory/CPU comes from cAdvisor.

---

#### Sub-group 3a — Resource Requests & Limits (`service.name = "kube-state-metrics"`)

**Exporter:** `kube-state-metrics` — same routing fields as Group 2.  
**Architectural layer:** K8s Control Plane — Declared Resource Intent

#### Metric-specific label fields

| Metric | Extra fields | Notes |
|---|---|---|
| `kube_pod_container_resource_requests` | `namespace`, `pod`, `container`, `resource`, `unit` | `resource`: `cpu` or `memory`. `unit`: `core` or `byte` |
| `kube_pod_container_resource_limits` | `namespace`, `pod`, `container`, `resource`, `unit` | Only emitted when the pod spec explicitly sets `resources.limits` |

#### JSON examples

**`kube_pod_container_resource_requests` — memory request**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kube-state-metrics",
    "node": { "name": "10.244.0.5:8080" }
  },
  "kubernetes_namespace": "kube-system",
  "kubernetes_service": "kube-state-metrics",
  "kubernetes_pod_name": "kube-state-metrics-7d9b5c4f6-xr2nt",
  "namespace": "spark-jobs",
  "pod": "spark-pi-7f89b5d4-exec-1",
  "container": "spark-kubernetes-executor",
  "resource": "memory",
  "unit": "byte",
  "kube_pod_container_resource_requests": 2147483648
}
```

**`kube_pod_container_resource_limits` — CPU limit**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kube-state-metrics",
    "node": { "name": "10.244.0.5:8080" }
  },
  "kubernetes_namespace": "kube-system",
  "kubernetes_service": "kube-state-metrics",
  "kubernetes_pod_name": "kube-state-metrics-7d9b5c4f6-xr2nt",
  "namespace": "spark-jobs",
  "pod": "spark-pi-7f89b5d4-exec-1",
  "container": "spark-kubernetes-executor",
  "resource": "cpu",
  "unit": "core",
  "kube_pod_container_resource_limits": 2.0
}
```

---

#### Sub-group 3b — Actual Resource Usage (`service.name = "kubernetes-cadvisor"`)

**Exporter:** cAdvisor — built into kubelet, no deployment needed.  
**Scrape job:** `kubernetes-cadvisor` via API server proxy.  
**Architectural layer:** Container Runtime

#### Routing fields

| Field | Value |
|---|---|
| `service.name` | `kubernetes-cadvisor` |
| `service.node.name` | `lab2.lan:6443` (API proxy address — same for all nodes) |
| `kubernetes_node` | Actual node hostname (e.g. `lab2`) — set by relabeling |

#### Metric-specific label fields

| Metric | Extra fields | Notes |
|---|---|---|
| `container_memory_working_set_bytes` | `id`, `image`, `name`, `namespace`, `pod`, `container` | Present per container; pod-level aggregates have empty `container` |
| `container_cpu_usage_seconds_total` | `id`, `image`, `name`, `namespace`, `pod`, `container` | Counter; rate() gives CPU fraction |
| `container_memory_rss` | `id`, `image`, `name`, `namespace`, `pod`, `container` | Resident Set Size |
| `container_network_receive_bytes_total` | `id`, `image`, `interface`, `name`, `namespace`, `pod` | Network interface name |
| `container_network_transmit_bytes_total` | `id`, `image`, `interface`, `name`, `namespace`, `pod` | |
| `container_fs_reads_bytes_total` | `device`, `id`, `image`, `name`, `namespace`, `pod`, `container` | |
| `container_fs_writes_bytes_total` | `device`, `id`, `image`, `name`, `namespace`, `pod`, `container` | |

#### JSON examples

**`container_memory_working_set_bytes` — actual RAM usage**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kubernetes-cadvisor",
    "node": { "name": "lab2.lan:6443" }
  },
  "kubernetes_node": "lab2",
  "id": "/kubepods/burstable/pod7f89b5d4/abc123",
  "image": "docker.io/apache/spark:3.5.0",
  "name": "k8s_spark-kubernetes-executor_spark-pi-7f89b5d4-exec-1_spark-jobs_...",
  "namespace": "spark-jobs",
  "pod": "spark-pi-7f89b5d4-exec-1",
  "container": "spark-kubernetes-executor",
  "container_memory_working_set_bytes": 1879048192
}
```

**`container_cpu_usage_seconds_total` — CPU consumed (counter)**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kubernetes-cadvisor",
    "node": { "name": "lab2.lan:6443" }
  },
  "kubernetes_node": "lab2",
  "id": "/kubepods/burstable/pod7f89b5d4/abc123",
  "image": "docker.io/apache/spark:3.5.0",
  "name": "k8s_spark-kubernetes-executor_spark-pi-7f89b5d4-exec-1_spark-jobs_...",
  "namespace": "spark-jobs",
  "pod": "spark-pi-7f89b5d4-exec-1",
  "container": "spark-kubernetes-executor",
  "container_cpu_usage_seconds_total": 8243.912
}
```

---

### Group 4 — Spark-Specific (`service.name = "kube-state-metrics"`)

**Exporter:** `kube-state-metrics` — same routing fields as Group 2.  
**Architectural layer:** K8s Workload — Deployment State

#### Metric-specific label fields

| Metric | Extra fields | Notes |
|---|---|---|
| `kube_deployment_spec_replicas` | `namespace`, `deployment` | Desired replica count from the Deployment spec |
| `kube_deployment_status_replicas` | `namespace`, `deployment` | Total replicas (including unavailable) |
| `kube_deployment_status_replicas_available` | `namespace`, `deployment` | Ready and passing readiness checks |
| `kube_deployment_status_replicas_unavailable` | `namespace`, `deployment` | Not yet ready |
| `kube_statefulset_replicas` | `namespace`, `statefulset` | For StatefulSet workloads |
| `kube_statefulset_status_replicas_ready` | `namespace`, `statefulset` | |
| `kube_replicaset_spec_replicas` | `namespace`, `replicaset` | |

#### JSON examples

**`kube_deployment_spec_replicas` — desired executor count**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kube-state-metrics",
    "node": { "name": "10.244.0.5:8080" }
  },
  "kubernetes_namespace": "kube-system",
  "kubernetes_service": "kube-state-metrics",
  "kubernetes_pod_name": "kube-state-metrics-7d9b5c4f6-xr2nt",
  "namespace": "spark-jobs",
  "deployment": "spark-pi-driver",
  "kube_deployment_spec_replicas": 4
}
```

**`kube_deployment_status_replicas_available` — running executors**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kube-state-metrics",
    "node": { "name": "10.244.0.5:8080" }
  },
  "kubernetes_namespace": "kube-system",
  "kubernetes_service": "kube-state-metrics",
  "kubernetes_pod_name": "kube-state-metrics-7d9b5c4f6-xr2nt",
  "namespace": "spark-jobs",
  "deployment": "spark-pi-driver",
  "kube_deployment_status_replicas_available": 3
}
```

---

### Group 5 — Scheduling (`service.name = "kube-state-metrics"`)

**Exporter:** `kube-state-metrics` — same routing fields as Group 2.  
**Architectural layer:** K8s Scheduling — Pod Lifecycle Events

#### Metric-specific label fields

| Metric | Extra fields | Notes |
|---|---|---|
| `kube_pod_container_status_waiting_reason` | `namespace`, `pod`, `container`, `reason` | `reason` values: `ContainerCreating`, `CrashLoopBackOff`, `ErrImagePull`, `ImagePullBackOff`, `CreateContainerConfigError`, `PodInitializing` |
| `kube_pod_container_status_running` | `namespace`, `pod`, `container` | 1 = running, 0 = not |
| `kube_pod_container_status_terminated_reason` | `namespace`, `pod`, `container`, `reason` | `reason` values: `OOMKilled`, `Error`, `Completed` |
| `kube_pod_init_container_status_waiting_reason` | `namespace`, `pod`, `container`, `reason` | For init containers |
| `kube_pod_status_ready` | `namespace`, `pod`, `condition` | `condition` = `true` or `false` |
| `kube_pod_start_time` | `namespace`, `pod` | Unix epoch of pod start |

#### JSON examples

**`kube_pod_container_status_waiting_reason` — stuck pod detection**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kube-state-metrics",
    "node": { "name": "10.244.0.5:8080" }
  },
  "kubernetes_namespace": "kube-system",
  "kubernetes_service": "kube-state-metrics",
  "kubernetes_pod_name": "kube-state-metrics-7d9b5c4f6-xr2nt",
  "namespace": "spark-jobs",
  "pod": "spark-pi-7f89b5d4-exec-3",
  "container": "spark-kubernetes-executor",
  "reason": "ImagePullBackOff",
  "kube_pod_container_status_waiting_reason": 1
}
```

---

### Group 6 — K8s API (`service.name = "kubernetes-apiservers"`)

**Exporter:** Built into the Kubernetes API server — no deployment needed.  
**Scrape job:** `kubernetes-apiservers` via endpoint discovery.  
**Architectural layer:** K8s Control Plane — API Gateway

#### Routing fields

| Field | Value |
|---|---|
| `service.name` | `kubernetes-apiservers` |
| `service.node.name` | `<apiserver_ip>:6443` (e.g. `192.168.1.48:6443`) |
| `kubernetes_namespace` | `default` (namespace of the `kubernetes` service) |
| `kubernetes_service` | `kubernetes` |
| `kubernetes_pod_name` | API server node FQDN (e.g. `lab2.lan`) |

#### Metric-specific label fields — counters and gauges

| Metric | Extra fields | Notes |
|---|---|---|
| `apiserver_request_total` | `verb`, `resource`, `subresource`, `scope`, `code`, `component` | `verb`: `GET`, `LIST`, `WATCH`, `POST`, `PUT`, `PATCH`, `DELETE`. `code` is HTTP status |
| `apiserver_current_inflight_requests` | `request_kind` | `request_kind`: `mutating`, `readOnly` |
| `process_cpu_seconds_total` | *(none)* | API server process CPU |
| `process_resident_memory_bytes` | *(none)* | API server process memory |
| `etcd_object_counts` | `resource` | Count of K8s objects in etcd by type |
| `workqueue_depth` | `name` | Queue backlog depth by controller name |
| `workqueue_adds_total` | `name` | |

#### Metric-specific label fields — histograms (search with `_bucket`, `_count`, or `_sum` suffix)

| Metric family | Suffix variants stored in ES | Extra fields |
|---|---|---|
| `apiserver_request_duration_seconds` | `_bucket`, `_count`, `_sum` | `verb`, `resource`, `subresource`, `scope`, `le` (buckets only) |
| `etcd_request_duration_seconds` | `_bucket`, `_count`, `_sum` | `operation`, `type` |
| `workqueue_work_duration_seconds` | `_bucket`, `_count`, `_sum` | `name` |
| `workqueue_queue_duration_seconds` | `_bucket`, `_count`, `_sum` | `name` |

#### JSON examples

**`apiserver_request_total` — API request counter**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kubernetes-apiservers",
    "node": { "name": "192.168.1.48:6443" }
  },
  "kubernetes_namespace": "default",
  "kubernetes_service": "kubernetes",
  "kubernetes_pod_name": "lab2.lan",
  "verb": "LIST",
  "resource": "pods",
  "subresource": "",
  "scope": "cluster",
  "code": "200",
  "component": "apiserver",
  "apiserver_request_total": 14823
}
```

**`apiserver_request_duration_seconds_count` — histogram (total count, simplest for dashboards)**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kubernetes-apiservers",
    "node": { "name": "192.168.1.48:6443" }
  },
  "kubernetes_namespace": "default",
  "kubernetes_service": "kubernetes",
  "kubernetes_pod_name": "lab2.lan",
  "verb": "GET",
  "resource": "nodes",
  "subresource": "",
  "scope": "resource",
  "component": "apiserver",
  "apiserver_request_duration_seconds_count": 10221
}
```

**`apiserver_request_duration_seconds_bucket` — one document per latency bucket**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kubernetes-apiservers",
    "node": { "name": "192.168.1.48:6443" }
  },
  "kubernetes_namespace": "default",
  "kubernetes_service": "kubernetes",
  "kubernetes_pod_name": "lab2.lan",
  "verb": "GET",
  "resource": "nodes",
  "subresource": "",
  "scope": "resource",
  "component": "apiserver",
  "le": "0.1",
  "apiserver_request_duration_seconds_bucket": 9814
}
```

---

### Group 7 — Storage (`service.name = "kubernetes-nodes"`)

**Exporter:** Built into kubelet — no deployment needed.  
**Scrape job:** `kubernetes-nodes` via API server proxy (`/api/v1/nodes/<node>/proxy/metrics`).  
**Architectural layer:** Node Agent / Persistent Storage

#### Routing fields

| Field | Value |
|---|---|
| `service.name` | `kubernetes-nodes` |
| `service.node.name` | `lab2.lan:6443` (API proxy address — same for all nodes) |
| `kubernetes_node` | Actual node hostname — set by relabeling |

#### Metric-specific label fields — storage

| Metric | Extra fields | Notes |
|---|---|---|
| `kubelet_volume_stats_used_bytes` | `namespace`, `persistentvolumeclaim` | Bytes consumed on PV by this PVC |
| `kubelet_volume_stats_capacity_bytes` | `namespace`, `persistentvolumeclaim` | Total PV capacity allocated |
| `kubelet_volume_stats_available_bytes` | `namespace`, `persistentvolumeclaim` | Free space on PV |
| `kubelet_volume_stats_inodes_used` | `namespace`, `persistentvolumeclaim` | Inodes used |
| `kubelet_volume_stats_inodes` | `namespace`, `persistentvolumeclaim` | Total inodes |

#### Metric-specific label fields — kubelet runtime (also from this job)

| Metric | Extra fields | Notes |
|---|---|---|
| `kubelet_running_pods` | *(none)* | Current pod count on this node |
| `kubelet_running_containers` | `container_state` | `container_state`: `running`, `exited`, `created`, `unknown` |
| `kubelet_node_config_error` | *(none)* | 1 if node config error present |

#### JSON examples

**`kubelet_volume_stats_used_bytes` — Spark shuffle disk usage**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kubernetes-nodes",
    "node": { "name": "lab2.lan:6443" }
  },
  "kubernetes_node": "lab2",
  "namespace": "spark-jobs",
  "persistentvolumeclaim": "spark-shuffle-pvc-exec-1",
  "kubelet_volume_stats_used_bytes": 4831838208
}
```

**`kubelet_running_pods` — pod count on node**
```json
{
  "@timestamp": "2026-03-05T14:30:00.000Z",
  "cluster": "spark-cluster",
  "environment": "production",
  "service": {
    "name": "kubernetes-nodes",
    "node": { "name": "lab2.lan:6443" }
  },
  "kubernetes_node": "lab2",
  "kubelet_running_pods": 12
}
```

---

## Why You May Not See Certain Metrics

| Issue | Cause | Fix |
|---|---|---|
| `kube_pod_container_resource_requests`, `kube_pod_status_phase`, etc. all missing | `kube-state-metrics` not deployed | `ansible-playbook -i ansible/inventory.yml ansible/playbooks/observability/prometheus/deploy.yml` |
| `kube-state-metrics` target shows DOWN in Prometheus with `context deadline exceeded` on a `10.244.x.x` address | Prometheus (running outside the cluster on GaryPC) cannot reach pod overlay IPs. Config must use the K8s API server proxy path. | `prometheus.yml` `kube-state-metrics` job must use `static_configs` with `lab2.lan:6443` and `metrics_path: /api/v1/namespaces/kube-system/services/kube-state-metrics:http-metrics/proxy/metrics` — already corrected in the current config |
| `node_cpu_seconds_total`, `node_memory_*` all missing | `node-exporter` DaemonSet not deployed | Same playbook as above |
| `apiserver_request_total` not found in Kibana search | Field exists; search requires exact field name. Use KQL: `apiserver_request_total : *` | Add it as a Discover column or filter by field |
| `apiserver_request_duration_seconds` not found | Histogram family — search for the suffix variants: `apiserver_request_duration_seconds_count : *` | See histogram naming convention section above |
| `kube_pod_container_resource_limits` absent even after KSM deployed | KSM only emits this when pods have explicit `resources.limits` in their spec; Spark pods without limits produce no documents | Set limits via Spark config: `spark.kubernetes.executor.limit.cores`, `spark.executor.memoryOverheadFactor` |
| Any metric from `kubernetes-nodes` or `kubernetes-cadvisor` missing | K8s API server TLS certs not copied to observability host, or Prometheus cannot reach `lab2.lan:6443` | Rerun `observability/deploy.yml`; verify `ops/observability/k8s-certs/` has `ca.crt`, `client.crt`, `client.key` |
| `kube_pod_status_phase` missing in recent data (last N hours) while other kube-state-metrics (e.g. `kube_pod_status_reason`, `kube_pod_container_resource_*`) are present | OTel Collector Elasticsearch exporter or Prometheus remote write may not be persisting this metric to the current backing index. Prometheus has the series (check `count(kube_pod_status_phase)`). | Restart Prometheus and OTel Collector; ensure `kubernetes-metrics.template.json` includes explicit `kube_pod_status_phase` (float) and `phase` (keyword) mappings; run diagnose playbook with `service.name.keyword` for ES counts. |

---

## Quick Kibana KQL Filters by Service Area

```kql
# --- NODE HEALTH (node-exporter) ---
service.name : "node-exporter"
service.name : "node-exporter" AND node_cpu_seconds_total : *
service.name : "node-exporter" AND node_memory_MemAvailable_bytes : *
service.name : "node-exporter" AND node_filesystem_avail_bytes : *
service.name : "node-exporter" AND kubernetes_node : "lab2"

# --- CLUSTER STATE (kube-state-metrics) ---
service.name : "kube-state-metrics"
service.name : "kube-state-metrics" AND kube_pod_status_phase : *
service.name : "kube-state-metrics" AND kube_node_status_condition : *

# --- POD RESOURCES — declared (kube-state-metrics) ---
service.name : "kube-state-metrics" AND kube_pod_container_resource_requests : *
service.name : "kube-state-metrics" AND kube_pod_container_resource_limits : *
# Filter by Spark namespace
service.name : "kube-state-metrics" AND namespace : "spark-jobs" AND kube_pod_container_resource_requests : *

# --- POD RESOURCES — actual usage (cAdvisor) ---
service.name : "kubernetes-cadvisor"
service.name : "kubernetes-cadvisor" AND container_memory_working_set_bytes : *
service.name : "kubernetes-cadvisor" AND namespace : "spark-jobs" AND container_memory_working_set_bytes : *

# --- SPARK-SPECIFIC (kube-state-metrics) ---
service.name : "kube-state-metrics" AND kube_deployment_spec_replicas : *
service.name : "kube-state-metrics" AND kube_deployment_status_replicas_available : *

# --- SCHEDULING / STUCK PODS ---
service.name : "kube-state-metrics" AND kube_pod_container_status_waiting_reason : *
# Stuck Spark executors specifically
service.name : "kube-state-metrics" AND namespace : "spark-jobs" AND kube_pod_container_status_waiting_reason : *

# --- K8s API SERVER ---
service.name : "kubernetes-apiservers"
service.name : "kubernetes-apiservers" AND apiserver_request_total : *
service.name : "kubernetes-apiservers" AND apiserver_request_duration_seconds_count : *
service.name : "kubernetes-apiservers" AND apiserver_current_inflight_requests : *

# --- STORAGE ---
service.name : "kubernetes-nodes"
service.name : "kubernetes-nodes" AND kubelet_volume_stats_used_bytes : *
service.name : "kubernetes-nodes" AND kubelet_running_pods : *
```
