# Phase 2 — Kubernetes discovery (KVA Informer)

Discovers `kva_informer`-enabled clusters from **`K8S_CLUSTERS`** in
`vars/variables.yaml` into ServiceNow CMDB.

## Cluster registry

All clusters, on every ServiceNow instance, are defined in `K8S_CLUSTERS`
(`vars/variables.yaml`). Per-entry **capability flags** (absent = false):

- **`kva_informer: true`** — this repo installs the KVA informer and validates the cluster's CMDB content
- **`dynatrace: true`** — this repo applies DynaKube, auto-tags, and the management zone for this cluster name

Every entry with a `location` is location-mapped in the CMDB regardless of flags.

See [specifications/servicenow/docs/install.md](../../../../../../specifications/servicenow/docs/install.md) §5 for field reference.

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

Target instance: `-e target=demo1|demo3|all` (default `demo3`); see
[../../README.md](../../README.md#target-instance--e-target). `deploy.yml`
writes `vars/contexts/servicenow_k8s_discovery_deploy_<id>.json`.

**One KVA informer per cluster.** The Helm release
(`k8s-informer-<cluster>`) and namespace are per cluster, not per instance, so
`install.yml` with a different `target` (or `target=all`) **repoints** the
cluster's informer to that instance (`instance.name`) instead of adding a
second one. Only the last-installed instance receives KVA data. KVA is installed
for Demo1 today; `deploy.yml`, `test.yml` and `diagnose.yml` are safe on any
target.

```bash
cd automation/ansible
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/install.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/test.yml -e @../vars/secrets.yaml
```
