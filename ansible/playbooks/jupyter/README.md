# JupyterHub Playbooks for Spark Development

This directory contains Ansible playbooks for deploying and managing JupyterHub on Kubernetes for interactive Spark development.

## Overview

JupyterHub provides a web-based notebook environment with PySpark pre-configured, allowing for interactive Spark development accessible from any browser.

## Playbooks

### `deploy_jupyter.yml` - Deploy JupyterHub

Deploys JupyterHub on Kubernetes with PySpark integration.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/jupyter/deploy_jupyter.yml
```

**What it does:**
- Deploys JupyterHub pod on Lab2 (pinned via node affinity)
- Configures PySpark with connection to Spark cluster
- Mounts NFS storage for notebooks, data access, and event logs
- Exposes JupyterHub via NodePort (32080)

**Prerequisites:**
- Kubernetes cluster running
- Spark deployed and running (`deploy_spark.yml`)
- NFS mounts configured on cluster nodes

### `start_jupyter.yml` - Start JupyterHub

Starts the JupyterHub service by scaling the deployment to 1 replica.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/jupyter/start_jupyter.yml
```

### `stop_jupyter.yml` - Stop JupyterHub

Stops JupyterHub by scaling the deployment to 0 replicas.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/jupyter/stop_jupyter.yml
```

### `status_jupyter.yml` - Check Status

Checks the status of JupyterHub deployment, pods, and service.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/jupyter/status_jupyter.yml
```

## Access JupyterHub

Once deployed, JupyterHub is accessible at:
- **URL**: https://Lab2.lan:32443 (HTTPS with self-signed certificate)
- **Authentication**: NativeAuthenticator (sign up + admin approval)
- **Python Version**: 3.11 (compatible with PySpark 3.5.1)
- **Certificate**: Self-signed (accept browser warning for internal use)

### Authentication Model

**Current Setup: Single-User Development Mode**
- Single user: `jovyan` 
- No authentication token required
- Suitable for: Development, testing, trusted networks
- NOT suitable for: Production, multi-user environments

**For Production**: See "Multi-User Setup" section below for JupyterHub deployment with authentication

## Features

### PySpark Integration

JupyterHub comes pre-configured with:
- PySpark kernel connected to Spark cluster
- Spark master: `spark://spark-master-0.spark-master-headless.spark.svc.cluster.local:7077`
- Spark configuration from `spark-defaults.conf`
- Environment variables from `spark-configmap`

### Storage Access

Notebooks have access to:
- `/mnt/spark/data` - Shared data directory (read-only)
- `/mnt/spark/events` - Spark event logs (read-only)
- `/home/jovyan/work` - Notebook workspace (persisted to `/mnt/spark/jupyter/notebooks`)

### Resource Allocation

- **CPU**: 1-2 cores (request-limit)
- **Memory**: 2-4 Gi (request-limit)
- **Node**: Lab2 (via node affinity)

## Usage Examples

### Creating a PySpark Notebook

1. Access JupyterHub at http://Lab2.lan:32080
2. Create a new notebook (Python 3)
3. Use PySpark:

```python
from pyspark.sql import SparkSession

# SparkSession is pre-configured via environment
spark = SparkSession.builder \
    .appName("JupyterNotebook") \
    .master("spark://spark-master-0.spark-master-headless.spark.svc.cluster.local:7077") \
    .getOrCreate()

# Test the connection
df = spark.range(1000)
df.count()

# Read data from NFS
data = spark.read.csv("/mnt/spark/data/your-data.csv", header=True)
data.show(10)
```

### Monitoring Spark Jobs

Jobs submitted from JupyterHub are visible in:
- **Spark Master UI**: http://Lab2.lan:32636
- **Spark History Server**: http://Lab2.lan:31534
- **Kibana**: http://GaryPC.lan:5601 (observability)

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -n spark -l app=jupyterhub

# Check pod events
kubectl describe pod -l app=jupyterhub -n spark

# View logs
kubectl logs -n spark -l app=jupyterhub
```

### Cannot Access JupyterHub

1. Verify pod is running: `kubectl get pods -n spark -l app=jupyterhub`
2. Check service: `kubectl get svc jupyterhub -n spark`
3. Verify NodePort: Should be `32080`
4. Test network: `curl http://Lab2.lan:32080`

### PySpark Not Connecting to Cluster

1. Verify Spark master is running: `kubectl get pods -n spark -l app=spark-master`
2. Check Spark master service: `kubectl get svc spark-master-headless -n spark`
3. Test DNS resolution from JupyterHub pod:
   ```bash
   kubectl exec -n spark -l app=jupyterhub -- nslookup spark-master-0.spark-master-headless.spark.svc.cluster.local
   ```

### Storage Access Issues

1. Verify NFS mounts on Lab2:
   ```bash
   ssh ansible@Lab2.lan
   ls -la /mnt/spark/data
   ls -la /mnt/spark/events
   ls -la /mnt/spark/jupyter
   ```

2. Check permissions:
   ```bash
   # Should be accessible by uid 1000 (jovyan user in container)
   ```

## Architecture

### Deployment Pattern

JupyterHub follows the same Kubernetes deployment pattern as Spark History Server:
- Deployment with 1 replica
- Node affinity to Lab2
- hostPath volumes for NFS-backed storage
- ConfigMap for Spark configuration
- NodePort service for external access

### Integration with Spark

```
JupyterHub (Lab2:32080)
    ↓
Spark Master (spark-master-headless:7077)
    ↓
Spark Workers (Lab1: 5 workers, Lab2: 2 workers)
    ↓
Event Logs → /mnt/spark/events
    ↓
Spark History Server (Lab2:31534)
    ↓
Observability Stack (GaryPC-WSL)
```

## Maintenance

### Updating JupyterHub Configuration

1. Edit the deployment template: `ansible/roles/spark/templates/jupyterhub-deployment.yaml.j2`
2. Redeploy: `ansible-playbook -i inventory.yml playbooks/jupyter/deploy_jupyter.yml`

### Updating Spark Configuration

Spark configuration is managed via ConfigMap:
```bash
# Update spark-defaults.conf
# Then recreate ConfigMap
kubectl create configmap spark-defaults-conf \
  --from-file=/home/ansible/spark/conf/spark-defaults.conf \
  -n spark --dry-run=client -o yaml | kubectl apply -f -

# Restart JupyterHub to pick up changes
ansible-playbook -i inventory.yml playbooks/jupyter/stop_jupyter.yml
ansible-playbook -i inventory.yml playbooks/jupyter/start_jupyter.yml
```

## Multi-User Setup

The current deployment is a **single-user Jupyter Notebook** suitable for development. For production multi-user environments, consider deploying **full JupyterHub**:

### Option 1: Full JupyterHub with Kubernetes (Recommended for Production)

Deploy JupyterHub via Helm chart for true multi-user support:

```bash
# Add JupyterHub Helm repo
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update

# Create configuration
cat > jupyterhub-values.yaml <<EOF
hub:
  image:
    name: jupyterhub/k8s-hub
    tag: latest

auth:
  type: dummy  # Change to oauth2, ldap, etc. for production
  admin:
    users:
      - admin

singleuser:
  image:
    name: jupyter/pyspark-notebook
    tag: latest
  cpu:
    limit: 2
    guarantee: 1
  memory:
    limit: 4G
    guarantee: 2G
  storage:
    type: dynamic
    capacity: 10Gi
    
  extraEnv:
    SPARK_MASTER: "spark://spark-master-0.spark-master-headless.spark.svc.cluster.local:7077"

prePuller:
  hook:
    enabled: true
EOF

# Deploy JupyterHub
helm install jupyterhub jupyterhub/jupyterhub \
  --namespace spark \
  --values jupyterhub-values.yaml
```

**Features**:
- User authentication (OAuth, LDAP, PAM, etc.)
- Per-user notebook servers
- Resource quotas per user
- User isolation
- Admin panel

### Option 2: Add Token Authentication to Current Setup

For small teams using the current single-user setup, add basic security:

1. Generate a token:
```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

2. Update deployment to use token:
```yaml
# In jupyterhub-deployment.yaml.j2
--NotebookApp.token='your-generated-token'
```

3. Access with token:
```
http://Lab2.lan:32080/?token=your-generated-token
```

### Authentication Comparison

| Feature | Current (Single-User) | Full JupyterHub |
|---------|----------------------|-----------------|
| Users | 1 (jovyan) | Unlimited |
| Authentication | None | OAuth/LDAP/PAM |
| Per-user resources | No | Yes |
| User isolation | No | Yes |
| Admin panel | No | Yes |
| Complexity | Low | Medium |
| Use case | Dev/Testing | Production |

## Python Version Compatibility

**Current Python**: 3.11.6 (from jupyter/pyspark-notebook:latest)
**Spark Version**: 3.5.1
**Compatibility**: ✓ Spark 4.0+ requires Python 3.11 or later

The Python 3.11 environment is required for Spark 4.0+. For Spark 3.5.1, Python 3.8-3.11 was supported, but Spark 4.0+ requires 3.11+.

1. Use an older Jupyter image:
```yaml
image: "jupyter/pyspark-notebook:python-3.8"
```

2. Or build a custom image with Python 3.8

**Recommendation**: Keep Python 3.11 - it's officially supported and provides latest features.

## Best Practices

1. **Save Work Regularly**: Notebooks are persisted but save frequently
2. **Resource Management**: Close unused notebooks to free resources
3. **Long-Running Jobs**: Consider using batch mode for very long jobs
4. **Data Access**: Use NFS-mounted data directories for shared data
5. **Version Control**: Consider pushing notebooks to Git for version control
6. **Security**: For production, implement proper authentication (see Multi-User Setup)
7. **Monitoring**: Use Spark UI and History Server to monitor job execution

## Integration with Global Playbooks

JupyterHub is integrated into the global orchestration playbooks:
- `playbooks/install.yml` - Deploys JupyterHub after Spark
- `playbooks/start.yml` - Starts JupyterHub with other services
- `playbooks/diagnose.yml` - Full platform diagnostics (includes Spark/K8s paths used by Jupyter)
- `playbooks/stop.yml` - Stops JupyterHub with other services

## Additional Resources

- [Jupyter Docker Stacks Documentation](https://jupyter-docker-stacks.readthedocs.io/)
- [PySpark Documentation](https://spark.apache.org/docs/latest/api/python/)
- [Project Overview](../../docs/PROJECT_OVERVIEW.md)
- [Spark Playbooks](../spark/README.md)

