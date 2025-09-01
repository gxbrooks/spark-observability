# Kubernetes Playbooks for Elastic-on-Spark

This directory contains Ansible playbooks for managing a Kubernetes cluster for Spark workloads.

## Playbook Overview

The playbooks follow a verb-object naming convention for easier tab-completion:

* `install_k8s.yml` - Installs and initializes a new Kubernetes cluster (creates kubeconfig with hostnames)
* `start_k8s.yml` - Starts Kubernetes services and ensures they are running
* `stop_k8s.yml` - Stops Kubernetes services
* `reset_k8s.yml` - Resets the Kubernetes cluster (destructive operation)
* `status_k8s.yml` - Checks the status of the Kubernetes cluster
* `regenerate_k8s_certs.yml` - Regenerates Kubernetes API server certificates with proper hostnames

## Usage

Run the playbooks using the standard Ansible command:

```bash
# Install and initialize Kubernetes
ansible-playbook -i ../../inventory.yml install_k8s.yml

# Start Kubernetes services
ansible-playbook -i ../../inventory.yml start_k8s.yml

# Check Kubernetes status
ansible-playbook -i ../../inventory.yml status_k8s.yml

# Create or recreate kubeconfig files with hostnames
ansible-playbook -i ../../inventory.yml install_k8s.yml --tags=kubeconfig

# Regenerate certificates with proper hostnames
ansible-playbook -i ../../inventory.yml regenerate_k8s_certs.yml

# Stop Kubernetes services
ansible-playbook -i ../../inventory.yml stop_k8s.yml

# Reset Kubernetes cluster
ansible-playbook -i ../../inventory.yml reset_k8s.yml
```

## Workflow After Network Changes

If IP addresses have changed (e.g., after moving to a new network):

1. Run `install_k8s.yml --tags=kubeconfig` to create kubeconfig files with proper hostnames
2. If TLS certificate errors occur, run `regenerate_k8s_certs.yml` to update certificates
3. Run `start_k8s.yml` to start Kubernetes services
4. Run `status_k8s.yml` to verify Kubernetes is working properly
5. Deploy and start Spark using the Spark playbooks

## Spark Deployment

After Kubernetes is running, use the Spark playbooks to deploy and start Spark:

```bash
# Deploy Spark on Kubernetes
ansible-playbook -i ../../inventory.yml ../spark/deploy_spark.yml

# Start Spark on Kubernetes
ansible-playbook -i ../../inventory.yml ../spark/start_spark.yml
```
