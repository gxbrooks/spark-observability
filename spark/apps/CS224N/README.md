# CS224N Jupyter Environment (Cluster-Managed)

This directory contains artifacts used to configure the Kubernetes-hosted Jupyter Notebook for Stanford CS224N.

## Purpose

CS224N setup instructions assume local Jupyter + local shell commands. In this project, those steps are translated into cluster automation so the Jupyter pod starts with a `cs224n` `venv` environment and notebook kernel.

## Artifacts

- `env.yml` - input file used to detect environment changes (hash/invalidation)
- `bootstrap_cs224n.sh` - startup bootstrap script executed inside the Jupyter container

## Deployment

Use the CS224N playbook:

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/CS224N/deploy.yml
```

This will:

1. Copy this directory to `/mnt/spark/jupyter/notebooks/CS224N` on Lab2.
2. Redeploy Jupyter using existing Jupyter playbooks.
3. On pod startup, run `bootstrap_cs224n.sh` which:
   - creates/updates a `venv` under `/home/jovyan/.cs224n/venv`
   - installs/upgrades the Jupyter kernel named `cs224n`

## Deactivation

To remove CS224N runtime components from Jupyter:

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/CS224N/undeploy.yml
```

This removes the `cs224n` kernel + venv inside the running Jupyter pod and removes staged CS224N artifacts from `/mnt/spark/jupyter/notebooks/CS224N`.
