# Dynatrace specifications (observability module)

Dynatrace **configuration** for this repository lives under `observability/dynatrace/` — co-located with the observability stack but **outside** `ansible/`. Playbooks in `ansible/playbooks/observability/dynatrace/` and ServiceNow SGC Dynatrace tasks apply these specifications to the tenant named by `DT_TENANT_URL` / `DT_API_URL` in `vars/variables.yaml`.

## Layout

```
observability/dynatrace/
  README.md
  otel-exporter/                 # OTel → Dynatrace snippet (shared with ELK stack)
  management-zones/
    {mz-slug}/                   # One folder per management zone (e.g. spark-observability)
      management-zone.json
      auto-tags.json.j2
  dashboards/                    # New Dashboards (DQL) — same set for every DT instance
  dynakube/                      # Dynatrace Operator CR template
  integrations/                  # Alerting profiles, OpenPipeline, problem notifications, …
  sampler/                       # GPU metrics sampler
  docs/
```

There is **no** per-tenant directory (e.g. `tenants/pdt20158/`). Specs describe the Dynatrace **solution**; which instance receives them is a variable (`DT_TENANT_URL`, etc.). Object **ids** may differ per instance after apply; the **set of objects** is the same.

| Path | Purpose |
|------|---------|
| `management-zones/spark-observability/` | MZ **Spark Observability** — host group + K8s + CUSTOM_DEVICE rules |
| `integrations/` | OpenPipeline, alerting profile, anomaly detectors, webhook payload templates |
| `dashboards/` | Spark System Metrics and drilldown dashboards |
| `dynakube/dynakube.yaml.j2` | cloudNativeFullStack Operator CR |

## Specification vs discovered entities

| Kind | Specified here? | Notes |
|------|-----------------|-------|
| Management zones, auto-tags, alerting, dashboards, OpenPipeline | **Yes** | Settings 2.0 / OpenPipeline JSON/J2 |
| Hosts, process groups, services, K8s clusters/pods | **No** | Discovered by OneAgent / Operator (prefer discovery over admin-listed clusters) |
| Cluster log → CI when DT cannot resolve CAI | **ServiceNow** | OpenPipeline stamps `spark.sn_ci_lookup=pod_name` + `spark.pod_name`; SN binds AS by pod name |

## Variables

| Variable | Role |
|----------|------|
| `DT_TENANT_URL` / `DT_API_URL` | Which Dynatrace instance to call |
| `DT_MANAGEMENT_ZONE` | MZ display name in Dynatrace |
| `DT_MANAGEMENT_ZONE_SLUG` | Folder under `management-zones/` (default `spark-observability`) |
| `DT_HOST_GROUP` | Host-group condition in MZ rules |
| `dt_specs_root_override` | Optional `-e` when specs live outside the clone |

Playbooks call `ansible/playbooks/observability/dynatrace/common/resolve_dt_spec_paths.yml` to set `dt_integrations_dir`, `dt_mz_settings_file`, etc.

## Related automation

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/observability/dynatrace/deploy.yml \
  -e @../vars/secrets.yaml --tags partitioning

ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/deploy.yml \
  -e @../vars/secrets.yaml
```

See `docs/Tenant_Setup.md` and `Partitioning_and_Tagging.md`.
