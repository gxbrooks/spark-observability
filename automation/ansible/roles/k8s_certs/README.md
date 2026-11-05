# Kubernetes Certificates Role

This Ansible role manages Kubernetes certificate distribution and permissions for secure Spark deployment.

## Requirements

- Kubernetes cluster with properly configured certificates
- Root access on Kubernetes nodes

## Role Variables

- `k8s_group`: The group that should have access to Kubernetes certificates
- `control_user`: The user that executes control plane operations
- `k8s_cert_base_dir`: Base directory for Kubernetes certificates
- `runtime_user`: The user that runs application workloads

## Example Playbook

```yaml
- hosts: kubernetes_master:kubernetes_workers
  become: true
  roles:
    - role: k8s_certs
      vars:
        k8s_group: kubernetes
        control_user: "{{ ansible_user }}"
```
