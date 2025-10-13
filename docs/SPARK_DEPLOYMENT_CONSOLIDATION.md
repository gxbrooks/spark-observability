# Spark Deployment Consolidation

This document describes the consolidation of multiple Spark deployment approaches into a single, secure Ansible-based approach.

## Overview

The elastic-on-spark project previously contained multiple approaches for deploying Spark on Kubernetes. This has been consolidated into a single, secure deployment method using Ansible roles and playbooks.

## Deployment Structure

- Primary deployment playbook: `ansible/playbooks/spark/deploy_spark.yml`
- Certificate management: `ansible/roles/k8s_certs`
- Spark deployment: `ansible/roles/spark`
- Interactive development: `ansible/roles/spark_ipython`
  - Playbook: `ansible/playbooks/spark/launch_ipython.yml`

## Deployment Process

1. Check prerequisites:
   - Running on Kubernetes control node
   - NFS mounts available

2. Certificate distribution:
   - Managed by `k8s_certs` role
   - Sets appropriate permissions for Kubernetes certificates

3. Spark deployment:
   - Templates deployment manifests
   - Applies Kubernetes manifests for Spark components

## NFS Requirements

The Spark deployment requires an NFS server with the following mount points:

1. `/mnt/spark/events` - Used for Spark event logging and history server
   - This mount must be accessible on all Kubernetes nodes
   - The mount is used by Spark master, workers, history server, and the PySpark IPython pod
   - Permissions should be set to 777 to allow all components to write event logs

You can set up the NFS server and mounts using the provided playbook:

```bash
ansible-playbook -i inventory.yml playbooks/nfs/install_nfs.yml
```

This playbook:
- Installs the NFS server on the designated NFS server nodes
- Creates the `/srv/nfs/spark/events` export directory
- Configures all Kubernetes nodes to mount this directory at `/mnt/spark/events`

All Spark components reference this shared directory through hostPath volumes in their Kubernetes manifests.

## Best Practices

- Role dependencies manage component relationships
- Templates are stored in role-specific template directories
- Variables are defined in role defaults
- Roles are stored in the standard `ansible/roles/` directory
- Roles are referenced by their simple name in playbooks (e.g., `name: spark`)
- ansible.cfg contains a single, clear roles_path setting

## Interactive Development Environment

An Ansible playbook has been created to launch PySpark with IPython:

```bash
ansible-playbook playbooks/spark/launch_ipython.yml
```

This playbook:
- Creates a pod with the Spark image
- Sets up required directories and permissions
- Launches an IPython shell with PySpark configured in local mode
- Uses the centralized variable system for configuration

### Convenient Launch Script

For quick access to an interactive PySpark IPython shell, a convenience script is also available:

```bash
./linux/launch_ipython.sh
```

This script:
- Creates a PySpark IPython pod if it doesn't exist
- Launches an interactive IPython shell with PySpark configured in the current terminal
- Configures GC logs to be written to standard log files in `/opt/spark/logs`
- Uses the shared NFS mount for event logging
- Provides clear instructions for cleanup when the session is done

The script is ideal for data exploration and interactive development without having to remember Kubernetes and PySpark configuration details.

### Implementation Details

The implementation follows Ansible best practices:

1. **Templating and Configuration**:
   - Uses the same environment variables from `spark-configmap.yaml` that are generated from `variables.yaml`
   - Inherits Spark image settings from the main deployment
   - Uses a Jinja2 template for pod configuration in `ansible/roles/spark_ipython/templates/spark-ipython-pod.yml.j2`

2. **Resource Management**:
   - Configurable pod resources through variables
   - Default resources set to sensible values (500m CPU request, 1 CPU limit, etc.)
   - Automatically creates required directories:
     - `/opt/spark/logs` for JVM logs
     - `/mnt/spark/events` for Spark event logs

3. **Local Mode Configuration**:
   - Configures PySpark to run in local mode (`--master local[*]`) to avoid Spark master connectivity issues
   - Uses the shared NFS-mounted `/mnt/spark/events` directory for event logging
   - Verifies NFS mount is properly configured before launching the pod
   - Uses JVM logging configuration to aid in debugging

4. **Usage Options**:
   - Interactive shell mode (default): `ansible-playbook playbooks/spark/launch_ipython.yml`
   - Non-interactive pod creation: `ansible-playbook playbooks/spark/launch_ipython.yml -e "launch_shell=false"`
   - Custom resources: `ansible-playbook playbooks/spark/launch_ipython.yml -e "pyspark_ipython_memory_limit=4Gi"`
   - Can be customized with additional parameters for resources

## Removed/Consolidated Scripts

The following scripts/files have been consolidated or removed:
- Redundant certificate management scripts
- Multiple deployment approaches
- Direct application of Kubernetes manifests
- Shell scripts for PySpark/IPython integration (`launch_pyspark_ipython.sh`)

These have been replaced by the structured Ansible roles and playbooks.

## Development Tools

The consolidation includes tools for development and troubleshooting:

1. **IPython for Interactive Spark Development**
   - Playbook: `ansible/playbooks/spark/launch_ipython.yml`
   - Role: `ansible/roles/spark_ipython`
   - Provides interactive PySpark development environment

2. **Diagnostic Tools**
   - Script: `ansible/scripts/diagnostics_docker_k8s.sh`
   - Checks Docker/Kubernetes configuration and troubleshoots common issues
