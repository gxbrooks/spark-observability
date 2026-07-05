# Service Mapping install / deploy

| Playbook | Purpose |
| -------- | ------- |
| `install.yml` | Store apps + classic plugin (`com.snc.service-mapping`) |
| `deploy.yml` | REST operations + **CI tag categories** (idempotent) |

`csdm/deploy.yml` imports `deploy.yml` before applying CSDM specs.

## Components (manifest order)

| Scope / plugin | Purpose |
| -------------- | ------- |
| `sn_cmdb_ci_class` | CMDB CI Class Model (dependency) |
| `sn_itom_pattern` | Discovery and Service Mapping Patterns |
| `sn_service_mapping` | CSDM Service Mapping scoped app (`/populate_tags` REST) |
| `sn_itom_map_app` | Service Mapping – Map workspace (`/now/svc-map/*` when entitled) |
| `com.snc.service-mapping` | Classic plugin — creates **`service_mapping_admin`** |

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

Per-service tag filters from `*.csdm.yaml` are applied by **`csdm/deploy.yml`** regardless
of Tag Categories UI state.

## Usage

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/service-mapping/install.yml \
  -e @../vars/secrets.yaml
```

Also invoked from top-level `playbooks/servicenow/install.yml` **after** `sgc/install.yml`.

Variables:

- `sn_sm_ensure_store_apps` — default **false**; set **true** to CI/CD refresh every manifest app (slow; may warn on shared demos)
- `sn_sm_configure_tag_categories` — default **true**: REST bootstrap of default categories (skips on ACL)

## Related

- `csdm/deploy.yml` — `tag_list` population from `*.csdm.yaml`
- [servicenow/docs/install.md](../../../../servicenow/docs/install.md) §6.5
- [Tag_Based_Service_Mapping.md](../../../../servicenow/docs/Tag_Based_Service_Mapping.md)
