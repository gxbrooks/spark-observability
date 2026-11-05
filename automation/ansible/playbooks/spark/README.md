# Spark Playbooks for Elastic-on-Spark

This directory contains Ansible playbooks for deploying and managing Apache Spark on Kubernetes.

## Playbook Overview

The playbooks follow a verb-object naming convention for easier tab-completion:

* `deploy_spark.yml` - Deploys Spark components on Kubernetes (builds images, applies manifests)
* `start_spark.yml` - Starts Spark services (master, workers, history server)
* `stop_spark.yml` - Stops Spark services and removes pods
* `launch_ipython.yml` - Launches interactive PySpark IPython environment

## Usage

Run the playbooks using the standard Ansible command:

```bash
# Deploy Spark on Kubernetes
ansible-playbook -i ../../inventory.yml deploy_spark.yml

# Start Spark services
ansible-playbook -i ../../inventory.yml start_spark.yml

# Stop Spark services
ansible-playbook -i ../../inventory.yml stop_spark.yml

# Launch interactive PySpark environment
ansible-playbook -i ../../inventory.yml launch_ipython.yml
```

## Resource Allocation

See [`docs/architecture-and-resources.md`](../../../docs/architecture-and-resources.md) for the full project-wide resource plan. Key points for Spark:

### Hardware
- **Lab1 & Lab2**: 32 logical CPUs, 96 GB RAM each — **symmetric** worker nodes
- **Lab3**: 32 logical CPUs, 64 GB RAM — control plane, Spark Master, History Server, HDFS, NFS, Observability

### Per-Host Worker Allocation (Lab1 and Lab2, identical)

| Component | Replicas | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|----------|-------------|-----------|----------------|--------------|
| Spark Worker | 4 | 2 | 4 | 8 GiB | 14 GiB |
| **Total** | **4** | **8** | **16** | **32 GiB** | **56 GiB** |

### Worker Sizing

| Setting | Value | Rationale |
|---------|-------|-----------|
| `SPARK_WORKER_CORES` | 4 | Matches K8s CPU limit; prevents over-allocation |
| `SPARK_WORKER_MEMORY` | 12 g | Leaves ~2 GiB headroom within 14 GiB pod limit |
| Replicas per host | 4 | Symmetric; 8 total workers, 32 cores, 96 GiB Spark heap cluster-wide |

## Spark Components

### Spark Master
- **Type**: StatefulSet with headless service (pinned to Lab3)
- **Resources**: 1 CPU request / 2 limit, 2 GiB request / 4 GiB limit
- **Ports**: 7077 (Spark), 8080 (Web UI)
- **DNS**: `spark-master-0.spark-master-headless.spark.svc.cluster.local`

### Spark Workers
- **Type**: Deployment with node affinity
- **Distribution**: 4 workers on Lab1, 4 workers on Lab2 (symmetric)
- **Resources**: 2 CPU request / 4 limit, 8 GiB request / 14 GiB limit each
- **Ports**: 8081 (Web UI)

### Spark History Server
- **Type**: Deployment (pinned to Lab3)
- **Resources**: 1 CPU request / 2 limit, 2 GiB request / 4 GiB limit
- **Ports**: 18080 (Web UI)
- **Storage**: hostPath mount at `/mnt/spark/events`

## Workflow Guide

### Initial Deployment

1. **Deploy Spark components:**
   ```bash
   ansible-playbook -i ../../inventory.yml deploy_spark.yml
   ```

2. **Start Spark services:**
   ```bash
   ansible-playbook -i ../../inventory.yml start_spark.yml
   ```

3. **Verify deployment:**
   ```bash
   kubectl get pods -n spark
   kubectl get svc -n spark
   ```

### Interactive Development

Launch an interactive PySpark environment:

```bash
ansible-playbook -i ../../inventory.yml launch_ipython.yml
```

This creates a PySpark-enabled pod with IPython shell access.

### Monitoring and Troubleshooting

#### Check Spark Web UIs
- **Spark Master**: http://Lab3.lan:31471 (NodePort)
- **Spark History**: http://Lab3.lan:31534 (NodePort)
- **Worker UIs**: Access via `kubectl port-forward`

#### Common Commands
```bash
# Check pod status
kubectl get pods -n spark -o wide

# Check resource usage
kubectl top pods -n spark

# View logs
kubectl logs -n spark <pod-name>

# Check worker distribution
kubectl get pods -n spark -o wide | grep worker
```

## Configuration

### Environment Variables
Spark configuration is managed through the `spark-configmap` ConfigMap, which is generated from `vars/variables.yaml` by `vars/generate_env.py`.

### Node Affinity
Workers are distributed using node affinity rules:
- **Lab1 workers**: Scheduled on `Lab1.lan`
- **Lab2 workers**: Scheduled on `Lab2.lan`

### Storage
- **Spark Events**: NFS mount at `/mnt/spark/events` (shared across all nodes)
- **Worker Storage**: Local hostPath volumes for temporary data

## Troubleshooting

### Common Issues

1. **Workers not starting**: Check node affinity and resource availability
2. **Memory issues**: Verify resource limits and node capacity
3. **Network issues**: Check DNS resolution and service connectivity
4. **Storage issues**: Verify NFS mount accessibility

### Diagnostic Commands

```bash
# Check resource allocation
kubectl describe nodes

# Check pod resource usage
kubectl top pods -n spark

# Check worker distribution
kubectl get pods -n spark -o wide | grep worker

# Check Spark master connectivity
kubectl exec -n spark spark-master-0 -- ./check-spark-health.sh all
```

### Performance Tuning

- **Memory**: Adjust worker memory limits based on workload
- **CPU**: Monitor CPU utilization and adjust limits if needed
- **Storage**: Ensure NFS mount has sufficient space and performance
- **Network**: Verify DNS resolution and service connectivity
