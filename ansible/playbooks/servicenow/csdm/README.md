# CSDM deploy automation

Ansible playbooks here **apply** ServiceNow CSDM specifications; the specifications themselves live under **`servicenow/regions/`** at the repository root (see [servicenow/README.md](../../../../servicenow/README.md)).

See **[servicenow/docs/CSDM_Specifications.md](../../../../servicenow/docs/CSDM_Specifications.md)** for the full TPG: roles (**CSDM Modeler**, deploy processor), platform Service Mapping guidance, attribute tables, runtime tags, and vertical discovery prerequisites.

## Roles

| Role | Responsibility |
|------|----------------|
| **CSDM Modeler** | Authors `{stack}.csdm.yaml` under a management region |
| **Deploy processor maintainer** | Generic automation in `csdm/tasks/` |
| **Discovery operator** | Horizontal Discovery, KVA, Docker Pattern |
| **Service Mapping operator** | Tag-based SM rules on the instance |

## Quick start

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/deploy.yml \
  -e @../vars/secrets.yaml
```

Deploy discovers all `servicenow/regions/*/region.yaml` files and applies listed CSDM specs. Limit to one region: `-e sn_region_filter=brooks-lab`.

When specs live outside Git: `-e sn_specs_root_override=/path/to/servicenow`.

Vertical discovery is **triggered asynchronously** only when `service_mapping: vertical` and `discover: true`. Tag-based services do **not** trigger vertical discovery.

**Tag-based Service Mapping (instance UI):** see **[servicenow/docs/Tag_Based_Service_Mapping.md](../../../../servicenow/docs/Tag_Based_Service_Mapping.md)**.

Check status:

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/diagnose.yml \
  -e @../vars/secrets.yaml
```

## Adding a stack to a management region

1. Create `servicenow/regions/{region-id}/{name}.csdm.yaml` following `servicenow/docs/CSDM_Specifications.md`.
2. Add the filename to `csdm_specs` in that region's `region.yaml`.
3. Apply runtime labels on workloads to match the specification.
4. Run `csdm/deploy.yml`.

To remove objects, set `csdm_op: delete` on entries in the CSDM file. See `servicenow/docs/CSDM_Specifications.md` — **csdm_op**.

Synthetic insert/delete examples: `csdm/test/servicenow_insert.yaml` and `csdm/test/servicenow_delete.yaml`.

Shared infrastructure values (instance URL, hostnames, ports used by multiple stacks) belong in `vars/variables.yaml` and are referenced from specifications via Jinja (`{{ SPARK_MASTER_HOST }}`). Application-only CSDM names and descriptions belong in `*.csdm.yaml`, not in `variables.yaml`.

## Service Mapping by platform

| Platform | Recommended | Vertical discovery |
|----------|-------------|-------------------|
| Kubernetes | Tag-based | **Must not** |
| Docker Compose | Tag-based | **May** (optional; rarely worth it) |
| Host | Tag-based or vertical | **May** |
| SaaS | Manual | **Must not** |

Full normative guidance: `servicenow/docs/CSDM_Specifications.md` Statement 1.
