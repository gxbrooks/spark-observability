# CSDM object specifications

Application teams declare ServiceNow CSDM objects in **`servicenow/servicenow.yaml`** under their playbook directory (for example `ansible/playbooks/spark/servicenow/servicenow.yaml`). The central deploy playbook at `playbooks/servicenow/csdm/deploy.yml` reads an explicit list of specification files and creates or updates CMDB records, relationships, entry points, and Service Mapping discovery triggers.

See **[docs/Specifications.md](docs/Specifications.md)** for the specification format, attribute meanings, and examples.

## Quick start

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/deploy.yml \
  -e @../vars/secrets.yaml
```

Vertical (Service Mapping) discovery is **triggered asynchronously** — the deploy playbook does not wait for maps to finish. Check progress with:

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/diagnose.yml \
  -e @../vars/secrets.yaml
```

## Adding an application

1. Create `ansible/playbooks/<app>/servicenow/servicenow.yaml` following `docs/Specifications.md`.
2. Add the path (relative to `ansible/playbooks/`) to `sn_csdm_spec_files` in `csdm/common/vars.yml`.
3. Run `csdm/deploy.yml`.

Shared infrastructure values (instance URL, hostnames, ports used by multiple stacks) belong in `vars/variables.yaml` and are referenced from specifications via Jinja (`{{ SPARK_MASTER_HOST }}`). Application-only CSDM names and descriptions belong in `servicenow.yaml`, not in `variables.yaml`.

## Service Mapping discovery

| Step | Mechanism |
|------|-----------|
| Register entry points + CSDM hierarchy | `csdm/deploy.yml` (Table API) |
| Trigger top-down discovery | Service Mapping Operations REST API (`SNC.BusinessServiceManager`) |
| Check status | `csdm/diagnose.yml` (`process_status`, `service_status`, entry points) |

Discovery runs server-side and may take many minutes per application service at scale.
