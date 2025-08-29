# Ansible Support Scripts

This directory contains utility scripts to support the Ansible deployment and operations.

## Available Scripts

### diagnostics_docker_k8s.sh

A diagnostic tool for Docker and Kubernetes integration issues. It helps troubleshoot common problems with:

- Docker service status
- Docker registry availability and content
- Spark image availability
- Kubernetes pod and service status
- Image pull issues
- Kubernetes node status
- Registry configuration

**Usage:**
```bash
./diagnostics_docker_k8s.sh
```

Run this script when:
- Pods are stuck in ImagePullBackOff state
- Deployments fail to start
- Registry connectivity issues occur
- Docker image building problems arise

The script provides a comprehensive overview of the system state to help diagnose and resolve issues quickly.
