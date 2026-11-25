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
| `start.yml` | Make sure the informer runs for the target (unparks it), label the OneAgent pods, copy `servicenow.com/*` pod labels to `cmdb_key_value`. `--tags all,kva_resync` also restarts the informer for a full CMDB resync |
| `stop.yml` | Park the informer (0 replicas) when it feeds the target |
| `test.yml` | Assert all registry locations + workloads per `kva_informer` cluster |
| `diagnose.yml` | The `test.yml` checks (reported, not fatal), informer pod + CMDB counts |

Target instance: `-e target=demo1|demo3` (default: the active instance); see
[../../README.md](../../README.md#target-instance--e-target). `deploy.yml`
writes `vars/contexts/servicenow_k8s_discovery_deploy_<id>.json`.

**One KVA informer per cluster.** The Helm release
(`k8s-informer-<cluster>`) and namespace are per cluster, not per instance, so
it follows the active instance. When the release is installed, a switch (any
install/deploy/start with another target) **repoints** it to the target
(`helm upgrade` with the target's `instance.name` and credentials secret), or
**parks** it (scales it to 0 replicas) when the target lacks the Kubernetes
Visibility Agent app (`sn_acc_visibility`). `stop.yml` parks it too.
`install.yml` installs both prerequisites for the target: the Kubernetes
Visibility Agent Store app on the instance (manifest
`specifications/servicenow/integrations/discovery/store_apps.yml`, CI/CD App Repo
API, skipped when present) and the informer Helm release pointed at it. The informer is
installed on the brooks-lab cluster (`k8s-informer-brooks-lab`). `diagnose.yml` and `stop.yml` run on any target; `test.yml` runs only against
the active instance.

```bash
cd automation/ansible
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/install.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/test.yml -e @../vars/secrets.yaml
```
