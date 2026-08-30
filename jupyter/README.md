# JupyterHub representations

Helm values for the optional multi-user JupyterHub chart. The default JupyterHub
deployment uses Kubernetes manifests under `ansible/roles/spark/` and
`ansible/playbooks/jupyter/deploy.yml`.

| File | Purpose |
| :--- | :--- |
| `jupyterhub-values.yaml.j2` | Helm values for `playbooks/jupyter/tasks/deploy-jupyterhub-helm.yml` |

Apply with:

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/jupyter/tasks/deploy-jupyterhub-helm.yml
```
