# Kubernetes PKI and kubeconfig layout

## Where private keys live

| Role | Canonical paths | Notes |
|------|-----------------|--------|
| **Control plane** (`kubernetes_master` in `ansible/inventory.yml`) | `/etc/kubernetes/pki/` | Cluster CA: `ca.crt` / `ca.key`. **kubernetes-admin** client: `admin.crt` / `admin.key`. API server, etcd, front-proxy certs, SA keys, etc. |
| **Aggregated admin kubeconfig** | `/etc/kubernetes/admin.conf` | Single file with **embedded** `certificate-authority-data`, `client-certificate-data`, `client-key-data` (base64). Preferred source for **kubectl** on hosts that should talk to the API as `kubernetes-admin`. |
| **Worker nodes** | `/etc/kubernetes/pki/` (partial) | After `kubeadm join`: typically `ca.crt`, kubelet client material — **not** the full set of control-plane keys and **not** `admin.key`. Workers are not a source for cluster-admin credentials. |

**Important:** The **cluster CA** and **`kubernetes-admin` private key** are created on the **control plane** during `kubeadm init`. They are **not** replicated to arbitrary workers (e.g. Lab2) unless you explicitly copy them (not recommended). If you see `~/.kube/certs/` on one machine and not another, that is usually a **client tool** layout, not a kubeadm default.

## Recommended layout for interactive users (devops)

- **`~/.kube/config`**: primary file for `kubectl`. Contents should match the control plane’s **`/etc/kubernetes/admin.conf`**, with **`cluster.server`** set to **`KUBERNETES_API_SERVER_URL`** (e.g. `https://Lab3.lan:6443`) from `vars/variables.yaml`.
- **Optional** file-based layout (not required): `client-certificate`, `client-key`, `certificate-authority` pointing at PEM files — equivalent to embedded base64 in `admin.conf`.

## Automation in this repo

- **Ansible** `playbooks/k8s/install.yml` (tags `kubeconfig`) builds `~/.kube/config` for the control-plane users using **`admin.crt` / `admin.key`** and **`ca.crt`**.
- **Ansible** `playbooks/k8s/provision_admin_kubeconfig.yml` copies **`/etc/kubernetes/admin.conf`** to **every** node in `k8s_nodes` so **`kubectl --kubeconfig=/etc/kubernetes/admin.conf`** works on workers for break-glass debugging.
- **`regenerate_k8s_certs.yml`** updates certs on the **control plane**; re-run **`install.yml --tags kubeconfig`** and refresh local `~/.kube/config` (or rely on **`linux/sync_devops_kubeconfig.sh`** after updating env vars).

## Devops shell sync (no playbook ordering dependency)

`linux/sync_devops_kubeconfig.sh` is sourced from **`.bashrc`**. It compares **`sha256`** of `/etc/kubernetes/admin.conf` on **`KUBERNETES_API_SERVER`** (SSH as `ansible`) with a stamp in **`~/.kube/.spark-observability-admin.conf.sha256`**, and refreshes **`~/.kube/config`** when the control plane file changes. It does **not** require running `assert_client_node.sh` first.

## Spark driver vs Kubernetes API

Spark’s **master** URL (`SPARK_MASTER_HOST` / `SPARK_MASTER_PORT`, e.g. `Lab3.lan:31686`) is **independent** of **`KUBERNETES_API_SERVER`**. Connection refused on the Spark master usually means the Spark services are not running — start the stack with Ansible (`playbooks/start.yml` / Spark playbooks), not kubeconfig sync.
