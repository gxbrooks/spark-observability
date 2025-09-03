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
* `create_join_token.yml` - Creates a join token for adding worker nodes to the cluster

## Usage

Run the playbooks using the standard Ansible command:

```bash
# Initial Installation (First Time Setup)
ansible-playbook -i ../../inventory.yml install_k8s.yml

# Start Kubernetes services
ansible-playbook -i ../../inventory.yml start_k8s.yml

# Check Kubernetes status
ansible-playbook -i ../../inventory.yml status_k8s.yml

# After Hostname Changes (For Existing Installation)
# First regenerate certificates with new hostnames:
ansible-playbook -i ../../inventory.yml regenerate_k8s_certs.yml
# Then create kubeconfig files with the new certificates:
ansible-playbook -i ../../inventory.yml install_k8s.yml --tags=kubeconfig

# Create a join token for worker nodes
ansible-playbook -i ../../inventory.yml create_join_token.yml

# Stop Kubernetes services
ansible-playbook -i ../../inventory.yml stop_k8s.yml

# Reset Kubernetes cluster
ansible-playbook -i ../../inventory.yml reset_k8s.yml
```

## Workflow Guide

### Initial Setup (Fresh Installation)

For a fresh installation or after resetting Kubernetes:

1. Run the main installation playbook:
   ```bash
   ansible-playbook -i ../../inventory.yml install_k8s.yml
   ```
   This will:
   - Install Kubernetes packages
   - Initialize the cluster with `kubeadm init`
   - Create initial certificates and kubeconfig files
   - Configure networking with Flannel

2. Start Kubernetes services and verify they're running:
   ```bash
   ansible-playbook -i ../../inventory.yml start_k8s.yml
   ansible-playbook -i ../../inventory.yml status_k8s.yml
   ```

### After Hostname or Network Changes

If IP addresses or hostnames have changed (e.g., after moving to a new network):

1. Update your inventory.yml with the current hostname/IP addresses

2. Run these playbooks in this specific order:
   ```bash
   # Step 1: Regenerate certificates with the correct hostnames
   ansible-playbook -i ../../inventory.yml regenerate_k8s_certs.yml
   
   # Step 2: Create kubeconfig files with the new certificates
   ansible-playbook -i ../../inventory.yml install_k8s.yml --tags=kubeconfig
   
   # Step 3: Restart Kubernetes services
   ansible-playbook -i ../../inventory.yml start_k8s.yml
   
   # Step 4: Verify everything is working
   ansible-playbook -i ../../inventory.yml status_k8s.yml
   ```

> **Important:** The `regenerate_k8s_certs.yml` playbook requires Kubernetes to be already installed. 
> If you're setting up a new installation, start with `install_k8s.yml` first.

### Certificate Management Details

The certificate regeneration process:

1. **Hostname Detection**: The playbook dynamically extracts all relevant hostnames from your inventory:
   - The FQDN/ansible_host value from your inventory
   - The inventory hostname (usually the short name)
   - The short hostname extracted from FQDN if present
   - localhost and Kubernetes internal names

2. **Certificate Backup**: Before regenerating certificates, the playbook:
   - Creates a timestamped backup directory
   - Backs up existing certificates if present
   - Preserves your CA certificates which remain valid

3. **Certificate Validation**: After regeneration, the playbook verifies:
   - The API server is accessible with the new certificates
   - All required hostnames are present in the certificate SANs
   - TLS connections work properly with strict validation

4. **Security Enhancements**:
   - Removes any `insecure-skip-tls-verify: true` flags from kubeconfig files
   - Performs validation tests using openssl and curl

### Troubleshooting Certificate Issues

If you encounter certificate validation errors:

1. **Check hostname resolution**: Ensure your hostnames resolve correctly:
   ```bash
   ping $(hostname)
   ping $(hostname -f)
   ```

2. **Verify certificate SANs**: Check that your certificate contains all needed hostnames:
   ```bash
   openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text | grep -A1 "Subject Alternative Name"
   ```
   
   Note: The certificate now includes both original and lowercase versions of each hostname for case-insensitive matching. If you see duplicate entries that only differ in capitalization, this is by design.

3. **Test API server directly**: Try connecting directly:
   ```bash
   curl -v --cert /etc/kubernetes/pki/apiserver-kubelet-client.crt \
        --key /etc/kubernetes/pki/apiserver-kubelet-client.key \
        https://localhost:6443/api/v1/nodes
   ```

4. **Run the playbook with verbose output**: For more debugging information:
   ```bash
   ansible-playbook -i ../../inventory.yml regenerate_k8s_certs.yml -v
   ```

## Spark Deployment

After Kubernetes is running, use the Spark playbooks to deploy and start Spark:

```bash
# Deploy Spark on Kubernetes
ansible-playbook -i ../../inventory.yml ../spark/deploy_spark.yml

# Start Spark on Kubernetes
ansible-playbook -i ../../inventory.yml ../spark/start_spark.yml
```
