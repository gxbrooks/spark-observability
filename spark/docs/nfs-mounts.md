# Spark NFS mounts: layout, ownership, and clients

This document describes the **shared Spark storage contract** used across the lab: **export paths on the NFS server**, **host paths under `/mnt/spark`**, **ownership and permissions**, and **which automation owns each class of machine**.

The **authoritative** automation for cluster nodes is Ansible: `ansible/playbooks/nfs/install.yml`. Shell helpers under `linux/` are for **developer / managed workstations** and overlap in intent but differ on the **NFS server host** (see [Classes of clients](#classes-of-clients)).

## Canonical mount table

All writable Spark shared directories use the same permission pattern: **owner `spark`**, **group `spark`**, **mode `2775`** (setgid directory so new files stay group-`spark`). The Ansible playbook creates directories with `mode: '2775'`, `owner: spark`, `group: spark`.

| Host path | NFS export (server) | Purpose |
|-----------|---------------------|---------|
| `/mnt/spark/events` | `/srv/nfs/spark/events` | Spark event logs (History Server, agents) |
| `/mnt/spark/data` | `/srv/nfs/spark/data` | Shared datasets, OTel JAR copy target, etc. |
| `/mnt/spark/logs` | `/srv/nfs/spark/logs` | Application / GC logs layout under NFS |
| `/mnt/spark/checkpoints` | `/srv/nfs/spark/checkpoints` | Streaming checkpoints |
| `/mnt/spark/jupyter` | `/srv/nfs/jupyterhub` | JupyterHub shared tree (notebooks path under this tree) |

**Root directory:** `/mnt/spark` is also **`spark:spark`**, mode **`2775`**.

**Exported but not under `/mnt/spark` in automation:** `/srv/nfs/jupyterhub-users` is listed in the server export list in `nfs/install.yml` for NFS use by JupyterHub (or other consumers). There is **no** corresponding `/mnt/spark/...` bind or client mount defined in that playbook today.

## Server perspective (`nfs_servers`)

**Physical / export layout**

- Export root for Spark data: `/srv/nfs/spark` (plus Jupyter paths under `/srv/nfs/jupyterhub*`).
- Export options in Ansible: `*(rw,sync,no_root_squash,no_subtree_check,insecure)` (see `nfs/install.yml`).
- Exports are written to `/etc/exports` and applied with `exportfs -ra`.

**`/mnt/spark` on the server**

- The server does **not** loopback-mount its own NFS for these paths in the playbook.
- Instead it uses **bind mounts**: each `/mnt/spark/<name>` is bound to the matching `/srv/nfs/...` directory (`fstype: none`, `opts: bind`).
- **Why bind mounts, not symlinks:** Kubernetes `hostPath` volumes expect a **real mountpoint** at `/mnt/spark/...`. A symlink to `/srv/...` used to make the path “look” right but left `hostPath` pointing at an unmounted directory; bind mounts keep the **contract path** (`/mnt/spark/...`) a true mount target.

**Legacy symlink cleanup**

- The playbook **stats** each bind target with `follow: false` and removes **`/mnt/spark/...` only when it is a symlink** before recreating directories and bind mounts.

## Kubernetes node perspective

Inventory groups (see `ansible/inventory.yml`):

- **`nfs_servers`**: NFS daemon + exports + **bind mounts** to `/mnt/spark/...`.
- **`kubernetes_master:kubernetes_workers:!nfs_servers`**: **NFS clients** only (machines that are K8s nodes but **not** the NFS server host).

Because the control plane host is also the NFS server in this lab, it is in `nfs_servers` and is **excluded** from the NFS-client play: it gets **bind mounts**, not `nfs` fstab entries.

**Client mounts (non-server K8s nodes)**

- **fstab/fs type:** `fstype: nfs`, **options:** `rw,sync,nfsvers=4` (NFSv4 over TCP).
- **Source:** `<nfs_server_dns>:/srv/nfs/...` where `nfs_server` is the `ansible_host` of `groups['nfs_servers'][0]` (DNS name, not a raw IP).

**Contract checks**

- `ansible/playbooks/k8s/diagnose.yml` verifies each of the five `/mnt/spark/*` paths is active, distinguishes **NFS** mounts from **bind** mounts on the server, and checks **`spark:spark`** + mode **`2775`** (via `stat` with `follow: true`).

## Classes of clients

### 1) Kubernetes nodes (Spark workers / master on cluster hosts)

- **Configure:** `ansible/playbooks/nfs/install.yml` (NFS client play).
- **Behavior:** Real NFSv4 mounts at `/mnt/spark/...` from the server’s export paths.
- **Same ownership/permission contract** as the server (`2775`, `spark:spark`).

### 2) NFS server host (same machine may run control plane / observability)

- **Configure:** `nfs/install.yml` server play + bind-mount play.
- **Behavior:** Local `/srv/nfs/...` trees, **bind-mounted** at `/mnt/spark/...`.
- **Not** a member of the Ansible “NFS client” play when it is listed in `nfs_servers`.

### 3) Managed developer / client machines (“client node” initialization)

- **Configure:** `linux/assert_client_node.sh` → `linux/assert_spark_mounts.sh`.
- **Behavior (typical workstation, not the NFS server):** Installs `nfs-common` if needed, mounts **`NFS_SERVER:/srv/nfs/...` → `/mnt/spark/...`** with NFSv4 options, and can add **`/etc/fstab`** lines (`nfs4`, `nfsvers=4,defaults,_netdev`).
- **Behavior (when the script believes it is on the NFS server):** It avoids NFS loopback and uses **symlinks** from `/mnt/spark/...` → `/srv/nfs/...` for the five paths.

**Important:** The symlink behavior on the **server host** in `assert_spark_mounts.sh` is **not** the same as the Ansible bind-mount standard. For any host that runs Kubernetes with `hostPath` under `/mnt/spark`, **use the Ansible playbook** so `/mnt/spark/*` are real mountpoints. Use the shell script on pure dev machines or after the server layout matches Ansible.

### 4) Lightweight NFS checks elsewhere

- `linux/assert_nfs_client.sh` — sanity for **`SPARK_DATA_MOUNT`** (default `/mnt/spark/data`) only: mount present, writable, sample data. Does not manage all five paths.

## Files that create or configure mounts

| Location | Role |
|----------|------|
| `ansible/playbooks/nfs/install.yml` | **Primary:** exports, directories, bind mounts on server, NFS mounts on non-server K8s nodes, symlink cleanup, `/etc/fstab` via Ansible `mount`. |
| `ansible/playbooks/tasks/regenerate_contexts.yml` + `vars/generate_contexts.sh` / `vars/generate_contexts.py` | Regenerates **`nfs`** context; `nfs/install.yml` loads `vars/contexts/nfs_ansible_vars.yml` (generated; `vars/contexts/` is gitignored). |
| `vars/variables.yaml` | Source definitions for `NFS_SERVER`, mount paths, and nfs-only vars consumed by `generate_contexts.py`. |
| `linux/assert_spark_mounts.sh` | Workstation-oriented mount + permission enforcement; server branch uses symlinks (see above). |
| `linux/assert_spark_events_mount.sh` | Deprecated wrapper; delegates to `assert_spark_mounts.sh`. |
| `linux/assert_client_node.sh` | Calls `assert_spark_mounts.sh` during client-node setup. |
| `ansible/playbooks/k8s/diagnose.yml` | Validation of mount presence type (NFS vs bind) and `spark:spark` / `2775` contract. |
| `ansible/playbooks/nfs/diagnose.yml` | High-level NFS service / `exportfs` / mount listing diagnostics. |
| `ansible/playbooks/spark/deploy.yml` | Pre-flight shell check that `/mnt/spark/events` exists and is writable on targeted nodes. |

## Operational notes

- **Pods and hostPath:** If mounts were down when a pod started, it may have bound an empty directory. After fixing mounts, **restart affected pods** so they see the live mount.
- **Single source for “what should be mounted”:** Prefer the lists in `nfs/install.yml` (`bind_mounts`, `nfs_mounts`, `nfs_export_dirs`) when changing the contract; keep `assert_spark_mounts.sh` `MOUNT_POINTS` in sync for dev machines.
