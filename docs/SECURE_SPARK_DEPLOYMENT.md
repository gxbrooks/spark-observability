# Secure Spark on Kubernetes Deployment Guide

This guide explains how to deploy Apache Spark on Kubernetes securely, ensuring all communications use SSL certificates and Docker images are properly managed.

## Overview

The deployment solution addresses two key security concerns:

1. **Secure Kubernetes Certificate Management**
   - Proper certificate-based authentication between clients and Kubernetes API
   - No insecure TLS verification skipping
   - Proper certificate distribution between development and runtime environments

2. **Secure Docker Image Management**
   - Local Docker registry for image distribution
   - Consistent image versioning and deployment
   - No insecure image pull policies

## Prerequisites

- A running Kubernetes cluster
- NFS mount at `/mnt/spark-events` for Spark History Server
- Proper network connectivity between all components

## Deployment Instructions

### Using Ansible (Recommended)

Run the secure deployment wrapper script:

```bash
./deploy_spark.sh
```

Alternatively, you can run the Ansible playbook directly:

```bash
cd /home/gxbrooks/repos/elastic-on-spark
ansible-playbook ansible/playbooks/spark/deploy_spark.yml
```

This will:
1. Configure secure Kubernetes certificates
2. Build and publish the Spark Docker image
3. Deploy all Spark components with proper security settings

### (Deprecated) Manual Scripts

The following manual scripts have been deprecated in favor of the Ansible-based approach:
   ```bash
   /home/gxbrooks/repos/elastic-on-spark/spark/deploy_spark_secure.sh
   ```

## Certificate Management Details

The solution uses the following approach for certificate management:

1. The Kubernetes CA certificate from `/etc/kubernetes/pki/ca.crt` is copied to user home directories
2. Each user gets a properly configured kubeconfig that references the local CA certificate
3. Certificate validation is properly enabled - no insecure flags
4. Group permissions ensure both development and runtime users have access

## Docker Image Management Details

The Docker image management strategy:

1. A local registry runs on port 5000
2. Images are built with consistent versioning based on source code checksums
3. Images are tagged and pushed to the local registry
4. Kubernetes deployments use proper image pull policies (Always)

## Access the Spark UI

After deployment:

1. For the Spark History Server:
   ```bash
   kubectl port-forward -n spark svc/spark-history 18080:18080
   ```
   Then open http://localhost:18080 in your browser

2. For the Spark Master UI:
   ```bash
   kubectl port-forward -n spark svc/spark-master 8080:8080
   ```
   Then open http://localhost:8080 in your browser

## Troubleshooting

### Certificate Issues

If you encounter certificate problems:

1. Verify the CA certificate exists and matches:
   ```bash
   diff ~/.kube/certs/ca.crt /etc/kubernetes/pki/ca.crt
   ```

2. Validate kubeconfig is properly configured:
   ```bash
   kubectl config view
   ```

### Image Pull Issues

If pods are stuck in "ImagePullBackOff":

1. Verify the image exists in the local registry:
   ```bash
   curl -X GET http://localhost:5000/v2/spark/tags/list
   ```

2. Check the image pull policy in the deployment:
   ```bash
   kubectl get deployment -n spark spark-history -o yaml | grep imagePullPolicy
   ```

3. Ensure container runtime can access the registry:
   ```bash
   docker pull localhost:5000/spark:3.5.1
   ```
