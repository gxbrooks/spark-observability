# ServiceNow ↔ Dynatrace comparator

Python implementation for CMDB/CSDM vs Smartscape model comparison. Replaces the former Ansible compare playbooks.

## Run

```bash
cd spark-observability
pip install -r servicenow/comparator/requirements.txt
PYTHONPATH=. python -m servicenow.comparator
```

Optional flags: `--scope-unit-id brooks-lab-onprem`, `--filter-by-cmdb-location`, `--filter-by-dynatrace-mz`, `--output-dir tmp/compare/manual`.

Requires `vars/secrets.yaml` (SN credentials) and `vars/contexts/dynatrace_ansible_vars.yml` (DT API token).

## Outputs

Writes under `tmp/compare/<timestamp>/`:

| File | Purpose |
|------|---------|
| `DT_SN_Model_Comparison.json` | Raw export (CMDB, Smartscape entities, CSDM intent) |
| `DT_SN_Model_Comparison_Report.json` | Consolidated findings + inventory |

Report **`findings`** (v1.3) is organized by discoverability:

- **`A_dual_discoverable`** — hosts, K8s clusters/nodes (SN Discovery/KVA ↔ Smartscape)
  - `A1_in_cmdb_not_smartscape`, `A2_in_smartscape_not_cmdb`, `A3_ire_mapped`
- **`B_dynatrace_injected`** — SGC-imported types (process groups, services, applications)
  - `B1_in_smartscape_not_cmdb`, `B2_in_cmdb_not_smartscape`, `B3_sgc_mapped`
- **`C_specification_alignment`** — CSDM intent, tag bindings, partitioning

## Specification files

| File | Role |
|------|------|
| `entity_taxonomy.yaml` | CMDB class ↔ Smartscape entity type discoverability map |
| `dynatrace-correlation.yaml` | Expected management zone, cluster name map, partitioning diagnostics |

Region registry: `servicenow/regions/*/region.yaml` (`compare.dynatrace_correlation_file` overrides correlation path).

## Report-only (from existing export)

```bash
PYTHONPATH=. python -m servicenow.comparator.analysis.report \
  tmp/compare/<timestamp>/DT_SN_Model_Comparison.json
```

## Docs

- [DT_SN_Comparison_Process.md](../docs/DT_SN_Comparison_Process.md)
- [DT_SN_Mapping.md](../docs/DT_SN_Mapping.md)
- [DT_SN_Specification_Guide.md](../docs/DT_SN_Specification_Guide.md)
