# Service Mapping install / deploy

| Playbook | Purpose |
| -------- | ------- |
| `install.yml` | Store apps + classic plugin (`com.snc.service-mapping`) |
| `deploy.yml` | Scripted REST operations + **CI tag categories** (idempotent) |
| `diagnose.yml` | Horizontal vs vertical Discovery timing and SM enrichment probes |

`csdm/deploy.yml` imports `deploy.yml` before running `csdm-inject`.

## Components (manifest order)

| Scope / plugin | Purpose |
| -------------- | ------- |
| `sn_cmdb_ci_class` | CMDB CI Class Model (dependency) |
| `sn_itom_pattern` | Discovery and Service Mapping Patterns |
| `sn_service_mapping` | CSDM Service Mapping scoped app (`/populate_tags` REST) |
| `sn_itom_map_app` | Service Mapping – Map workspace (`/now/svc-map/*` when entitled) |
| `com.snc.service-mapping` | Classic plugin — creates **`service_mapping_admin`** |

## Layout

| Path | Purpose |
|------|---------|
| `tasks/deploy_sm_rest_api.yml` | Install/update Scripted REST API |
| `files/sm_*.js` | Operation scripts (`discover`, `populate_tags`, `ensure_tag_categories`) |
| `common/ensure_tag_categories.yml` | Default CI tag categories via REST |
| `tasks/diagnose_*.yml` | Coordination / enrichment diagnostics |

## Roles (Zurich)

| Role | Notes |
| ---- | ----- |
| **`service_mapping_admin`** | Primary admin role after plugin activation — use this, not `sm_admin` |
| **`sm_admin`** | Often **absent** on Zurich; do not search for it |
| **`itom_admin`** | Umbrella ITOM admin (optional) |

## Tag Categories UI

- **Classic (works on optimizincdemo1):** Filter Navigator → **CI tag categories**
  or `svc_tag_categories_list.do`. Requires **`service_mapping_admin`**.
- **Empty list is normal** — click **New** and create categories (see install.md §6.5).
- **Workspace** `/now/svc-map/tag-categories` may be unavailable when Store download
  for `sn_itom_map_app` is blocked; classic UI is sufficient for brooks-lab.

Per-service tag filters from `*.csdm.yaml` are applied by **`csdm-inject`**
(via `csdm/deploy.yml`) regardless of Tag Categories UI state.

## Usage

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/service-mapping/install.yml \
  -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/service-mapping/deploy.yml \
  -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/service-mapping/diagnose.yml \
  -e @../vars/secrets.yaml
```

Also invoked from top-level `playbooks/servicenow/install.yml` **after** `sgc/install.yml`.

Variables:

- `sn_sm_ensure_store_apps` — default **false**; set **true** to CI/CD refresh every manifest app (slow; may warn on shared demos)
- `sn_sm_configure_tag_categories` — default **true**: REST bootstrap of default categories (skips on ACL)

## Related

- `csdm/deploy.yml` — `csdm-inject` applies tag_list population from `*.csdm.yaml`
- [servicenow/docs/install.md](../../../../servicenow/docs/install.md) §6.5
- [Tag_Based_Service_Mapping.md](../../../../servicenow/docs/Tag_Based_Service_Mapping.md)
