# Ansible Playbooks for Spark Observability Platform

This directory contains Ansible playbooks for managing the Spark Observability infrastructure across **Lab1**, **Lab2**, and **Lab3** (native Linux). Observability (Docker Compose) runs on **Lab3** per `inventory.yml` (`observability_host`).

## Global Playbooks

These playbooks orchestrate multiple components in the correct dependency order:

### `install.yml` — Host and cluster foundation
Installs packages and configures Docker, NFS (server per `nfs_servers` + clients on K8s nodes), Kubernetes, and Elastic Agent. **Does not** deploy Spark/Jupyter/observability workloads; run `deploy.yml` next.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/install.yml
```

**Order:** Docker (Lab3) → NFS → Kubernetes → Elastic Agent.

### `deploy.yml` — Deploy workloads
Applies Hadoop (if used), observability stack, Spark registry client on nodes, Spark on Kubernetes (including OTel listener), and JupyterHub.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/deploy.yml
```

**Prerequisites:** `install.yml` (or equivalent) completed.

**Hadoop / HDFS:** The Hadoop import is tagged `hadoop`. If `kubectl apply` errors because existing StatefulSets cannot be updated in place, run `ansible-playbook ... playbooks/deploy.yml --skip-tags hadoop` after fixing or removing the old `hdfs-namenode` StatefulSet, or run `playbooks/k8s/hadoop/deploy_hadoop.yml` alone when the cluster is clean.

### `start.yml` — Start runtime services
Starts NFS, Kubernetes, Docker on Lab3, observability Compose stack, Elastic Agent refresh, and Spark pods.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/start.yml
```

**Prerequisites:** `install.yml` and `deploy.yml` for first-time bring-up.

### `diagnose.yml` — Full platform diagnostics
Runs component `diagnose` playbooks (Docker, NFS, Kubernetes, observability, Spark, Elastic Agent). Replaces the former top-level `status.yml`.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/diagnose.yml
```

Lightweight checks remain available under each component (e.g. `spark/status.yml`, `observability/status.yml`, `elastic-agent/status.yml`).

### `stop.yml` - Stop All Services
Stops the full Spark Observability stack in a safe order: Jupyter and Spark workloads, HDFS (scale to zero), in-cluster Prometheus exporters, Elastic Agent, observability Docker Compose, Docker on the observability host, Kubernetes (kubelet + containerd on workers then master), and the NFS server.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/stop.yml
```

**Shutdown order (summary):**
1. JupyterHub (spark namespace)
2. Spark (spark namespace)
3. HDFS (`hdfs` namespace)
4. node-exporter + kube-state-metrics
5. Elastic Agent (all `linux` hosts)
6. Observability (`docker compose down` on `observability`)
7. Docker service and `docker.socket` on observability host (socket stop prevents accidental restart via `docker` clients)
8. Kubernetes (workers first, then control plane)
9. NFS server (`nfs_servers`)

**Note:** This does not remove Kubernetes packages or etcd data; it stops runtimes so pods (including `kube-system` / CNI) are no longer running on the nodes. Use `k8s/uninstall.yml` or reset playbooks only if you intend to remove the cluster.

**Use Cases:**
- System shutdown/maintenance
- Free up system resources
- Prepare for system updates

## Component-Specific Playbooks

For fine-grained control, use component-specific playbooks in subdirectories:

### Docker (`docker/`)
- `install.yml` - Install Docker on **observability** hosts (Lab3; `docker.io` + `docker-compose-v2`)
- `uninstall.yml` - Remove Docker packages
- `start.yml` / `stop.yml` - Docker systemd service
- `diagnose.yml` - Check Docker status

> **Note:** Kubernetes uses **containerd**. Docker Engine on Lab3 runs the observability stack; Lab2 may still use Docker for image build/registry steps depending on playbooks in use.

### NFS (`nfs/`)
- `install.yml` - Install NFS server and configure clients (includes all exports and data setup)
- `uninstall.yml` - Remove NFS server and clients
- `start.yml` - Start NFS server
- `stop.yml` - Stop NFS server
- `diagnose.yml` - NFS server and client mounts

### Kubernetes (`k8s/`)
- `install.yml` - Install Kubernetes cluster
- `uninstall.yml` - Remove Kubernetes cluster
- `start.yml` - Start Kubernetes services
- `stop.yml` - Stop Kubernetes services
- `diagnose.yml` - Cluster troubleshooting and health
- `reset_k8s.yml` - Reset cluster (special utility - wipes all data)

### Observability (`observability/`)
- `install.yml` - Install observability platform
- `start.yml` - Start observability services
- `stop.yml` - Stop observability services
- `status.yml` - Check observability services
- `uninstall.yml` - Remove observability platform

### Spark (`spark/`)
- `deploy.yml` - Deploy Spark on Kubernetes (includes all config and mounting)
- `undeploy.yml` - Remove Spark from Kubernetes
- `start.yml` - Start Spark components
- `stop.yml` - Stop Spark components
- `status.yml` - Check Spark cluster status

### CS224N (`CS224N/`)
- `deploy.yml` - Stage CS224N artifacts and redeploy Jupyter with cs224n bootstrap
- `undeploy.yml` - Remove cs224n kernel/env and staged artifacts

### Elastic Agent (`elastic-agent/`)
- `install.yml` - Install Elastic Agent on hosts (includes cert distribution and setup)
- `uninstall.yml` - Remove Elastic Agent
- `start.yml` - Start Elastic Agent service
- `stop.yml` - Stop Elastic Agent service
- `status.yml` - Check Elastic Agent status

## Infrastructure Overview

### Hosts

| Host | Role | Components |
|------|------|------------|
| **Lab1** | Kubernetes worker | Kubernetes worker (containerd), Elastic Agent (typical) |
| **Lab2** | Kubernetes master+worker, data plane | K8s control plane + worker (containerd), Hadoop (per inventory), Jupyter scheduling target (per inventory), Elastic Agent |
| **Lab3** | Observability + NFS + dev / control | NFS server (`nfs_servers`), Docker Compose stack (Elasticsearch, Kibana, Grafana, Logstash, Prometheus, Tempo, OTel collector, etc.), optional Ansible control node |

### Service URLs

After startup, services are accessible at:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Kibana** | http://Lab3.lan:5601 | See `vars/secrets.yaml` → generated `observability_docker.env` |
| **Grafana** | http://Lab3.lan:3000 | `GF_SECURITY_ADMIN_*` from same env / secrets |
| **Elasticsearch** | https://Lab3.lan:9200 | `ES_USER` / `ES_PASSWORD` from same |
| **Spark History Server** | http://Lab2.lan:31534 | (no auth) |
| **Spark Master UI** | http://Lab2.lan:32290 | (no auth) |

> **Note:** JupyterHub will be added during Spark 4.0 migration with Python 3.11 support.

## Common Workflows

### First-Time Setup
```bash
cd ansible

ansible-playbook -i inventory.yml playbooks/install.yml
ansible-playbook -i inventory.yml playbooks/deploy.yml
ansible-playbook -i inventory.yml playbooks/start.yml
ansible-playbook -i inventory.yml playbooks/diagnose.yml
```

### Daily Development Startup
```bash
cd ansible

# Start all services (assumes already installed)
ansible-playbook -i inventory.yml playbooks/start.yml
```

### Troubleshooting
```bash
cd ansible

ansible-playbook -i inventory.yml playbooks/diagnose.yml

# Component-specific (examples)
ansible-playbook -i inventory.yml playbooks/k8s/diagnose.yml

# Check Kubernetes pods
kubectl get pods -n spark
kubectl get svc -n spark

# Check Spark logs
kubectl logs -n spark <pod-name>
```

### Maintenance/Shutdown
```bash
cd ansible

# Stop all services gracefully
ansible-playbook -i inventory.yml playbooks/stop.yml
```

## Prerequisites

### Control Machine
- Ansible installed
- SSH access to all hosts
- Python 3.x

### Target Hosts
- Ubuntu/Debian Linux (Lab1, Lab2)
- WSL2 Ubuntu (GaryPC-WSL)
- SSH server configured
- User 'ansible' with sudo privileges

### Special Notes

#### Docker on GaryPC WSL
Docker Desktop must be started **manually** through the Windows UI before running playbooks. The playbooks will verify Docker is running but cannot start it automatically on WSL.

#### Running Playbooks
All playbooks should be run from the `ansible` directory to ensure proper loading of `ansible.cfg` and role paths:

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/<playbook-name>.yml
```

## Best Practices

1. **Always run from ansible directory** - Ensures ansible.cfg is loaded
2. **Check status before starting** - Verify prerequisites are met
3. **Review logs after operations** - Check for errors or warnings
4. **Use global playbooks for common tasks** - Ensures correct dependency order
5. **Use component playbooks for specific tasks** - Better for troubleshooting

## Troubleshooting

### Common Issues

**Playbook fails to find roles:**
- Ensure you're running from the `ansible` directory
- Check that `ansible.cfg` exists in the ansible directory

**SSH connection failures:**
- Verify SSH keys are set up: `ssh ansible@Lab1.lan`
- Check inventory.yml has correct hostnames/IPs

**Docker not available on GaryPC:**
- Manually start Docker Desktop on Windows
- Verify with: `docker ps`

**Kubernetes pods not starting:**
- Check Kubernetes status: `kubectl get nodes`
- Check pod logs: `kubectl logs -n spark <pod-name>`
- Run diagnostics: `ansible-playbook -i inventory.yml playbooks/k8s/diagnose.yml`

**Observability services not accessible:**
- Check Docker containers: `docker ps`
- Check logs: `docker-compose logs` (in observability directory)
- Verify network connectivity: `ping GaryPC.lan`

## Additional Resources

- [Project Overview](../../docs/PROJECT_OVERVIEW.md)
- [Running Ansible Playbooks](../../docs/RUNNING_ANSIBLE_PLAYBOOKS.md)
- [Kubernetes Management](k8s/README.md)
- [Spark Deployment](spark/README.md)
- [Observability Platform](observability/README.md)

