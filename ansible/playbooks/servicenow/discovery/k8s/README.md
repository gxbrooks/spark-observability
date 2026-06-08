# Phase 2 — Kubernetes discovery (KVA Informer)

Discovers the **primary** cluster (`K8S_PRIMARY_CLUSTER`, currently `brooks-lab`) into ServiceNow CMDB.

## Cluster registry

All clusters on the shared ServiceNow instance are defined in `vars/variables.yaml`:

- **`K8S_PRIMARY_CLUSTER`** — cluster this repo manages (KVA install, Dynatrace, tests)
- **`K8S_CLUSTERS`** — multi-entry map: name, location, managed flag, per-cluster options

See `../docs/install.md` §5 for field reference.

## Location (product-native)

`deploy.yml` applies ServiceNow best practice:

1. Ensure `cmn_location` + set `cmdb_ci_kubernetes_cluster.location` for **every** `K8S_CLUSTERS` entry
2. Business rule `k8s-inherit-location-from-cluster` copies `cluster.location` to child CIs on KVA insert/update

## Playbooks

| Playbook | Purpose |
| -------- | ------- |
| `install.yml` | Helm KVA Informer on **managed** primary cluster |
| `deploy.yml` | All registry locations + inheritance business rule |
| `discover.yml` | Restart Informer for CMDB resync |
| `test.yml` | Assert registry locations + primary cluster workloads |
| `diagnose.yml` | Informer pod + CMDB counts |

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/install.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/test.yml -e @../vars/secrets.yaml
```
