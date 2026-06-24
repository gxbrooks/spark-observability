# CSDM object specifications

Application teams declare ServiceNow CSDM objects in **`servicenow/csdm.yaml`** under their playbook directory (for example `ansible/playbooks/spark/servicenow/csdm.yaml`). The central deploy playbook at `playbooks/servicenow/csdm/deploy.yml` reads an explicit list of specification files and creates or updates CMDB records, relationships, entry points (vertical only), and Service Mapping discovery triggers.

See **[docs/CSDM_Specifications.md](docs/CSDM_Specifications.md)** for the full TPG: roles (**CSDM Modeler**, deploy processor), platform Service Mapping guidance, attribute tables, runtime tags, and vertical discovery prerequisites.

## Roles

| Role | Responsibility |
|------|----------------|
| **CSDM Modeler** | Authors `csdm.yaml` — hierarchy, platforms, `service_mapping`, tags, `depends_on` |
| **Deploy processor maintainer** | Generic automation in `csdm/tasks/` and registry in `csdm/common/vars.yml` |
| **Discovery operator** | Horizontal Discovery, KVA, Docker Pattern |
| **Service Mapping operator** | Tag-based SM rules on the instance |

## Quick start

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/deploy.yml \
  -e @../vars/secrets.yaml
```

Vertical discovery is **triggered asynchronously** only when `service_mapping: vertical` and `discover: true`. Tag-based services do **not** trigger vertical discovery.

**Tag-based Service Mapping (instance UI):** see **[docs/Tag_Based_Service_Mapping.md](docs/Tag_Based_Service_Mapping.md)** — which application services, tag categories, and UI paths.

Check status:

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/diagnose.yml \
  -e @../vars/secrets.yaml
```

## Adding an application

1. Create `ansible/playbooks/<app>/servicenow/csdm.yaml` following `docs/CSDM_Specifications.md` (CSDM Modeler perspective).
2. Add the path (relative to `ansible/playbooks/`) to `sn_csdm_spec_files` in `csdm/common/vars.yml`.
3. Apply runtime labels on workloads to match the specification.
4. Run `csdm/deploy.yml`.

To remove objects, set `csdm_op: delete` on entries in `csdm.yaml`. See `docs/CSDM_Specifications.md` — **csdm_op**.

Synthetic insert/delete examples: `csdm/test/servicenow_insert.yaml` and `csdm/test/servicenow_delete.yaml`.

Shared infrastructure values (instance URL, hostnames, ports used by multiple stacks) belong in `vars/variables.yaml` and are referenced from specifications via Jinja (`{{ SPARK_MASTER_HOST }}`). Application-only CSDM names and descriptions belong in `csdm.yaml`, not in `variables.yaml`.

## Service Mapping by platform

| Platform | Recommended | Vertical discovery |
|----------|-------------|-------------------|
| Kubernetes | Tag-based | **Must not** |
| Docker Compose | Tag-based | **May** (optional; rarely worth it) |
| Host | Tag-based or vertical | **May** |
| SaaS | Manual | **Must not** |

Full normative guidance: `docs/CSDM_Specifications.md` Statement 1.
