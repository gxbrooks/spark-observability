# CS224N Playbooks

This directory contains playbooks that layer CS224N notebook dependencies onto the existing Kubernetes Jupyter environment.

These playbooks leverage the existing Jupyter playbooks in `ansible/playbooks/jupyter`.

## Playbooks

### `deploy.yml`

Stages CS224N artifacts and redeploys Jupyter so startup bootstraps the `cs224n` conda env + kernel.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/CS224N/deploy.yml
```

### `undeploy.yml`

Removes CS224N runtime components (kernel + venv) and staged artifacts.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/CS224N/undeploy.yml
```
