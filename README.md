# elastic-on-spark
Use Elasticsearch to monitor and observe Spark

## Setup

### Prerequisites
- Ansible installed on the control machine
- SSH access to target servers
- Python 3.x

### Spark Environment Setup

1. Set up NFS for Spark event logs:
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/nfs/install_nfs.yml
```

2. Set up Kubernetes:
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/k8s/setup_kubernetes.yml
ansible-playbook -i ansible/inventory.yml ansible/playbooks/k8s/init_kubernetes_cluster.yml
ansible-playbook -i ansible/inventory.yml ansible/playbooks/k8s/setup_k8s_permissions.yml
```

3. Distribute Kubernetes certificates securely:
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/k8s/distribute_k8s_certs.yml
```

4. Deploy Spark on Kubernetes securely:
```bash
./deploy_spark.sh
```

Or run the Ansible playbook directly:
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/spark/deploy_spark.yml
```

> **Note:** The deployment uses secure certificate management and doesn't rely on insecure TLS flags.
> For detailed information about the secure deployment, see [Secure Spark Deployment Guide](docs/SECURE_SPARK_DEPLOYMENT.md).

### Managing Spark

The Spark environment can be managed with the following commands:

#### Starting Spark
```bash
# Start all components
ansible-playbook -i ansible/inventory.yml ansible/playbooks/spark/start_spark.yml
```

#### Interactive Development with PySpark
To launch an interactive PySpark IPython shell for development and data exploration:

```bash
# Quick and easy method (launches in current terminal)
./linux/launch_ipython.sh

# OR using the Ansible playbook directly (will launch its own interactive shell)
ansible-playbook -i ansible/inventory.yml ansible/playbooks/spark/launch_ipython.yml

# Create pod without launching interactive shell
ansible-playbook -i ansible/inventory.yml ansible/playbooks/spark/launch_ipython.yml -e "launch_shell=false allow_interactive_param=false"
```

> **Note:** Use either the shell script OR the Ansible playbook with interactive mode, but not both together. The shell script already handles pod creation before launching the interactive shell.

The interactive shell provides:
- A full PySpark environment with SparkSession pre-configured
- Event logging to the NFS-mounted `/mnt/spark-events` directory
- GC logs written to `/opt/spark/logs/gc.log`
- Local mode execution (`--master local[*]`) for development

When done with the interactive session:
```bash
# Clean up the pod when finished
kubectl delete pod pyspark-ipython -n spark
```

#### Restarting Spark
```bash
# Restart all components
ansible-playbook -i ansible/inventory.yml ansible/playbooks/spark/start_spark.yml -e "restart=true"

# Restart specific component
ansible-playbook -i ansible/inventory.yml ansible/playbooks/spark/start_spark.yml -e "spark_component=master restart=true"
```

#### Environment Configuration Generation
The system automatically generates configuration files from `variables.yaml` as needed. The modification time-based generation mechanism compares the modification time of the source `variables.yaml` file with that of the generated files to determine if regeneration is necessary.

Generated configuration files include:
- `docker/.env` - Environment variables for Docker Compose
- `spark/spark-image.toml` - Configuration for Spark image builds
- `spark/k8s/spark-configmap.yaml` - Kubernetes ConfigMap for Spark runtime

These files are only regenerated when:
1. The source `variables.yaml` file has been modified more recently than the generated files
2. The target files don't exist
3. Force regeneration is explicitly requested

To force regeneration of these files, use the `force_env_generation` parameter:

```bash
# Force environment configuration regeneration
ansible-playbook -i ansible/inventory.yml ansible/playbooks/spark/deploy_spark.yml -e "force_env_generation=true"
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

#### Stopping Spark
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/spark/stop_spark.yml
```

### Spark History Server

The Spark History Server provides a web UI for monitoring and debugging Spark applications after they've completed.

#### Direct Deployment

For secure deployment of the Spark History Server, use the deployment script:

```bash
# Run the secure deployment script
./deploy_secure_spark.sh
```

This script:
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

3. **NFS Mount Issues**
   - Ensure NFS server is running: `systemctl status nfs-server`
   - Check mount permissions: `ls -la /mnt/spark-events`
   - Verify NFS exports: `exportfs -v`

4. **Docker Image Build Issues**
   - Check Docker build logs
   - Verify all required build arguments are properly extracted from `spark-image.toml`
   - Ensure Docker has enough resources allocated
