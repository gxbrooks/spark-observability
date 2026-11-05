# Spark Role

This Ansible role handles the deployment of Spark on Kubernetes.

## Requirements

- Kubernetes cluster with proper certificates configured
- NFS mount for Spark event logs

## Dependencies

- k8s_certs role for certificate management

## Role Variables

- `spark_version`: The version of Spark to deploy
- `registry_host`: The Docker registry host address
- `spark_image`: The full Spark image name including registry and version
- `k8s_config_dir`: Directory for Kubernetes configuration files
- `kubeconfig`: Path to the Kubernetes configuration file

## Example Playbook

```yaml
- hosts: kubernetes_master
  roles:
    - role: spark
      vars:
        spark_version: "{{ lookup('env', 'SPARK_VERSION') | default('3.5.1') }}"
```
