# Dynatrace OOTB Kubernetes monitoring settings

Environment-scoped Settings 2.0 specs for out-of-the-box Kubernetes anomaly
detection and cloud Kubernetes monitoring pipelines.

| Area | Schema | Spec files |
| ---- | ------ | ---------- |
| Clusters | `builtin:anomaly-detection.kubernetes.cluster` | `cluster-anomaly-*.json` |
| Namespaces | `builtin:anomaly-detection.kubernetes.namespace` | `namespace-anomaly-*.json` |
| Nodes | `builtin:anomaly-detection.kubernetes.node` | `node-anomaly-*.json` |
| Workloads | `builtin:anomaly-detection.kubernetes.workload` | `workload-anomaly-*.json` |
| Volumes (PVC) | `builtin:anomaly-detection.kubernetes.pvc` | `pvc-anomaly-*.json` |
| Cloud K8s monitoring pipelines | `builtin:cloud.kubernetes.monitoring` | `cloud_monitoring-anomaly-*.json` |

`*-enabled.json` enables detectors with lab-tuned thresholds: **60%** for
percent-based rules, observation windows at **~1/3** of Dynatrace schema
defaults (sample periods clamped so sample ≤ observation).
`*-disabled.json` sets detectors / pipelines **disabled** (unconfigure).

Apply via:

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/observability/dynatrace/k8s_monitoring_start.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/observability/dynatrace/k8s_monitoring_stop.yml -e @../vars/secrets.yaml
```

`k8s_monitoring_start.yml` also activates the Kubernetes app
(`builtin:app-transition.kubernetes`).
