# Dynatrace specifications (observability module)

Dynatrace **configuration** for this repository lives under `observability/dynatrace/` — co-located with the observability stack (OpenTelemetry Collector dual-feed, shared lab context) but **outside** `ansible/`. Playbooks in `ansible/playbooks/observability/dynatrace/` apply these specifications to the tenant.

## Layout

```
observability/dynatrace/
  README.md
  otel-exporter/                 # OTel → Dynatrace snippet (shared with ELK stack)
  tenants/
    {tenant-id}/
      tenant.yaml                # Tenant descriptor and path index
      management-zones/
        {mz-slug}/               # One folder per management zone (DT admin sphere)
          management-zone.json   # Settings 2.0: MZ rules (deploy payload)
          auto-tags.json.j2      # Settings 2.0: auto-tag rules
      dashboards/                # New Dashboards (DQL) JSON documents
      dynakube/                  # Dynatrace Operator CR template
      integrations/              # Alerting profiles, problem notifications, metric/log events
      sampler/                   # GPU metrics sampler (runtime scripts + systemd units)
      docs/                      # Tenant/partitioning documentation
```

### Lab tenant (`tenants/pdt20158/`)

| Path | Purpose |
|------|---------|
| `management-zones/spark-observability/` | MZ **Spark Observability** — host group + K8s cluster rules |
| `integrations/` | SGC-related DT Settings (alerting profile, anomaly detectors, webhook payload templates) |
| `dashboards/` | Spark System Metrics and drilldown dashboards |
| `dynakube/dynakube.yaml.j2` | cloudNativeFullStack Operator CR |

## Specification vs discovered entities

| Kind | Specified here? | Notes |
|------|-----------------|-------|
| Management zones, auto-tags, alerting, dashboards | **Yes** | Settings 2.0 JSON/J2; applied by `dynatrace/deploy.yml` |
| Hosts, process groups, services, K8s objects | **No** | Discovered by OneAgent / Operator; exported by `compare.yml` |
| SN ↔ DT correlation keys | **ServiceNow** `region.yaml` + compare `dynatrace-correlation.yaml` | SN is system of reference for cross-platform compare |

## Variables (spec locations outside Git)

| Variable | Default |
|----------|---------|
| `dt_specs_root` | `{repo}/observability/dynatrace` |
| `dt_tenants_dir` | `{dt_specs_root}/tenants` |
| `dt_specs_root_override` | `-e` override when specs live outside the clone |

Playbooks call `resolve_dt_spec_paths.yml`, which scans `tenants/*/tenant.yaml` and resolves paths for the active tenant and management zone (`DT_MANAGEMENT_ZONE` or `-e dt_management_zone_slug=`).

## Multiple tenants and management zones

Enterprises may add:

```
tenants/
  pdt20158/
    management-zones/spark-observability/
    management-zones/analytics-production/
  {other-tenant}/
    management-zones/...
```

Each ServiceNow management region (`servicenow/regions/*/region.yaml`) references `dynatrace.tenant_id` and `dynatrace.management_zone` (slug under `management-zones/`).

## Related automation

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/observability/dynatrace/deploy.yml \
  -e @../vars/secrets.yaml --tags partitioning
```

See `tenants/pdt20158/docs/Tenant_Setup.md` and `Partitioning_and_Tagging.md`.
