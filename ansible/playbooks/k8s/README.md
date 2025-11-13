# Kubernetes Playbooks for Elastic-on-Spark

This directory contains Ansible playbooks for managing a Kubernetes cluster for Spark workloads.

## Playbook Overview

The playbooks follow a verb-object naming convention for easier tab-completion:

* `install_k8s.yml` - Installs and initializes a new Kubernetes cluster with CNI plugins and networking
* `start_k8s.yml` - Starts Kubernetes services, configures networking, and joins worker nodes
* `stop_k8s.yml` - Stops Kubernetes services
* `reset_k8s.yml` - Resets the Kubernetes cluster (destructive operation)
* `uninstall_k8s.yml` - Completely removes Kubernetes and restores system to original state
* `status_k8s.yml` - Quick status check (master node only) - "Is it running?"
* `diagnose_k8s.yml` - Comprehensive health diagnostics (all nodes) - "Why isn't it working?"

## Usage

Run the playbooks using the standard Ansible command:

```bash
# Initial Installation (First Time Setup)
ansible-playbook -i ../../inventory.yml install_k8s.yml

# Start Kubernetes services and join worker nodes
ansible-playbook -i ../../inventory.yml start_k8s.yml

# Quick status check (master node only)
ansible-playbook -i ../../inventory.yml status_k8s.yml

# Comprehensive diagnostics (all nodes)
ansible-playbook -i ../../inventory.yml diagnose_k8s.yml

# Stop Kubernetes services
ansible-playbook -i ../../inventory.yml stop_k8s.yml

# Reset Kubernetes cluster (destructive)
ansible-playbook -i ../../inventory.yml reset_k8s.yml

# Completely uninstall Kubernetes and restore system
ansible-playbook -i ../../inventory.yml uninstall_k8s.yml
```

## Workflow Guide

### Initial Setup (Fresh Installation)

For a fresh installation or after resetting Kubernetes:

1. **Install Kubernetes:**
   ```bash
   ansible-playbook -i ../../inventory.yml install_k8s.yml
   ```
   This will:
   - Install Kubernetes packages (kubelet, kubeadm, kubectl)
   - Install CNI plugins
   - Disable swap (required for Kubernetes)
   - Initialize the cluster with `kubeadm init`
   - Configure containerd and networking

2. **Start Kubernetes services and join worker nodes:**
   ```bash
   ansible-playbook -i ../../inventory.yml start_k8s.yml
   ```
   This will:
   - Start containerd and kubelet services
   - Configure network prerequisites (rp_filter, iptables, sysctl)
   - Install and configure Flannel CNI
   - Join worker nodes to the cluster
   - Assign Pod CIDRs to worker nodes

3. **Verify cluster health:**
   ```bash
   ansible-playbook -i ../../inventory.yml status_k8s.yml
   ansible-playbook -i ../../inventory.yml diagnose_k8s.yml
   ```

### Adding Worker Nodes

To add new worker nodes to an existing cluster:

1. **Update inventory.yml** with the new worker node details
2. **Run start_k8s.yml** on the new worker node:
   ```bash
   ansible-playbook -i ../../inventory.yml start_k8s.yml --limit <new-worker-node>
   ```
   This will automatically:
   - Install CNI plugins if missing
   - Configure networking prerequisites
   - Join the node to the cluster
   - Assign a Pod CIDR

### Network Configuration

The playbooks automatically configure network prerequisites for Kubernetes:

- **Swap Management**: Automatically disables swap (required for Kubernetes)
- **Kernel Modules**: Loads `br_netfilter` module for iptables bridge filtering
- **Sysctl Settings**: Configures `net.bridge.bridge-nf-call-iptables`, `net.bridge.bridge-nf-call-ip6tables`, and `net.ipv4.ip_forward`
- **rp_filter**: Disables reverse path filtering on network interfaces
- **iptables**: Sets FORWARD policy to ACCEPT for pod-to-Service connectivity

### CNI Plugin Management

The playbooks handle CNI plugin installation and configuration:

- **CNI Plugins**: Downloads and installs CNI plugins to `/opt/cni/bin/`
- **Flannel CNI**: Installs and configures Flannel for pod networking
- **Pod CIDR**: Automatically assigns Pod CIDRs to worker nodes
- **CNI Configuration**: Creates Flannel CNI configuration from ConfigMap

### Troubleshooting

If you encounter issues:

1. **Run diagnostics:**
   ```bash
   ansible-playbook -i ../../inventory.yml diagnose_k8s.yml
   ```

2. **Check cluster status:**
   ```bash
   ansible-playbook -i ../../inventory.yml status_k8s.yml
   ```

3. **Verify node connectivity:**
   ```bash
   kubectl get nodes -o wide
   kubectl get pods -A
   ```

4. **Check CNI status:**
   ```bash
   kubectl get pods -n kube-flannel
   ls -la /opt/cni/bin/
   ls -la /etc/cni/net.d/
   ```

## UFW Firewall Configuration

To enable UFW (Uncomplicated Firewall) with Kubernetes support:

### Prerequisites
- Kubernetes cluster is running and healthy
- Pod-to-Service connectivity is working
- CoreDNS is ready and functioning

### UFW Configuration

The playbooks can configure UFW to work with Kubernetes:

```bash
# Configure UFW for Kubernetes (when ready)
ansible-playbook -i ../../inventory.yml start_k8s.yml -e "ufw_enabled=true"
```

This will:
- Set `DEFAULT_FORWARD_POLICY="ACCEPT"` for pod-to-Service connectivity
- Add Kubernetes NAT rules for pod egress traffic
- Enable IP forwarding in UFW
- Configure firewall rules for Kubernetes ports (6443, 2379, 2380, 10250, etc.)
- Allow SSH and HTTP/HTTPS for NodePort services

### Testing UFW Configuration

Before enabling UFW, test connectivity:
```bash
# Test pod-to-Service connectivity
kubectl -n spark exec pod/test-dns -- sh -c 'nc -vz 10.96.0.1 443'
```

After enabling UFW, verify connectivity is maintained:
```bash
# Verify connectivity still works
kubectl -n spark exec pod/test-dns -- sh -c 'nc -vz 10.96.0.1 443'
```

### UFW Troubleshooting

If pod connectivity breaks after enabling UFW:

1. **Check UFW status:**
   ```bash
   sudo ufw status verbose
   ```

2. **Check UFW logs:**
   ```bash
   sudo tail -f /var/log/ufw.log
   ```

3. **Disable UFW temporarily:**
   ```bash
   sudo ufw disable
   ```

4. **Check iptables rules:**
   ```bash
   sudo iptables -L FORWARD -n -v
   sudo iptables -t nat -L POSTROUTING -n -v
   ```

## Playbook Capabilities

### install_k8s.yml
- Installs Kubernetes packages (kubelet, kubeadm, kubectl)
- Downloads and installs CNI plugins
- Disables swap (required for Kubernetes)
- Initializes cluster with `kubeadm init`
- Configures containerd runtime
- Sets up basic networking prerequisites

### start_k8s.yml
- Starts containerd and kubelet services
- Configures network prerequisites (rp_filter, iptables, sysctl)
- Detects and installs missing CNI plugins
- Installs and configures Flannel CNI
- Joins worker nodes to the cluster
- Assigns Pod CIDRs to worker nodes
- Handles UFW firewall configuration (optional)

### status_k8s.yml
- Quick status check (master node only)
- Checks kubelet service status
- Verifies Kubernetes API availability
- Shows node and pod status
- Fast "is it running?" check

### diagnose_k8s.yml
- Comprehensive health diagnostics (all nodes)
- Checks system requirements (memory, CPU, OS)
- Validates swap status, CNI plugins, Pod CIDR assignments
- Monitors Flannel pod status and network configuration
- Deep troubleshooting for "why isn't it working?" issues

### uninstall_k8s.yml
- Completely removes Kubernetes components
- Restores system to original state
- Re-enables swap if it was originally enabled
- Cleans up all configuration files and directories
- Removes package holds and dependencies

## Spark Deployment

After Kubernetes is running, use the Spark playbooks to deploy and start Spark:

```bash
# Deploy Spark on Kubernetes
ansible-playbook -i ../../inventory.yml ../spark/deploy_spark.yml

# Start Spark on Kubernetes
ansible-playbook -i ../../inventory.yml ../spark/start_spark.yml
```
