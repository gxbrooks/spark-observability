# Spark Deployment Consolidation

This document describes the consolidation of multiple Spark deployment approaches into a single, secure Ansible-based approach.

## Overview

The elastic-on-spark project previously contained multiple approaches for deploying Spark on Kubernetes. This has been consolidated into a single, secure deployment method using Ansible roles and playbooks.

## Deployment Structure

- Primary deployment playbook: `ansible/playbooks/spark/deploy_spark.yml`
- Certificate management: `ansible/roles/k8s_certs`
- Spark deployment: `ansible/roles/spark`

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

## Best Practices

- Role dependencies manage component relationships
- Templates are stored in role-specific template directories
- Variables are defined in role defaults
- Roles are stored in the standard `ansible/roles/` directory
- Roles are referenced by their simple name in playbooks (e.g., `name: spark`)
- ansible.cfg contains a single, clear roles_path setting

## Removed/Consolidated Scripts

The following scripts/files have been consolidated or removed:
- Redundant certificate management scripts
- Multiple deployment approaches
- Direct application of Kubernetes manifests

These have been replaced by the structured Ansible roles and playbooks.
