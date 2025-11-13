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

### Hardware Specifications
- **Lab1 & Lab2**: 16 cores (32 threads), 96GB RAM each
- **Total Cluster**: 32 cores (64 threads), 192GB RAM
- **Swap**: Disabled (Kubernetes requirement)

### Lab1 Resource Allocation (Dedicated Worker Node)

| **Component** | **Replicas** | **CPU Request** | **CPU Limit** | **Memory Request** | **Memory Limit** |
|------------|-----------------|-----------------|---------------|-------------------|------------------|
| **Spark Workers** | 5 | 2 cores each | 4 cores each | 8Gi each | 14Gi each |
| **Kubernetes System** | ~7 pods | ~1 core | ~2 cores | ~2Gi | ~4Gi |
| **SUBTOTAL - Lab1** | **~7** | **11-22 cores** | **18-36 cores** | **42-84Gi** | **74Gi** |

### Lab2 Resource Allocation (Control Plane + Workers)

| **Component** | **Replicas** | **CPU Request** | **CPU Limit** | **Memory Request** | **Memory Limit** |
|------------|-----------------|-----------------|---------------|-------------------|------------------|
| **Spark Master** | 1 | 1 core | 2 cores | 2Gi | 4Gi |
| **Spark History** | 1 | 1 core | 2 cores | 2Gi | 4Gi |
| **Spark Workers** | 2 | 2 cores each | 4 cores each | 8Gi each | 14Gi each |
| **Kubernetes System** | ~8 pods | ~2 cores | ~4 cores | ~4Gi | ~8Gi |
| **SUBTOTAL - Lab2** | **~12** | **8-16 cores** | **12-24 cores** | **16-32Gi** | **24-48Gi** |

### Resource Allocation Rationale

#### **Memory Allocation Strategy**
- **Lab1**: 74Gi allocated (77% of 96Gi) with 22Gi system reserve
- **Lab2**: 48Gi allocated (50% of 96Gi) with 48Gi system reserve
- **System Reserve**: Includes OS kernel (~2-4Gi), file cache (~8-16Gi), system processes (~2-4Gi), and OOM buffer (~4-8Gi)

#### **CPU Allocation Strategy**
- **Lab1**: 18-36 cores (113-225% of 16 cores) - CPU overcommitment acceptable for worker node
- **Lab2**: 12-24 cores (75-150% of 16 cores) - CPU overcommitment acceptable with control plane priority
- **Kubernetes**: Can handle CPU overcommitment through proper scheduling and throttling

#### **Worker Distribution**
- **Lab1**: 5 workers (dedicated worker node for maximum parallelism)
- **Lab2**: 2 workers (control plane priority with some worker capacity)
- **Total**: 7 Spark workers for good task distribution

#### **Spark Worker Core Configuration**
Each worker is configured with `SPARK_WORKER_CORES=4` to match the Kubernetes CPU limit of 4 cores. This ensures Spark respects the K8s resource constraints and prevents workers from over-allocating cores based on host CPU count.

#### **Safety Considerations**
- **Memory Safety**: All allocations within available RAM limits
- **OOM Prevention**: Adequate headroom prevents memory pressure
- **I/O Performance**: Sufficient file cache memory for good I/O performance
- **System Stability**: Reserved memory for OS and system processes

## Spark Components

### Spark Master
- **Type**: StatefulSet with headless service
- **Resources**: 1-2 cores, 2-4Gi memory
- **Ports**: 7077 (Spark), 8080 (Web UI)
- **DNS**: `spark-master-0.spark-master-headless.spark.svc.cluster.local`

### Spark Workers
- **Type**: Deployment with node affinity
- **Distribution**: 5 workers on Lab1, 2 workers on Lab2
- **Resources**: 2-4 cores, 8-14Gi memory each
- **Ports**: 8081 (Web UI)

### Spark History Server
- **Type**: Deployment
- **Resources**: 1-2 cores, 2-4Gi memory
- **Ports**: 18080 (Web UI)
- **Storage**: NFS mount at `/mnt/spark/events`

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
- **Spark Master**: http://Lab2.local:31471 (NodePort)
- **Spark History**: http://Lab2.local:31534 (NodePort)
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
Spark configuration is managed through the `spark-configmap` ConfigMap, which is generated from `variables.yaml` by `linux/generate_env.py`.

### Node Affinity
Workers are distributed using node affinity rules:
- **Lab1 workers**: Scheduled on `Lab1.local`
- **Lab2 workers**: Scheduled on `Lab2.local`

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
