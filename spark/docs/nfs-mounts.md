# Spark NFS mounts: layout, ownership, and clients

This document describes the **shared Spark storage contract** used across the lab: **export paths on the NFS server**, **host paths under `/mnt/spark`**, **ownership and permissions**, and **which automation owns each class of machine**.

`vars/variables.yaml` is the SSOT for shared variable specifications. `ansible/playbooks/nfs/install.yml` is the implementation SSOT for how mount points are created and enforced on cluster hosts. Shell helpers under `linux/` are for **developer / managed workstations** and overlap in intent but differ on the **NFS server host** (see [Classes of clients](#classes-of-clients)).

## NFS view vs local filesystem view

Kubernetes nodes expose a **single contract path** (`/mnt/spark/...`) to pods, OneAgent, and Elastic Agent. What sits behind that path differs by subdirectory:

| Contract path (all K8s nodes) | NFS server export (`Lab3`) | Worker / master node backing store | Visible on other nodes? | OneAgent tails here? |
|------------------------------|----------------------------|------------------------------------|-------------------------|----------------------|
| `/mnt/spark/events` | `/srv/nfs/spark/events` | NFS mount (Lab1–2) or bind to export (Lab3) | **Yes** — shared | No (not app log tail source) |
| `/mnt/spark/data` | `/srv/nfs/spark/data` | NFS / bind | **Yes** — shared | No |
| `/mnt/spark/checkpoints` | `/srv/nfs/spark/checkpoints` | NFS / bind | **Yes** — shared | No |
| `/mnt/spark/jupyter` | `/srv/nfs/jupyterhub` | NFS / bind | **Yes** — shared | No |
| `/mnt/spark/jars` | *(none)* | Per-host `hostPath` | No | No |
| **`/mnt/spark/logs`** | **Not exported** (legacy tree may remain at `/srv/nfs/spark/logs` on the server, unmounted) | **`/var/local/spark/logs` bind-mounted at `/mnt/spark/logs`** | **No** — **node-local only** | **Yes** — **only the host where the file was written** |
| `/mnt/spark/logs/spark-client/<hostname>/` | *(under local logs root)* | Same local store as above | No | Yes — client driver on that host |
| `/mnt/spark/logs/<pod-name>/` | *(under local logs root)* | Same local store; pod `hostPath` on scheduling node | No | Yes — only on the node running the pod |

**Design rule:** Dynatrace OneAgent and OpenPipeline must see **one physical file per log path**. Application logs therefore **must not** live on a shared NFS mount. Shared NFS remains for **events, datasets, and checkpoints** — data that executors and the History Server must read across nodes.

### What OneAgent uses

OneAgent custom log sources tail **`/mnt/spark/logs/*/spark-app.log*`** on **the local host filesystem**. After `nfs/install.yml`, that path is always the **local bind** (`/var/local/spark/logs`), not NFS. Each host only sees log directories created on **that** machine (pod logs on the scheduled node; client logs on the driver host).

## Canonical mount table

Writable **shared** directories use **owner `spark`**, **group `spark`**, **mode `2775`** (setgid). Application logs use the same directory contract on the local store; **log files** use **`spark:spark` mode `664`** (see [Application log permissions](#application-log-permissions)).

| Host path | NFS export (server) | Purpose |
|-----------|---------------------|---------|
| `/mnt/spark/events` | `/srv/nfs/spark/events` | Spark event logs (History Server, agents) |
| `/mnt/spark/data` | `/srv/nfs/spark/data` | Shared application datasets (read/write) |
| `/mnt/spark/jars` | *(none — per-host hostPath)* | Runtime JARs for Spark in Kubernetes (OTel listener, etc.) |
| `/mnt/spark/logs` | **Local only** — `/var/local/spark/logs` → bind at `/mnt/spark/logs` | Application / GC logs (**per-host**, not NFS) |
| `/mnt/spark/checkpoints` | `/srv/nfs/spark/checkpoints` | Streaming checkpoints |
| `/mnt/spark/jupyter` | `/srv/nfs/jupyterhub` | JupyterHub shared tree |

**Root directory:** `/mnt/spark` is **`spark:spark`**, mode **`2775`**.

## Application log permissions

OneAgent runs as **`dtuser`**. Pod log files are written as **`spark:spark`**. Client-mode chapter drivers run as the interactive user (e.g. **`gxbrooks`**) but must still be readable by OneAgent.

| Object | Owner | Group | Mode | Notes |
|--------|-------|-------|------|-------|
| `/var/local/spark/logs` | `spark` | `spark` | `2775` | Local store; bind-mounted at `/mnt/spark/logs` |
| `/mnt/spark/logs/<pod>/` | `spark` | `spark` | `755` | Created by pod init / `chown 185:185` before Spark starts |
| Pod `spark-app.log` | `spark` | `spark` | `664` | Log4j cluster config; world-readable |
| `/mnt/spark/logs/spark-client/<hostname>/` | `spark` or driver user | `spark` | `755` | Directory must be traversable by `dtuser` |
| Client `spark-app.log` | driver user | `spark` | `644` | Set via Log4j `filePermissions = rw-r--r--` in `log4j2-client.properties` |

**Group membership:** `ansible/playbooks/nfs/install.yml` adds **`dtuser`** to supplementary group **`spark`** on Kubernetes nodes so group-readable client logs (`664`) are tailed without opening other-writable permissions.

**Elastic Agent** (where deployed) uses the same paths; members of group **`spark`** (including **`elastic-agent`**) read pod logs.

## `vars/variables.yaml` and `/mnt/spark`

Centralized variables live in `vars/variables.yaml` and are emitted into context files by `vars/generate_contexts.py` (e.g. `spark-runtime`, `spark-client`, `nfs`, `devops`). Only a **subset** of the `/mnt/spark/*` paths are named there today; the rest are implied by playbooks and shell scripts.

| Variable | Value (as in repo) | Contexts (where generated) | Role |
|----------|-------------------|----------------------------|------|
| `SPARK_EVENTS_DIR` | `/mnt/spark/events` | `spark-runtime`, `ansible`, `elastic-agent`, `spark-client` | Event log directory for cluster config, agents, and local clients |
| `SPARK_MOUNT_BASE` | `/mnt/spark` | `spark-runtime`, `nfs` | Shared parent path under NFS on nodes |
| `SPARK_DATA_MOUNT` | `/mnt/spark/data` | `spark-runtime`, `nfs`, `spark-client` | Dataset / shared data mount |
| `NFS_SERVER` | e.g. `Lab3.lan` | `spark-runtime`, `nfs`, `devops` | NFS server hostname for clients and env scripts |
| `NFS_SPARK_DATA_EXPORT` | `/srv/nfs/spark/data` | `nfs` only | Server-side export path for data |

Client log directory: **`/mnt/spark/logs/spark-client/$(hostname -s)/`** — set by `spark/apps/data-analysis-book/run-chapters.sh` (`SPARK_LOG_DIR`).

## Kubernetes: mounts on the node vs “only in pods”

**The nodes must have the mounts.** Spark workloads use **`hostPath`** volumes that bind **paths on the Linux host** (e.g. `/mnt/spark/data`, `/mnt/spark/logs/$(POD_NAME)`) into containers. The kubelet does not mount NFS for you.

For **shared** paths (`events`, `data`, `checkpoints`, `jupyter`): NFS client mount on workers, bind mount on the NFS server host.

For **`/mnt/spark/logs`**: **local disk only** on each Kubernetes node — no NFS export, no cross-node visibility.

## Server perspective (`nfs_servers`)

- Export root: `/srv/nfs/spark` (plus Jupyter paths).
- **`/srv/nfs/spark/logs` is no longer exported.** Legacy files may remain on the server disk for manual archive/migration; they are not mounted at `/mnt/spark/logs`.
- Other `/mnt/spark/*` shared paths use **bind mounts** from `/srv/nfs/...` on Lab3.

## Kubernetes node perspective

- **`kubernetes_master:kubernetes_workers:!nfs_servers`**: NFSv4 mounts for **events, data, checkpoints, jupyter** only.
- **All `kubernetes_master:kubernetes_workers` hosts** (including Lab3): **`/mnt/spark/logs`** ← bind **`/var/local/spark/logs`**.

After changing the logs mount, **restart Spark pods** on affected nodes so `hostPath` log directories attach to the live local mount.

## Classes of clients

### 1) Kubernetes nodes

- **Configure:** `ansible/playbooks/nfs/install.yml`.
- **Shared paths:** NFSv4 from `Lab3.lan:/srv/nfs/spark/...`.
- **Application logs:** local bind only.

### 2) NFS server host (Lab3)

- **Configure:** server play + bind mounts for shared paths + local logs play.
- **Not** an NFS client for shared Spark paths (uses binds).

### 3) Developer workstations

- **Configure:** `linux/assert_spark_mounts.sh` — NFS for shared paths; **local** `/var/local/spark/logs` (or equivalent) for application logs when running chapter drivers against the cluster.

## Files that create or configure mounts

| Location | Role |
|----------|------|
| `ansible/playbooks/nfs/install.yml` | Exports, shared NFS mounts, **local application log bind**, `dtuser` → `spark` |
| `ansible/playbooks/k8s/diagnose.yml` | Validates mount presence and `spark:spark` / `2775` contract |
| `spark/conf/log4j2-client.properties` | Client log file permissions (`rw-r--r--`) |
| `spark/apps/data-analysis-book/run-chapters.sh` | `SPARK_LOG_DIR=/mnt/spark/logs/spark-client/<hostname>/` |

## Operational notes

- **Pods and hostPath:** If mounts were wrong when a pod started, restart the pod after fixing `/mnt/spark/logs`.
- **Single OneAgent tail:** If a log file appears on multiple hosts, `/mnt/spark/logs` is still on NFS — re-run `nfs/install.yml` and verify `findmnt -T /mnt/spark/logs` shows **`/var/local/spark/logs`**, not `nfs`.
- **Do not** re-export `/srv/nfs/spark/logs` without an explicit architecture change; it breaks per-host OneAgent attribution.
