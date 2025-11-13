# Ansible Playbooks for Spark Observability Platform

This directory contains Ansible playbooks for managing the complete Spark Observability infrastructure across Lab1, Lab2, and GaryPC WSL.

## Global Playbooks

These playbooks orchestrate multiple components in the correct dependency order:

### `install.yml` - Complete Installation
Installs and configures all components from scratch (idempotent).

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/install.yml
```

**Installation Order:**
1. Docker (Lab2 only - for building Spark images)
2. NFS Server and Clients
3. Kubernetes Cluster (uses containerd runtime)
4. Observability Platform (GaryPC-WSL with Docker Desktop)
5. Spark on Kubernetes
6. Elastic Agent (host-level on Lab1, Lab2, GaryPC)

**Use Cases:**
- First-time setup on new hosts
- Re-installing components after system changes
- Ensuring all components are properly configured

### `start.yml` - Start All Services
Starts all services in the correct dependency order.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/start.yml
```

**Startup Order:**
1. NFS Server (Lab2)
2. Kubernetes Cluster (Lab2 master + Lab1/Lab2 workers)
3. Observability Platform (GaryPC-WSL)
4. Spark on Kubernetes (master, workers, history server)

**Prerequisites:**
- Docker on GaryPC must be manually started via Docker Desktop UI
- All components should be installed (run `install.yml` if needed)

**Use Cases:**
- Daily startup of the development environment
- Restart after system maintenance
- First-time startup on GaryPC WSL

### `status.yml` - Check All Services
Checks the status of all components.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/status.yml
```

**Checks:**
- Docker status (Lab2 only)
- Kubernetes cluster health
- Spark cluster status
- Elastic Agent status (host-level)
- Displays summary and next steps

**Use Cases:**
- Verify all services are running
- Troubleshoot startup issues
- Check system health

### `stop.yml` - Stop All Services
Gracefully stops all services in reverse dependency order.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/stop.yml
```

**Shutdown Order:**
1. Spark components
2. Observability Platform
3. Kubernetes Cluster
4. NFS Server

**Note:** Docker and Elastic Agent remain running. Use component-specific playbooks to stop them if needed.

**Use Cases:**
- System shutdown/maintenance
- Free up system resources
- Prepare for system updates

## Component-Specific Playbooks

For fine-grained control, use component-specific playbooks in subdirectories:

### Docker (`docker/`)
- `install.yml` - Install Docker on Lab2 (for image building only)
- `uninstall.yml` - Remove Docker
- `start.yml` - Start Docker service
- `stop.yml` - Stop Docker service
- `diagnose.yml` - Check Docker status and troubleshoot issues

> **Note:** Docker is only used on Lab2 for building custom Spark images. Kubernetes uses containerd as its container runtime.

### NFS (`nfs/`)
- `install.yml` - Install NFS server and configure clients (includes all exports and data setup)
- `uninstall.yml` - Remove NFS server and clients
- `start.yml` - Start NFS server
- `stop.yml` - Stop NFS server
- `status.yml` - Check NFS server and client status

### Kubernetes (`k8s/`)
- `install.yml` - Install Kubernetes cluster
- `uninstall.yml` - Remove Kubernetes cluster
- `start.yml` - Start Kubernetes services
- `stop.yml` - Stop Kubernetes services
- `status.yml` - Check cluster status
- `diagnose.yml` - Troubleshoot cluster issues
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
| **Lab1** | Kubernetes Worker, Monitoring | Kubernetes Worker (containerd), Elastic Agent (systemd) |
| **Lab2** | Kubernetes Master+Worker, NFS, Image Builds | Kubernetes Master+Worker (containerd), NFS Server, Elastic Agent (systemd), Docker (image builds only), JupyterHub |
| **GaryPC** | Windows Host | Elastic Agent (Windows service) |
| **GaryPC-WSL** | Observability Platform | Elasticsearch, Kibana, Grafana, Logstash (Docker Compose) |

### Service URLs

After startup, services are accessible at:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Kibana** | http://GaryPC.local:5601 | elastic / myElastic2025 |
| **Grafana** | http://GaryPC.local:3000 | admin / (check observability/.env) |
| **Elasticsearch** | https://GaryPC.local:9200 | elastic / myElastic2025 |
| **Spark History Server** | http://Lab2.local:31534 | (no auth) |
| **Spark Master UI** | http://Lab2.local:32290 | (no auth) |

> **Note:** JupyterHub will be added during Spark 4.0 migration with Python 3.11 support.

## Common Workflows

### First-Time Setup
```bash
cd ansible

# 1. Install all components
ansible-playbook -i inventory.yml playbooks/install.yml

# 2. Start all services
ansible-playbook -i inventory.yml playbooks/start.yml

# 3. Verify everything is running
ansible-playbook -i inventory.yml playbooks/status.yml
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

# Check status of all components
ansible-playbook -i inventory.yml playbooks/status.yml

# Check specific components
ansible-playbook -i inventory.yml playbooks/docker/status_docker.yml
ansible-playbook -i inventory.yml playbooks/k8s/diagnose_k8s.yml

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
- Verify SSH keys are set up: `ssh ansible@Lab1.local`
- Check inventory.yml has correct hostnames/IPs

**Docker not available on GaryPC:**
- Manually start Docker Desktop on Windows
- Verify with: `docker ps`

**Kubernetes pods not starting:**
- Check Kubernetes status: `kubectl get nodes`
- Check pod logs: `kubectl logs -n spark <pod-name>`
- Run diagnostics: `ansible-playbook -i inventory.yml playbooks/k8s/diagnose_k8s.yml`

**Observability services not accessible:**
- Check Docker containers: `docker ps`
- Check logs: `docker-compose logs` (in observability directory)
- Verify network connectivity: `ping GaryPC.local`

## Additional Resources

- [Project Overview](../../docs/PROJECT_OVERVIEW.md)
- [Running Ansible Playbooks](../../docs/RUNNING_ANSIBLE_PLAYBOOKS.md)
- [Kubernetes Management](k8s/README.md)
- [Spark Deployment](spark/README.md)
- [Observability Platform](observability/README.md)

