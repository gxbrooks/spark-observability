# Architecture and resource allocation

This document is the **project-wide** reference for lab host roles, service placement, and concrete CPU/RAM/disk allocations. Every software component that consumes measurable resources is listed with its configured value, not a range.

For file-system paths and NFS layout see [File_System_Architecture.md](File_System_Architecture.md). For the Prometheus/Tempo/OTel metrics pipeline see [Prometheus and Grafana Tempo Architecture](../observability/docs/Prometheus_Tempo_Architecture.md).

---

## 1. Host inventory


| Host         | Logical CPUs | RAM   | Disk   | Role                                                                                                                               |
| ------------ | ------------ | ----- | ------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Lab1.lan** | 32           | 96 GB | 937 GB | Kubernetes worker — Spark workers only                                                                                             |
| **Lab2.lan** | 32           | 96 GB | 935 GB | Kubernetes worker — Spark workers only                                                                                             |
| **Lab3.lan** | 32           | 64 GB | 915 GB | Observability (Docker Compose), K8s control plane, Spark Master, Spark History Server, HDFS, NFS server, JupyterHub, Elastic Agent |


DNS names (`*.lan`) are authoritative; IPs are in `ansible/inventory.yml` for reference only.

Lab1 and Lab2 are **symmetric**: identical hardware, identical Spark worker count and resource spec. Lab3 is the single ops/control node.

---

## 2. Lab3 — resource allocation

### 2.1 Docker Compose: Observability stack

Configured in `[observability/docker-compose.yml](../observability/docker-compose.yml)`.


| Service                | Memory limit | CPU limit | Notes                                                           |
| ---------------------- | ------------ | --------- | --------------------------------------------------------------- |
| Elasticsearch (`es01`) | 4 GiB        | —         | JVM heap auto-sizes to ~50 % of container limit                 |
| Kibana                 | 2 GiB        | —         | `NODE_OPTIONS --max-old-space-size=1536`                        |
| Grafana                | 2 GiB        | —         |                                                                 |
| Prometheus             | 3 GiB        | 0.5       | Local TSDB 15 d retention; primary store is ES via remote write |
| Tempo                  | 2 GiB        | 0.4       | Trace backend (local filesystem)                                |
| Logstash               | 2 GiB        | —         |                                                                 |
| OTel Collector         | 1 GiB        | —         | Reservation 384 MiB                                             |
| **Subtotal**           | **16 GiB**   | **1.3**   |                                                                 |


Init containers (`init-certs`, `set-kibana-password`, `init-index`) are short-lived and do not count toward steady-state budget.

### 2.2 Kubernetes control plane

Static pods managed by kubelet on Lab3.


| Component               | Est. memory | Est. CPU | Notes                               |
| ----------------------- | ----------- | -------- | ----------------------------------- |
| etcd                    | 1 GiB       | 0.5      | Single-node cluster                 |
| kube-apiserver          | 1.5 GiB     | 0.5      |                                     |
| kube-scheduler          | 0.5 GiB     | 0.25     |                                     |
| kube-controller-manager | 0.5 GiB     | 0.25     |                                     |
| CoreDNS (1 pod)         | 0.2 GiB     | 0.1      | Second replica may land on a worker |
| kube-flannel            | 0.1 GiB     | 0.1      | DaemonSet — one per node            |
| kube-proxy              | 0.1 GiB     | 0.1      | DaemonSet — one per node            |
| **Subtotal**            | **~4 GiB**  | **~2**   |                                     |


### 2.3 Kubernetes workloads on Lab3


| Component             | Replicas | Mem request | Mem limit   | CPU request | CPU limit | Config                                                                                                                          |
| --------------------- | -------- | ----------- | ----------- | ----------- | --------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Spark Master          | 1        | 2 GiB       | 4 GiB       | 1           | 2         | `[ansible/roles/spark/templates/spark-master.yaml.j2](../ansible/roles/spark/templates/spark-master.yaml.j2)`                   |
| Spark History Server  | 1        | 2 GiB       | 4 GiB       | 1           | 2         | `[ansible/roles/spark/templates/spark-history.yaml.j2](../ansible/roles/spark/templates/spark-history.yaml.j2)`                 |
| HDFS NameNode         | 1        | 1 GiB       | 2 GiB       | 0.25        | 1         | `[ansible/playbooks/k8s/hadoop/hadoop-namenode.yaml](../ansible/playbooks/k8s/hadoop/hadoop-namenode.yaml)`                     |
| HDFS DataNode         | 1        | 1 GiB       | 2 GiB       | 0.25        | 1         | `[ansible/playbooks/k8s/hadoop/hadoop-datanode.yaml](../ansible/playbooks/k8s/hadoop/hadoop-datanode.yaml)`                     |
| JupyterHub            | 1        | 2 GiB       | 4 GiB       | 1           | 2         | `[ansible/roles/spark/templates/jupyterhub-deployment.yaml.j2](../ansible/roles/spark/templates/jupyterhub-deployment.yaml.j2)` |
| node-exporter         | 1        | 50 MiB      | 100 MiB     | 50m         | 200m      | `[k8s/monitoring/node-exporter.yaml](../k8s/monitoring/node-exporter.yaml)`                                                     |
| **Subtotal (limits)** |          |             | **~16 GiB** |             | **~8**    |                                                                                                                                 |


### 2.4 Native services on Lab3


| Component                                 | Est. memory | Notes                                                                                 |
| ----------------------------------------- | ----------- | ------------------------------------------------------------------------------------- |
| NFS server (kernel)                       | 0.5 GiB     | Exports `/srv/nfs/spark/*`; see `[ansible/playbooks/nfs/](../ansible/playbooks/nfs/)` |
| Elastic Agent                             | 0.5 GiB     | Systemd service; config at `[elastic-agent/](../elastic-agent/)`                      |
| OS, Docker engine, kubelet, sshd, logging | 3 GiB       |                                                                                       |
| **Subtotal**                              | **4 GiB**   |                                                                                       |


### 2.5 Lab3 rollup


| Category                       | Memory (limits) |
| ------------------------------ | --------------- |
| Docker Compose (Observability) | 16 GiB          |
| K8s control plane              | 4 GiB           |
| K8s workloads (limits)         | 16 GiB          |
| Native services + OS           | 4 GiB           |
| **Total allocated**            | **40 GiB**      |
| **Hardware**                   | **64 GiB**      |
| **Headroom**                   | **24 GiB**      |


Headroom covers page cache, Elasticsearch segment merges, and burst allocation. CPU (32 logical) is well within budget.

---

## 3. Lab1 and Lab2 — resource allocation (symmetric)

Both hosts run identical Spark worker fleets and monitoring agents. No observability, no NFS, no HDFS, no control-plane pods.

### 3.1 Kubernetes workloads per host


| Component     | Replicas | Mem request | Mem limit | CPU request | CPU limit | Config                                                                                                        |
| ------------- | -------- | ----------- | --------- | ----------- | --------- | ------------------------------------------------------------------------------------------------------------- |
| Spark Worker  | 4        | 8 GiB       | 14 GiB    | 2           | 4         | `[ansible/roles/spark/templates/spark-worker.yaml.j2](../ansible/roles/spark/templates/spark-worker.yaml.j2)` |
| node-exporter | 1        | 50 MiB      | 100 MiB   | 50m         | 200m      | `[k8s/monitoring/node-exporter.yaml](../k8s/monitoring/node-exporter.yaml)`                                   |
| kube-flannel  | 1        | ~50 MiB     | ~50 MiB   | ~100m       | ~100m     | DaemonSet (system)                                                                                            |
| kube-proxy    | 1        | ~128 MiB    | ~256 MiB  | ~100m       | ~500m     | DaemonSet (system)                                                                                            |


**Per-host totals (4 workers):**


| Metric                 | Value  |
| ---------------------- | ------ |
| Worker memory requests | 32 GiB |
| Worker memory limits   | 56 GiB |
| Worker CPU requests    | 8      |
| Worker CPU limits      | 16     |


### 3.2 Native services per host


| Component                     | Est. memory | Notes           |
| ----------------------------- | ----------- | --------------- |
| Elastic Agent                 | 0.5 GiB     | Systemd service |
| OS, kubelet, containerd, sshd | 3 GiB       |                 |
| **Subtotal**                  | **3.5 GiB** |                 |


### 3.3 Per-host rollup


| Category                           | Memory (limits) |
| ---------------------------------- | --------------- |
| K8s workloads (Spark + monitoring) | 56.4 GiB        |
| Native services + OS               | 3.5 GiB         |
| **Total allocated**                | **~60 GiB**     |
| **Hardware**                       | **96 GiB**      |
| **Headroom**                       | **~36 GiB**     |


Headroom covers file-system page cache, Spark shuffle spill, and executor overhead beyond the JVM. CPU (32 logical) is adequate: limits sum to ~17 cores, well under 32.

### 3.4 Spark worker sizing rationale


| Setting               | Value | Why                                                                                           |
| --------------------- | ----- | --------------------------------------------------------------------------------------------- |
| `SPARK_WORKER_CORES`  | 4     | Matches the K8s CPU limit; prevents Spark from over-allocating based on host CPU count        |
| `SPARK_WORKER_MEMORY` | 12 g  | Leaves ~2 GiB headroom within the 14 GiB pod memory limit for JVM non-heap and OS overhead    |
| Replicas per host     | 4     | Symmetric; gives 8 total workers across the cluster (32 total cores, 96 GiB total Spark heap) |


`SPARK_WORKER_MEMORY` is set in `[vars/variables.yaml](../vars/variables.yaml)`. `SPARK_WORKER_CORES` is set inline in the worker manifest template.

---

## 4. Cluster-wide Kubernetes monitoring

These pods run on every node or are scheduled by the cluster.


| Component          | Scope                 | Mem request | Mem limit | CPU request | CPU limit | Config                                                                                |
| ------------------ | --------------------- | ----------- | --------- | ----------- | --------- | ------------------------------------------------------------------------------------- |
| node-exporter      | DaemonSet (all nodes) | 50 MiB      | 100 MiB   | 50m         | 200m      | `[k8s/monitoring/node-exporter.yaml](../k8s/monitoring/node-exporter.yaml)`           |
| kube-state-metrics | 1 pod (cluster)       | 64 MiB      | 256 MiB   | 10m         | 200m      | `[k8s/monitoring/kube-state-metrics.yaml](../k8s/monitoring/kube-state-metrics.yaml)` |


---

## 5. Elastic Agent

Elastic Agent runs as a **systemd service** on Lab1, Lab2, and Lab3. It collects system metrics (CPU, memory, disk, network) and ships them to Elasticsearch via Logstash.

There are no cgroup or systemd `MemoryMax`/`CPUQuota` limits configured. Typical steady-state memory is ~500 MiB per host. Configuration is in `[elastic-agent/](../elastic-agent/)`. Deployment is managed by `[ansible/playbooks/elastic-agent/install.yml](../ansible/playbooks/elastic-agent/install.yml)`.

---

## 6. iPython / PySpark interactive pods

The `launch_ipython.yml` playbook creates a short-lived PySpark pod for interactive use. Default resources: 500m CPU request / 1 CPU limit, 1 GiB memory request / 2 GiB memory limit. Override with `-e pyspark_ipython_cpu_limit=...` and `-e pyspark_ipython_memory_limit=...`.

Config: `[ansible/playbooks/spark/launch_ipython.yml](../ansible/playbooks/spark/launch_ipython.yml)`.

---

## 7. Log rotation and retention

Every log-producing component is configured with bounded rotation to prevent disk exhaustion.

### 7.1 Docker container logs (stdout/stderr)

All long-running Docker Compose services use a shared `json-file` logging driver with rotation. Configured via the `x-logging` anchor in [`observability/docker-compose.yml`](../observability/docker-compose.yml).

| Service            | Driver    | Max size | Max files | Cap   |
| ------------------ | --------- | -------- | --------- | ----- |
| Elasticsearch      | json-file | 50 MB    | 5         | 250 MB |
| Kibana             | json-file | 50 MB    | 5         | 250 MB |
| Grafana            | json-file | 50 MB    | 5         | 250 MB |
| Prometheus         | json-file | 50 MB    | 5         | 250 MB |
| Tempo              | json-file | 50 MB    | 5         | 250 MB |
| Logstash           | json-file | 50 MB    | 5         | 250 MB |
| OTel Collector     | json-file | 50 MB    | 5         | 250 MB |

Init containers (`init-certs`, `set-kibana-password`, `init-index`) are short-lived and excluded.

### 7.2 Application-level log rotation

| Component | Rotation mechanism | Max size | Files/age | Config |
| --------- | ------------------ | -------- | --------- | ------ |
| Grafana file logs | Built-in `[log.file]` | 128 MB (`max_size_shift=27`) | Daily, 7-day max | [`observability/grafana/grafana.ini`](../observability/grafana/grafana.ini) `[log.file]` |
| Logstash internal logs | Built-in rotation | 100 MB | 10 files, 7-day age | [`observability/logstash/config/logstash.yml`](../observability/logstash/config/logstash.yml) |
| Filebeat | Built-in rotation | 10 MB | 10 files | [`observability/filebeat/filebeat.yml`](../observability/filebeat/filebeat.yml) |
| Elastic Agent | Built-in rotation | 50 MB | 7 files | [`elastic-agent/elastic-agent.linux.yml.j2`](../elastic-agent/elastic-agent.linux.yml.j2) |

### 7.3 Spark logs

| Component | Rotation mechanism | Max size | Files/age | Config |
| --------- | ------------------ | -------- | --------- | ------ |
| GC logs (all: master, worker, history, driver, executor) | JVM `-Xlog:gc*` | 10 MB | 10 files | `spark-defaults.conf`, `spark-master.yaml.j2`, `spark-worker.yaml.j2`, `spark-history.yaml.j2` |
| Application logs (log4j2-cluster) | Log4j2 RollingFile | 20 MB | 10 files, 30-day delete | [`spark/conf/log4j2-cluster.properties`](../spark/conf/log4j2-cluster.properties) |
| Event logs (`/mnt/spark/events`) | History Server cleaner | — | 7-day max age, 100 file max | `spark.history.fs.cleaner.*` in [`spark/conf/spark-defaults.conf`](../spark/conf/spark-defaults.conf) and [`ansible/roles/spark/templates/spark-defaults.conf.j2`](../ansible/roles/spark/templates/spark-defaults.conf.j2) |

### 7.4 Kubernetes container logs

Kubelet container log rotation is configured in `/var/lib/kubelet/config.yaml` on each K8s node via [`ansible/playbooks/k8s/install.yml`](../ansible/playbooks/k8s/install.yml).

| Setting               | Value | Effect                            |
| --------------------- | ----- | --------------------------------- |
| `containerLogMaxSize` | 50 Mi | Rotates when a container log hits 50 MB |
| `containerLogMaxFiles` | 5    | Keeps at most 5 rotated files     |

### 7.5 Prometheus TSDB retention

Prometheus data retention is size- and time-bounded (not log rotation per se, but relevant to disk).

| Setting | Value | Config |
| ------- | ----- | ------ |
| `--storage.tsdb.retention.time` | 15 d | [`observability/docker-compose.yml`](../observability/docker-compose.yml) |
| `--storage.tsdb.retention.size` | 10 GB | Same |

---

## 8. Documentation map


| Location                                                  | Purpose                                                                                    |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `**docs/`** (this directory)                              | Cross-cutting: architecture, file-system layout, project overview, logging, DNS, runbooks. |
| `**observability/docs/**`                                 | Observability architecture (Prometheus/Tempo/ES pipeline, environment variables).          |
| `**observability/elasticsearch/docs/**`                   | Elasticsearch indices, APIs, ILM policies.                                                 |
| `**observability/grafana/docs/**`, `**prometheus/docs/**` | Component-specific notes.                                                                  |
| `**elastic-agent/docs/**`                                 | Elastic Agent deployment and behavior.                                                     |
| `**ansible/playbooks/spark/README.md**`                   | Spark playbook usage and resource details.                                                 |


---

## 9. Related documents

- [File_System_Architecture.md](File_System_Architecture.md) — DevOps/Ops paths, NFS mounts, certificates.
- [Application_Locations.md](Application_Locations.md) — URLs and client tools.
- [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) — Setup entry points and playbooks.
- [Log_Architecture.md](Log_Architecture.md) — Log pipelines (NFS server host = Lab3).
- [Prometheus and Grafana Tempo Architecture](../observability/docs/Prometheus_Tempo_Architecture.md) — Metrics and traces path into Elasticsearch.

