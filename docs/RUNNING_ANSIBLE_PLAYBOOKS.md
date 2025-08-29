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

All roles are referenced by their simple name (e.g., `name: spark`) as the `roles_path` is configured in ansible.cfg.

## Running the Spark Deployment Playbook

⚠️ **IMPORTANT**: All Ansible commands **MUST** be run from the `ansible` directory to ensure ansible.cfg is properly loaded and roles can be found.

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

## Common Issues and Solutions

### Permission Issues

If you encounter permission issues when running the playbook:

1. Ensure your user has proper permissions to run kubectl commands
2. Check that you have proper SSH access to the remote machines
3. Make sure your user is in the docker group (`sudo usermod -aG docker $USER`)

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
