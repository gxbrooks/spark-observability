# Running Ansible Playbooks

This document provides instructions on how to run the Ansible playbooks for deploying Spark on Kubernetes.

## Prerequisites

- Ansible installed on your system
- kubectl installed and configured
- Access to the Kubernetes cluster

## Role Organization

Roles are stored in the `ansible/roles/` directory following Ansible best practices:

- `k8s_certs`: Manages Kubernetes certificate distribution
- `spark`: Handles Spark deployment on Kubernetes
- `spark_ipython`: Provides PySpark IPython integration for interactive development

All roles are referenced by their simple name (e.g., `name: spark`) as the `roles_path` is configured in ansible.cfg.

## Running the Spark Deployment Playbook

⚠️ **IMPORTANT**: All Ansible commands **MUST** be run from the `ansible` directory to ensure ansible.cfg is properly loaded and roles can be found.

Before running any playbooks, ensure your environment configuration files are up-to-date:

```bash
cd /home/gxbrooks/repos/elastic-on-spark
python3 linux/generate_env.py
```

Then run your playbooks from the ansible directory:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/ansible
ansible-playbook playbooks/spark/deploy_spark.yml
```

If needed, you can specify the inventory file explicitly:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/ansible
ansible-playbook -i inventory.yml playbooks/spark/deploy_spark.yml
```

Running from any other directory will cause errors with finding roles.

## Available Playbooks

### Deploy Spark

Deploys Spark on Kubernetes:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/ansible
ansible-playbook playbooks/spark/deploy_spark.yml
```

### Start Spark

Starts Spark services:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/ansible
ansible-playbook playbooks/spark/start_spark.yml
```

### Stop Spark

Stops Spark services:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/ansible
ansible-playbook playbooks/spark/stop_spark.yml
```

### Launch PySpark IPython Environment

Launches an interactive IPython environment with PySpark:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/ansible
ansible-playbook playbooks/spark/launch_ipython.yml
```

#### Options for PySpark IPython

- Create pod without interactive shell:
  ```bash
  ansible-playbook playbooks/spark/launch_ipython.yml -e "launch_shell=false"
  ```

- Customize resources:
  ```bash
  ansible-playbook playbooks/spark/launch_ipython.yml -e "pyspark_ipython_memory_limit=4Gi pyspark_ipython_cpu_limit=2"
  ```

## Common Issues and Solutions

### Permission Issues

If you encounter permission issues when running the playbook:

1. Ensure your user has proper permissions to run kubectl commands
2. Check that you have proper SSH access to the remote machines
3. Make sure your user is in the docker group (`sudo usermod -aG docker $USER`)
4. Ensure all generated configuration files have proper permissions:
   ```bash
   # Check permissions on generated files
   ls -la roles/spark/files/k8s/spark-configmap.yaml
   
   # Fix permissions if needed
   chmod 644 roles/spark/files/k8s/spark-configmap.yaml
   ```

#### ConfigMap Permission Denied Issue

If you see an error like this when starting Spark:

```
TASK [Apply env ConfigMap for pods] *******************************************************************************************************************
An exception occurred during task execution. To see the full traceback, use -vvv. The error was: ansible_collections.kubernetes.core.plugins.module_utils.k8s.exceptions.CoreException: Failed to load resource definition: [Errno 13] Permission denied: '/home/gxbrooks/repos/elastic-on-spark/ansible/roles/spark/files/k8s/spark-configmap.yaml'
```

This is caused by Ansible's k8s module having issues accessing the file directly from the roles directory. To fix this:

1. Regenerate the environment variables:
   ```bash
   cd /home/gxbrooks/repos/elastic-on-spark
   python3 linux/generate_env.py -f
   ```

2. Run the Ansible playbook from the ansible directory:
   ```bash
   cd /home/gxbrooks/repos/elastic-on-spark/ansible
   ansible-playbook playbooks/spark/start_spark.yml
   ```

The updated playbooks automatically copy the ConfigMap to a temporary location before applying it.

### Missing Inventory

If you see an error about a missing inventory file:

1. Make sure you're running the command from the `ansible` directory
2. Verify that `inventory.yml` exists in the ansible directory
3. If your inventory is in a different location, specify it with `-i path/to/inventory.yml`

## Additional Flags

- `-v`: Increase verbosity (use `-vvv` for maximum verbosity)
- `--check`: Dry-run mode
- `--tags TAG_NAME`: Run only tasks with specific tag
- `--skip-tags TAG_NAME`: Skip tasks with specific tag

## Stopping Spark

To stop all Spark components, including services, run:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/ansible
ansible-playbook playbooks/spark/stop_spark.yml
```

This will remove:
- Spark worker pods
- Spark master pod and service
- Spark history server pod and service (accessible at http://localhost:31534)
- Spark ConfigMap

## Using PySpark with IPython

For interactive development with PySpark, use the IPython integration playbook:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/ansible
ansible-playbook playbooks/spark/launch_ipython.yml
```

This will:
1. Create a PySpark-enabled pod in the Kubernetes cluster
2. Launch an interactive IPython shell connected to Spark
3. Provide access to all Spark functionality through the IPython interface

### Options for the IPython Playbook:

- Create without launching shell: 
  ```bash
  ansible-playbook playbooks/spark/launch_ipython.yml -e "launch_shell=false"
  ```

- Customize resource allocation:
  ```bash
  ansible-playbook playbooks/spark/launch_ipython.yml \
    -e "pyspark_ipython_memory_limit=4Gi pyspark_ipython_cpu_limit=2"
  ```

- Custom pod name:
  ```bash
  ansible-playbook playbooks/spark/launch_ipython.yml \
    -e "pyspark_ipython_pod_name=my-custom-pyspark"
  ```

## Common Docker and Registry Issues

When deploying Spark on Kubernetes, Docker image management is critical:

1. **Registry Connection Issues**
   - If pods are stuck in `ImagePullBackOff` state, check registry configuration
   - Ensure registry is running: `docker ps | grep registry`
   - Restart the registry if needed: `docker restart registry`

2. **Image Building Problems**
   - If image build fails, check Docker service: `systemctl status docker`
   - Verify Docker has sufficient disk space: `df -h /var/lib/docker`
   - Check Docker image building logs

3. **Registry Authentication**
   - For private registries, ensure proper authentication is configured
   - Check registry is accessible: `curl localhost:5000/v2/_catalog`

## Troubleshooting History Server Issues

If the Spark History UI (http://localhost:31534) is not responding:

1. First, check if the History Server pod is running:
   ```bash
   kubectl get pods -n spark
   ```

2. If no pods are running, there might be an issue with the Spark start playbook. Run with verbose output:
   ```bash
   cd /home/gxbrooks/repos/elastic-on-spark/ansible
   ansible-playbook -vvv playbooks/spark/start_spark.yml
   ```

3. Check the History Server service is properly exposed:
   ```bash
   kubectl get svc -n spark | grep history
   ```

4. Check the logs from the History Server pod:
   ```bash
   kubectl logs -n spark $(kubectl get pods -n spark | grep history | awk '{print $1}')
   ```

5. Verify the NFS mount for Spark event logs is working:
   ```bash
   kubectl exec -it -n spark $(kubectl get pods -n spark | grep history | awk '{print $1}') -- ls -la /mnt/spark/events
   ```

## Troubleshooting with Diagnostic Scripts

If you encounter issues with Docker or Kubernetes, you can use the included diagnostic script:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/ansible
./scripts/diagnostics_docker_k8s.sh
```

This script checks:
- Docker service status
- Docker registry availability
- Registry contents
- Spark images
- Kubernetes pod and service status
- Image pull issues
- Node status
- Registry configuration
