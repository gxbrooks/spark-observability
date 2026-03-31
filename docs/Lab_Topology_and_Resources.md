# Lab topology and resource plan

This document is the **project-wide** reference for how lab hosts are partitioned, which services run where, and how CPU/RAM/disk are budgeted. It reflects the **target** layout (migration in progress): inventory and playbooks may lag until cutover is complete.

For file-system paths and NFS layout, see [File_System_Architecture.md](File_System_Architecture.md). For Prometheus/Tempo/ES metrics flow, see [Prometheus and Grafana Tempo Architecture](../observability/docs/Prometheus_Tempo_Architecture.md).

---

## Host roles

| Host | Role (target) |
|------|------------------|
| **Lab3.lan** | Observability stack (Docker Compose: Elasticsearch, Kibana, Grafana, Prometheus, Tempo, Logstash, OTel Collector, …), **Kubernetes control plane**, **HDFS** (NameNode + DataNode on-cluster), **NFS server** (`/srv/nfs/...`), **JupyterHub** (Spark namespace). Single “ops” node for control-plane and shared data services. |
| **Lab1.lan**, **Lab2.lan** | **Symmetric Spark workers** (Kubernetes workers, Spark executors). Dedicated to compute; no observability stack, no NFS server, no HDFS services in the target design. |

DNS and IPs are documented for humans in `ansible/inventory.yml` (`expected_ips`); configs should use `*.lan` names, not literals.

---

## Lab3 hardware (planning baseline)

| Resource | Capacity | Notes |
|----------|----------|--------|
| RAM | 64 GB | Shared by OS, Docker, kubelet/containerd, and all co-located services below. |
| vCPU | 16 | Shared; avoid sustained 100% on all cores during normal operation. |
| Disk | 1 TB | OS, Docker volumes, `etcd`, container images, HDFS and NFS **data** (HDFS and NFS are lightly used today; size for **migrated** data from Lab2 plus growth). |

---

## Service placement and resource caps (target)

Values are **planning caps** (upper bounds), not a guarantee that every service sits at its limit at once. **HDFS, NFS, and Jupyter** are intentionally at the **lower end** of the range because current usage is light; tighten or raise caps when workloads grow.

### Observability (Docker on Lab3)

Stack is defined in `observability/docker-compose.yml` (memory limits per container). Aggregate container limits for long-running services are on the order of **~15–18 GiB** (Elasticsearch 4 GiB, Kibana 2 GiB, Grafana 2 GiB, Prometheus 3 GiB, Tempo 2 GiB, Logstash 2 GiB, OTel Collector 256 MiB, plus overhead).

**Prometheus** is used primarily as a **scrape + forward path**: Kubernetes metrics are scraped from the API server / kubelets, then **remote write (v2)** into the **OTel Collector** and on into **Elasticsearch** for dashboards and retention. The **local TSDB** is for short retention and operator debugging, **not** the primary long-term analytics store (see observability Prometheus doc).

### Kubernetes control plane (Lab3)

Runs on the same host as Docker (kubeadm-style single control-plane node). Budget roughly **6–8 GiB RAM** and **~2–3 vCPU** for `etcd`, API server, scheduler, controller-manager, kubelet, and base addons under normal load.

### HDFS (on-cluster, Lab3)

HDFS stays **on Lab3** (single DataNode with current manifests; replication factor 1 in dev configs). **Planning cap (combined NN+DN JVM / pod memory): ~2–4 GiB** at the low end while usage stays light. Persisted disk for NameNode/DataNode must cover **migrated** HDFS content from Lab2.

### NFS server (Lab3)

Kernel NFS exports for Spark/Jupyter paths (`/srv/nfs/spark/...`, etc.). **Planning cap: ~0.5–1 GiB RAM** for daemon and cache; **disk** is dominated by **migrated** NFS data from Lab2.

### JupyterHub (Kubernetes on Lab3)

Deployed via Spark playbooks; pod template uses **requests 2 GiB / limits 4 GiB** CPU/memory (see `ansible/roles/spark/templates/jupyterhub-deployment.yaml.j2`). Treat **4 GiB** as the **upper cap** for planning on a loaded node.

---

## Coexistence check (order of magnitude)

For Lab3, a rough simultaneous budget is:

- Observability (Docker limits + overhead): **~18–22 GiB**
- Kubernetes control plane + base CNI/DNS: **~6–8 GiB**
- JupyterHub (limit): **~4 GiB**
- HDFS (light): **~2–4 GiB**
- NFS (kernel): **~1 GiB**
- OS, Docker engine, logging, ssh, agents: **~3–4 GiB**
- **Headroom** (spikes, page cache, ES merges): **~8–12 GiB**

Total lands in the **~42–52 GiB** range before headroom, which **fits 64 GiB** if HDFS/NFS/Jupyter stay light and observability retention is not expanded blindly. **CPU** at **16 vCPU** is adequate but not oversized when Prometheus scrapes the cluster and Docker runs concurrently; watch peak load during heavy Spark activity on **workers** (Lab1/Lab2), not necessarily on Lab3.

---

## Documentation map (global vs module)

| Location | Purpose |
|----------|---------|
| **`docs/`** (this directory) | Cross-cutting topics: lab topology, file-system layout, project overview, logging strategy, DNS, runbooks that span Ansible + Spark + observability. |
| **`observability/docs/`** | Observability-specific architecture (e.g. Prometheus/Tempo/ES). |
| **`observability/elasticsearch/docs/`** | Elasticsearch indices, APIs, ILM. |
| **`observability/grafana/docs/`**, **`prometheus/docs/`**, etc. | Component-specific notes. |
| **`elastic-agent/docs/`** | Elastic Agent deployment and behavior. |

---

## Related documents

- [File_System_Architecture.md](File_System_Architecture.md) — DevOps/Ops paths, NFS mounts, certificates.
- [Application_Locations.md](Application_Locations.md) — URLs and client tools.
- [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) — Setup entry points and playbooks.
- [Log_Architecture.md](Log_Architecture.md) — Log pipelines (NFS server host = Lab3 in target layout).
- [../observability/docs/Prometheus_Tempo_Architecture.md](../observability/docs/Prometheus_Tempo_Architecture.md) — Metrics and traces path into Elasticsearch.
