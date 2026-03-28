# Secure Spark on Kubernetes Deployment Guide

This guide explains how to deploy Apache Spark on Kubernetes securely, ensuring all communications use SSL certificates and Docker images are properly managed.

## Overview

The deployment solution addresses two key security concerns:

1. **Secure Kubernetes Certificate Management**
   - Proper certificate-based authentication between clients and Kubernetes API
   - No insecure TLS verification skipping
   - Proper certificate distribution between development and runtime environments
   - Automatic certificate regeneration when hostnames or network configurations change

2. **Secure Docker Image Management**
   - Local Docker registry for image distribution
   - Consistent image versioning and deployment
   - No insecure image pull policies

## Prerequisites

- A running Kubernetes cluster
- NFS mount at `/mnt/spark/events` for Spark History Server
- Proper network connectivity between all components

## Deployment Instructions

### Using Ansible (Recommended)

Run the secure deployment wrapper script:

```bash
./deploy_spark.sh
```

Alternatively, you can run the Ansible playbook directly:

```bash
cd /home/gxbrooks/repos/spark-observability
ansible-playbook ansible/playbooks/spark/deploy_spark.yml
```

This will:
1. Configure secure Kubernetes certificates
2. Build and publish the Spark Docker image
3. Deploy all Spark components with proper security settings

## Kubernetes Certificate Management

### Initial Setup

During the initial Kubernetes setup, certificates are created automatically with:
```bash
ansible-playbook -i inventory.yml ansible/playbooks/k8s/install_k8s.yml
```

### After Hostname or Network Changes

If your cluster's hostname or network configuration changes, regenerate certificates:

```bash
# Step 1: Update your inventory.yml with current hostnames/IPs

# Step 2: Regenerate certificates with proper hostnames
ansible-playbook -i inventory.yml ansible/playbooks/k8s/regenerate_k8s_certs.yml

# Step 3: Update kubeconfig files with new certificates 
ansible-playbook -i inventory.yml ansible/playbooks/k8s/install_k8s.yml --tags=kubeconfig

# Step 4: Restart Kubernetes services
ansible-playbook -i inventory.yml ansible/playbooks/k8s/start_k8s.yml
```

The certificate regeneration process:
- Backs up existing certificates (creates a timestamped backup in `/etc/kubernetes/pki/`)
- Generates both original and lowercase variants of all hostnames in the certificate SANs
- Ensures unique hostname entries to avoid duplicates
- Performs validation to ensure certificates work properly with case-insensitive matching
- Removes any insecure TLS verification flags
- Validates API server connectivity with proper certificate validation

### (Deprecated) Manual Scripts

The following manual scripts have been deprecated in favor of the Ansible-based approach:
   ```bash
   /home/gxbrooks/repos/spark-observability/spark/deploy_spark_secure.sh
   ```

## Certificate Management Details

The solution uses the following approach for certificate management:

1. The Kubernetes CA certificate from `/etc/kubernetes/pki/ca.crt` is embedded directly in the kubeconfig files
2. Each user gets a properly configured kubeconfig with the embedded CA certificate
3. Certificate validation is strictly enforced - all `insecure-skip-tls-verify` flags have been removed
4. Hostname validation is automatically verified during installation and certificate regeneration
5. **Case-insensitive hostname matching** ensures certificates work with different hostname capitalizations
6. Both original and lowercase versions of each hostname are included in certificate SANs
7. When network configurations change, `regenerate_k8s_certs.yml` creates new certificates with correct hostnames
8. Group permissions ensure both development and runtime users have access
9. Certificate validation is automatically tested during setup to detect potential issues

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

1. Check if hostname validation is successful:
   ```bash
   SERVER=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}' | grep -o 'https://[^:]*' | sed 's#https://##')
   openssl s_client -connect ${SERVER}:6443 -servername ${SERVER} -showcerts </dev/null 2>&1 | grep -i "Verification"
   ```
   You should see "Verification: OK" in the output. If not, certificates need to be regenerated.

2. Inspect the API server certificate's Subject Alternative Names:
   ```bash
   echo | openssl s_client -connect localhost:6443 2>/dev/null | openssl x509 -text | grep -A1 "Subject Alternative Name"
   ```
   Verify that all required hostnames (including lowercase variants) are present in the output.

3. Regenerate certificates with the correct hostname:
   ```bash
   # The regeneration playbook will include both original and lowercase variants of all hostnames
   ansible-playbook -i inventory.yml ansible/playbooks/k8s/regenerate_k8s_certs.yml
   
   # Update kubeconfig files with the new certificates
   ansible-playbook -i inventory.yml ansible/playbooks/k8s/install_k8s.yml --tags=kubeconfig
   
   # Restart Kubernetes services
   ansible-playbook -i inventory.yml ansible/playbooks/k8s/start_k8s.yml
   ```

4. Validate that kubeconfig is properly configured with certificate validation:
   ```bash
   kubectl config view | grep -A2 "cluster:"
   ```
   Ensure there is no `insecure-skip-tls-verify: true` in the output.
   
5. Test API server access with certificate verification:
   ```bash
   # Using curl to test certificate validation
   curl --cacert /etc/kubernetes/pki/ca.crt https://${SERVER}:6443/version
   
   # Using kubectl with proper certificate validation
   KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes
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
   docker pull localhost:5000/spark:${SPARK_VERSION}
   ```
