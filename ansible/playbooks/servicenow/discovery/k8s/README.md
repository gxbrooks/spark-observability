# Phase 2 — Kubernetes discovery (KVA Informer)

Discovers `kva_informer`-enabled clusters from **`K8S_CLUSTERS`** in
`vars/variables.yaml` into ServiceNow CMDB.

## Cluster registry

All clusters on the shared ServiceNow instance are defined in `K8S_CLUSTERS`
(`vars/variables.yaml`). Per-entry **capability flags** (absent = false):

- **`kva_informer: true`** — this repo installs the KVA informer and validates the cluster's CMDB content
- **`dynatrace: true`** — this repo applies DynaKube, auto-tags, and the management zone for this cluster name

Every entry with a `location` is location-mapped in the CMDB regardless of flags.

See [servicenow/docs/install.md](../../../../servicenow/docs/install.md) §5 for field reference.

## Location (product-native)

`deploy.yml` applies ServiceNow best practice:

1. Ensure `cmn_location` + set `cmdb_ci_kubernetes_cluster.location` for **every** `K8S_CLUSTERS` entry
2. Business rule `k8s-inherit-location-from-cluster` copies `cluster.location` to child CIs on KVA insert/update

## Playbooks

| Playbook | Purpose |
| -------- | ------- |
| `install.yml` | Helm KVA Informer on the `kva_informer`-enabled cluster |
| `deploy.yml` | All registry locations + inheritance business rule |
| `discover.yml` | Restart Informer for CMDB resync |
| `test.yml` | Assert all registry locations + workloads per `kva_informer` cluster |
| `diagnose.yml` | Informer pod + CMDB counts |

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/install.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/test.yml -e @../vars/secrets.yaml
```
