# ServiceNow specifications

ServiceNow **configuration** for this repository lives here — outside `ansible/`. Ansible playbooks under `ansible/playbooks/servicenow/` are **management automation** only (deploy, diagnose, compare, discovery, SGC); they read paths from this tree.

## Layout

```
servicenow/
  README.md
  docs/                          # Platform-wide TPG and process docs
  integrations/
    sgc/                         # ServiceNow-side SGC integration artifacts (business rules, scripts)
  regions/
    {region-id}/                 # Management region (enterprise: team / geography / portfolio boundary)
      region.yaml                # Cross-platform registry (CMDB location, Dynatrace tenant/MZ refs, spec list)
      {stack}.csdm.yaml          # CSDM specifications (ServiceNow CMDB/CSDM object definitions)
```

### Optimiz lab (`regions/brooks-lab/`)

| File | Purpose |
|------|---------|
| `region.yaml` | Registry for brooks-lab: CMDB location, Dynatrace tenant/MZ, compare scope, linked specs |
| `observability-platform.csdm.yaml` | Elastic observability stack BA/BS/AS |
| `spark.csdm.yaml` | Apache Spark on Kubernetes |
| `elastic-agent.csdm.yaml` | Elastic Agent per node |
| `dynatrace-monitoring.csdm.yaml` | Dynatrace Tenant and OneAgent AS |

## Specification vs automation

- **`*.csdm.yaml`** — Declarative **specifications**: shorthand for ServiceNow UI/API steps to create Business Applications, Business Services, Application Services, relationships, tags, and discovery triggers. Not “intent”; these are the authoritative model for what should exist in CMDB.
- **`region.yaml`** — Cross-platform join point: links CMDB placement to Dynatrace partitioning and lists which CSDM specs belong to this management region. Compare and deploy automation scan `regions/*/region.yaml`.

## Variables (spec locations outside Git)

Automation resolves specifications from:

| Variable | Default |
|----------|---------|
| `sn_specs_root` | `{repo}/servicenow` |
| `sn_regions_dir` | `{sn_specs_root}/regions` |
| `sn_specs_root_override` | `-e` override when specs are managed outside the clone |

Deploy and compare **sweep** `sn_regions_dir/*/region.yaml` to discover regions. Filter one region with `-e sn_region_filter=brooks-lab`.

## Related paths

| Path | Role |
|------|------|
| `ansible/playbooks/servicenow/` | Ansible playbooks (csdm, discovery, sgc) |
| `servicenow/comparator/` | Python compare (export + report); specs: `entity_taxonomy.yaml`, `dynatrace-correlation.yaml` |

## Adding a management region

1. Create `servicenow/regions/{region-id}/region.yaml` (copy from `brooks-lab`).
2. Add one or more `{name}.csdm.yaml` specifications per `servicenow/docs/CSDM_Specifications.md`.
3. Point `region.yaml` `dynatrace.tenant_id` and `dynatrace.management_zone` at the correct entry under `observability/dynatrace/tenants/`.
4. Re-run `csdm/deploy.yml` and `python -m servicenow.comparator` (no registry edit required when using region discovery).
