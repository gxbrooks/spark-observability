# CSDM deploy automation

Top-level Ansible playbooks wrap **sn-sync** to apply ServiceNow CSDM
specifications under **`specifications/servicenow/regions/`** (see
[servicenow/README.md](../../../../servicenow/README.md)).

Normative TPG: **[sn-sync/docs/CSDM_Specifications.md](../../../../../../sn-sync/docs/CSDM_Specifications.md)**.  
Operator CLI: **[sn-sync/docs/usage.md](../../../../../../sn-sync/docs/usage.md)**.

## Entry points

| Playbook | Role |
|----------|------|
| `deploy.yml` | Imports `service-mapping/deploy.yml`, then runs `sn-sync-inject` |
| `delete.yml` | Runs `sn-sync-delete` (`sn_csdm_delete_all` or `sn_csdm_delete_cis`) |
| `diagnose.yml` | Runs `sn-sync-diff` (exit `1` = differences; playbook does not fail) |

Requires `sn-sync-inject` / `sn-sync-diff` on `PATH` (system install or venv).

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/deploy.yml \
  -e @../vars/secrets.yaml

# One region
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/deploy.yml \
  -e @../vars/secrets.yaml -e sn_region_filter=brooks-lab

# Explicit specs
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/deploy.yml \
  -e @../vars/secrets.yaml \
  -e '{"sn_csdm_spec_paths_override": ["/path/to/app.csdm.yaml"]}'

ansible-playbook -i inventory.yml playbooks/servicenow/csdm/diagnose.yml \
  -e @../vars/secrets.yaml
```

`deploy.yml` loads `SN_*` from Observability secrets/context and
`SN_SM_*` URIs from `vars/contexts/servicenow_sm_deploy.json` (written by
`service-mapping/deploy.yml`). Optional adjunct: horizontal Discovery trigger
(`-e sn_csdm_trigger_horizontal_discovery=false` to skip).

## Direct CLI (same semantics)

```bash
export SN_URL=... SN_USER=... SN_PASSWORD=...
export SN_SM_POPULATE_TAGS_URI=$(jq -r .sm_rest_populate_tags_uri \
  vars/contexts/servicenow_sm_deploy.json)

sn-sync-inject --specs-root ~/repos/spark-observability/servicenow \
  --region brooks-lab \
  --inventory ~/repos/spark-observability/ansible/inventory.yml

sn-sync-delete --all --specs path/to/app.csdm.yaml   # or --ci NAME
sn-sync-diff --specs-root ~/repos/spark-observability/servicenow --region brooks-lab \
  --inventory ~/repos/spark-observability/ansible/inventory.yml
```

Specs are purely declarative — use operators; do not put `csdm_op` in YAML.

## Layout

| Path | Purpose |
|------|---------|
| `deploy.yml` / `diagnose.yml` | Top-level wrappers |
| `common/vars.yml` | Injector env wiring |
| `test/servicenow_insert.yaml` | Synthetic sample (prefer `sn-sync/fixtures/`) |

Service Mapping Scripted REST sources live under
`../service-mapping/` (not here). Discovery coordination diagnostics:
`../service-mapping/diagnose.yml`.

## Adding a stack

1. Create `specifications/servicenow/regions/{region-id}/{name}.csdm.yaml`.
2. List it in that region’s `region.yaml` → `csdm_specs`.
3. Apply matching runtime labels on workloads.
4. Run `csdm/deploy.yml` (or `sn-sync-inject`).

Shared infrastructure values belong in `vars/variables.yaml` (Jinja in specs).
Application-only CSDM names belong in `*.csdm.yaml`.

## Service Mapping by platform

| Platform | Recommended | Vertical discovery |
|----------|-------------|-------------------|
| Kubernetes | Tag-based | **Must not** |
| Docker Compose | Tag-based | **May** (optional; rarely worth it) |
| Host | Tag-based or vertical | **May** |
| SaaS | Manual | **Must not** |

Full normative guidance: `sn-sync/docs/CSDM_Specifications.md` Statement 1.
