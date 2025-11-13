# Elastic-on-Spark Project Overview

This document provides a comprehensive overview of the Elastic-on-Spark project, including setup, usage, and architecture.

## Project Description

Use Elasticsearch to monitor and observe Spark applications running on Kubernetes with comprehensive observability stack integration.

## Setup

### Prerequisites
- Ansible installed on the control machine
- SSH access to target servers
- Python 3.11 (for Spark 4.0.1 compatibility)

### Spark Environment Setup

1. Set up NFS for Spark event logs:
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/nfs/install_nfs.yml
```

2. Set up Kubernetes:
```bash
# Use the simplified k8s playbooks for installation and management
ansible-playbook -i ansible/inventory.yml ansible/playbooks/k8s/install_k8s.yml
ansible-playbook -i ansible/inventory.yml ansible/playbooks/k8s/start_k8s.yml
```

3. Certificate Management (after hostname/network changes):
```bash
# Navigate to ansible directory first
cd ansible
# Regenerate certificates with the new hostnames
ansible-playbook -i inventory.yml playbooks/k8s/regenerate_k8s_certs.yml
# Update kubeconfig files with the new certificates
ansible-playbook -i inventory.yml playbooks/k8s/install_k8s.yml --tags=kubeconfig
```

4. Deploy Spark on Kubernetes securely:
```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/spark/deploy_spark.yml
```

> **Important:** Always run Ansible playbooks from within the `ansible` directory to ensure that `ansible.cfg` is properly loaded. See [Running Ansible Playbooks](RUNNING_ANSIBLE_PLAYBOOKS.md) for details.

> **Security Note:** This deployment implements robust certificate management with proper TLS validation.
> - All insecure TLS verification flags have been removed for production-grade security
> - Certificate regeneration is fully automated when hostnames or network configurations change
> - Comprehensive certificate validation ensures proper TLS security throughout the stack
> For detailed information about the secure deployment, see [Secure Spark Deployment Guide](SECURE_SPARK_DEPLOYMENT.md).

### Managing Spark

The Spark environment can be managed with the following commands:

#### Starting Spark
```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/spark/start_spark.yml
```

#### Interactive Development with PySpark

##### Client-Mode iPython (Terminal-Based)

For quick tests and command-line development on Lab2:

```bash
# SSH to Lab2
ssh ansible@Lab2.local

# Navigate to project
cd /home/gxbrooks/repos/elastic-on-spark

# Activate venv and launch iPython
source venv/bin/activate
./spark/ispark/launch_ipython.sh
```

**Features:**
- Fast startup
- Terminal-based
- Good for quick tests and automation
- Runs in client mode (connects to Spark cluster)

**Use for:**
- Interactive Spark development
- Quick debugging or testing
- Scripting and automation
- All current Spark 3.5.1 work

> **Note on JupyterHub:** Multi-user JupyterHub support is available with Spark 4.0.1 and Python 3.11 compatibility.

#### Stopping Spark
```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/spark/stop_spark.yml
```

#### Restarting Spark
```bash
# Restart all components
cd ansible
ansible-playbook -i inventory.yml playbooks/spark/start_spark.yml -e "restart=true"

# Restart specific component
cd ansible
ansible-playbook -i inventory.yml playbooks/spark/start_spark.yml -e "spark_component=master restart=true"
```

#### Environment Configuration Generation
The system automatically generates configuration files from `variables.yaml` as needed. The modification time-based generation mechanism compares the modification time of the source `variables.yaml` file with that of the generated files to determine if regeneration is necessary.

Generated configuration files include:
- `observability/.env` - Environment variables for Docker Compose
- `spark/spark-image.toml` - Configuration for Spark image builds
- `ansible/roles/spark/files/k8s/spark-configmap.yaml` - Kubernetes ConfigMap for Spark runtime (auto-generated)

These files are only regenerated when:
1. The source `variables.yaml` file has been modified more recently than the generated files
2. The target files don't exist
3. Force regeneration is explicitly requested

> **Important:** If you modify `variables.yaml`, always regenerate the configuration files before running Ansible playbooks.

To force regeneration of these files, use the `force_env_generation` parameter:

```bash
cd ansible
# Force environment configuration regeneration
ansible-playbook -i inventory.yml playbooks/spark/deploy_spark.yml -e "force_env_generation=true"
```

You can also manually generate configuration files by running the script directly:

```bash
# Generate all configuration files
python3 linux/generate_env.py

# Generate specific context files
python3 linux/generate_env.py observability spark-runtime

# Force regeneration
python3 linux/generate_env.py -f

# Get verbose output
python3 linux/generate_env.py -v
```

### Spark History Server

The Spark History Server provides a web UI for monitoring and debugging Spark applications after they've completed.

#### Direct Deployment

For secure deployment of the Spark History Server:

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/spark/deploy_spark.yml
```

This playbook:
1. Sets up proper Kubernetes certificate management
2. Builds and securely distributes the Spark Docker image
3. Deploys the History Server to Kubernetes with proper security settings
4. Provides detailed status and troubleshooting information

#### Accessing the History Server UI

Once deployed, the History Server UI should be accessible at:
- http://localhost:31534 (via NodePort)

If you can't access the NodePort, the script also offers port-forwarding as an alternative:
```bash
kubectl port-forward -n spark service/spark-history 18080:18080
```
Then access: http://localhost:18080

#### Troubleshooting Common Issues

1. **TLS Certificate Verification Issues**
   - Error: `Unable to connect to the server: tls: failed to verify certificate`
   - Solutions:
     - Run the certificate distribution playbook: `ansible-playbook ansible/playbooks/k8s/distribute_k8s_certs.yml`
     - Manually set up certificates: `sudo ./spark/setup_k8s_certs.sh $(whoami)`
     - Check certificate paths and permissions (see docs/SECURE_SPARK_DEPLOYMENT.md)

2. **History Server Pod Not Starting**
   - Check pod status: `kubectl get pods -n spark`
   - View pod logs: `kubectl logs -n spark <pod-name>`
   - Check pod description: `kubectl describe pod -n spark <pod-name>`
   - If there's a "permission denied" error on ConfigMap files:
     ```bash
     # Regenerate environment files
     cd /home/gxbrooks/repos/elastic-on-spark
     python3 linux/generate_env.py -f
     
     # Then run the playbook from ansible directory
     cd ansible
     ansible-playbook playbooks/spark/start_spark.yml
     ```
   - For detailed troubleshooting steps, see the [Running Ansible Playbooks](RUNNING_ANSIBLE_PLAYBOOKS.md) guide

3. **NFS Mount Issues**
   - Ensure NFS server is running: `systemctl status nfs-server`
   - Check mount permissions: `ls -la /mnt/spark/events`
   - Verify NFS exports: `exportfs -v`

4. **Docker Image Build Issues**
   - Check Docker build logs
   - Verify all required build arguments are properly extracted from `spark-image.toml`
   - Ensure Docker has enough resources allocated

## Kubernetes Cluster Management

The project includes a set of Ansible playbooks for managing Kubernetes clusters with production-grade security:

```bash
# Initial setup: Install and set up Kubernetes
cd ansible
ansible-playbook -i inventory.yml playbooks/k8s/install_k8s.yml

# After hostname or network changes:
# 1. First regenerate certificates with current hostnames
ansible-playbook -i inventory.yml playbooks/k8s/regenerate_k8s_certs.yml
# 2. Then recreate kubeconfig files to use the new certificates
ansible-playbook -i inventory.yml playbooks/k8s/install_k8s.yml --tags=kubeconfig

# Check Kubernetes cluster status
ansible-playbook -i inventory.yml playbooks/k8s/status_k8s.yml

# Start/Stop Kubernetes services
ansible-playbook -i inventory.yml playbooks/k8s/start_k8s.yml
ansible-playbook -i inventory.yml playbooks/k8s/stop_k8s.yml

# Generate a new join token for worker nodes
ansible-playbook -i inventory.yml playbooks/k8s/create_join_token.yml
```

> **Security Note:** The Kubernetes configuration enforces strict TLS certificate validation. When hostnames or network configurations change, always run the playbooks in this exact order:
> 1. `regenerate_k8s_certs.yml` - Creates new certificates with the current hostnames (includes case-insensitive hostname matching)
> 2. `install_k8s.yml --tags=kubeconfig` - Creates kubeconfig files with the new certificates
> 3. `start_k8s.yml` - Restarts services with the new configuration
>
> The playbooks automatically handle hostname case sensitivity by including both original and lowercase variants of all hostnames in the certificates.

See [ansible/playbooks/k8s/README.md](../ansible/playbooks/k8s/README.md) for detailed documentation on Kubernetes management.
