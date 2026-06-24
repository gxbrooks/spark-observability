# ServiceNow automation

Ansible playbooks for ServiceNow integration. Configuration is applied to the
ServiceNow instance via REST Table API from the control node; host-side
components (Discovery SSH account, MID Server) run on lab hosts per
`ansible/inventory.yml`.

## Layout

| Directory | Purpose |
| --------- | ------- |
| `discovery/` | Phases 1–3: MID Server, Discovery credentials, schedules, on-demand scans, K8s/Docker discovery |
| `cmdb/` | CMDB 360 (Multisource CMDB): license check, sys_properties, diagnose |
| `sgc/` | Phase 4: Service Graph Connector + event integration. `install.yml` installs required Store apps/plugins; `sources/<source>/` holds per-source (currently `dynatrace/`) configuration, including `sources/dynatrace/events/` for the alerting webhook |
| *(future)* `incident/` | Incident integrations |

Top-level orchestrators: `install.yml`, `deploy.yml`, `start.yml`, `diagnose.yml`, `compare.yml`
(import child playbooks in order). Global playbooks import these with tag
`servicenow` (use `--skip-tags servicenow` to omit).

`sgc/sources/` is organized by **observability source** (one subdirectory per
SGC/event source). Dynatrace is the only source today; additional sources get
sibling directories.

## Variables and secrets

**Non-secret** ServiceNow settings live in `vars/variables.yaml` under the
**`service-now`** context. Playbooks load the generated flat file
`vars/contexts/servicenow_ansible_vars.yml` (regenerated automatically on
`deploy.yml`, `install.yml`, etc.).

| Variable | Where | Purpose |
| -------- | ----- | ------- |
| `SN_URL` | `variables.yaml` → service-now context | Instance base URL |
| `SN_MID_INSTALLER_DEB_URL` | `variables.yaml` → service-now context | Linux MID `.deb` (must match instance build) |
| `SN_LAB_LOCATION_NAME`, subnet, MID name, … | `variables.yaml` → service-now context | brooks-lab Discovery scope |

**Secrets** — `vars/secrets.yaml` → `servicenow:` block:

- `SN_USER`, `SN_PASSWORD` — API automation user (`admin_brooks_lab`)
- `SN_MID_USER`, `SN_MID_PASSWORD` — MID Server user (`mid_brooks_lab`, **`mid_server` role only**)

Full prerequisite checklist: **`docs/install.md`**

SSH discovery private key is generated on first `discovery/install.yml` run and
stored at `vars/sn_discovery_id_ed25519` (gitignored).

## Entry points

```bash
cd ansible

# Full ServiceNow stack (or run individual playbooks below)
ansible-playbook -i inventory.yml playbooks/servicenow/install.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/discover.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/start.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/diagnose.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/compare.yml -e @../vars/secrets.yaml

# CSDM deploy and compare process: playbooks/servicenow/docs/DT_CN_Comparison_Process.md

# Phase 1 — Discovery only
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/install.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/deploy.yml -e @../vars/secrets.yaml

# CMDB 360 (Multisource CMDB)
ansible-playbook -i inventory.yml playbooks/servicenow/cmdb/deploy.yml -e @../vars/secrets.yaml
```

## ServiceNow users (two required)

| User | Secrets key | Roles | Used for |
| ---- | ----------- | ----- | -------- |
| `admin_brooks_lab` | `SN_USER` | discovery_admin, cmdb_inst_admin, rest_service, … | Ansible `deploy.yml` / `discover.yml` |
| `mid_brooks_lab` | `SN_MID_USER` | **mid_server** only | MID Server agent on Lab3 |

The MID user **cannot** replace the admin user for Phase 1. See `docs/install.md`.

Run `discovery/diagnose.yml` for a live permission matrix.

## References

- Design: `tmp/ServiceNow_Dynatrace_Integration.md`
- Implementation log: `tmp/20260603_0950_ServiceNow_Dynatrace_Implementation_Notes.md`
- Lab topology: `docs/architecture-and-resources.md`
