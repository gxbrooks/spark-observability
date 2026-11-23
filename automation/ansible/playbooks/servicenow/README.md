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
| `service-mapping/` | Tag-based Service Mapping: Store apps, classic plugin, Scripted REST (`/populate_tags`) |
| `csdm/` | Thin wrappers around **sn-sync** (`deploy.yml` / `delete.yml` / `diagnose.yml`) |
| `sgc/` | Phase 4: Service Graph Connector + event integration. `install.yml` installs required Store apps/plugins; `sources/<source>/` holds per-source (currently `dynatrace/`) configuration, including `sources/dynatrace/events/` for the alerting webhook |
| *(future)* `incident/` | Incident integrations |

Top-level orchestrators: `install.yml`, `deploy.yml`, `start.yml`, `diagnose.yml`
(import child playbooks in order). Global playbooks import these with tag
`servicenow` (use `--skip-tags servicenow` to omit).

**Model compare** is implemented in Python: `servicenow/comparator/` (see README there).

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
| `SN_INSTANCES` | `variables.yaml` → service-now context | Instance registry, one entry per `id` (`demo1`, `demo3`): `url`, `secrets_suffix`, MID name/service/dir, `mid_installer_deb_url` (must match the instance build), `dt_problem_notification_name`, `dt_sgc_api_token_name`, `dt_legacy_connector_sys_id`, `incident_deploy_enabled` |
| `SN_DEFAULT_TARGET` | `variables.yaml` → service-now context | Instance used when `-e target` is omitted (`demo3`) |
| `SN_URL` | `variables.yaml` → service-now context | Demo1 URL, read only by the non-Ansible tools (`servicenow/comparator`, `create-sn-change-window.py`); playbooks use `SN_INSTANCES.<id>.url` |
| `SN_LAB_LOCATION_NAME`, subnet, schedule, … | `variables.yaml` → service-now context | brooks-lab Discovery scope (same on every instance) |

**Secrets** — `vars/secrets.yaml` → `servicenow:` block. Each instance's keys
carry its `secrets_suffix` (none for `demo1`, `_DEMO3` for `demo3`):

- `SN_USER<suffix>`, `SN_PASSWORD<suffix>` — API automation user (`admin_brooks_lab`)
- `SN_MID_USER<suffix>`, `SN_MID_PASSWORD<suffix>` — MID Server user (`mid_brooks_lab`, **`mid_server` role only**)
- `SN_DT_WEBHOOK_USER<suffix>`, `SN_DT_WEBHOOK_PASSWORD<suffix>` — written by `sgc/sources/dynatrace/events/deploy.yml`

**Per-instance deploy facts** (gitignored, written by deploy playbooks):
`vars/contexts/servicenow_discovery_deploy_<id>.json`,
`servicenow_k8s_discovery_deploy_<id>.json`, `servicenow_sm_deploy_<id>.json`.

## Target instance (`-e target=`)

brooks-lab feeds several ServiceNow instances at once (Demo1 and Demo3). Every
ServiceNow playbook takes:

| Value | Effect |
| ----- | ------ |
| *(omitted)* | `SN_DEFAULT_TARGET` — **`demo3`** |
| `demo1` / `demo3` | That instance only |
| `all` | Every `SN_INSTANCES` entry. This process runs the first entry (`demo1`); [`common/target.yml`](common/target.yml) first runs the same ServiceNow playbook as a child `ansible-playbook -e target=<id>` for each remaining entry (same inventory, extra vars, tags, verbosity, `--check`/`--diff`). Child logs: `automation/ansible/tmp/sn-target-<playbook>-<id>-<timestamp>.log`. A failed child stops the run before the first entry runs. |

`common/target.yml` is the first `import_playbook` of every ServiceNow
playbook. It validates `target` and fans out **once per run** (the outermost
ServiceNow playbook), so aggregators such as `servicenow/deploy.yml` or the
whole-lab `playbooks/deploy.yml` re-run only the ServiceNow playbook per
instance, never the whole lab. Two playbooks have no guard because they don't
touch ServiceNow: `discovery/k8s/label_oneagent_pods.yml` and
`sgc/sources/dynatrace/events/apply_openpipeline_only.yml`.

`incident/deploy.yml` changes instance-wide Event Management settings, so it
**skips** any instance whose `incident_deploy_enabled` is `false` (Demo3 today:
its EM is shared with other teams).

Design and status: [Multi_Instance_Plan.md](../../../../specifications/servicenow/docs/Multi_Instance_Plan.md).

Full prerequisite checklist: **[specifications/servicenow/docs/install.md](../../../../specifications/servicenow/docs/install.md)**

SSH discovery private key is generated on first `discovery/install.yml` run and
stored at `vars/sn_discovery_id_ed25519` (gitignored).

## Entry points

```bash
cd automation/ansible

# Every command below takes -e target=demo1|demo3|all (default demo3).
# Full ServiceNow stack (or run individual playbooks below)
ansible-playbook -i inventory.yml playbooks/servicenow/install.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/discover.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/start.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/diagnose.yml -e @../vars/secrets.yaml -e target=all
# Model compare (Python — from repo root)
# PYTHONPATH=. python -m servicenow.comparator

# CSDM model (requires sn-sync-inject on PATH)
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/diagnose.yml -e @../vars/secrets.yaml
# Compare process: specifications/servicenow/docs/DT_SN_Comparison_Process.md

# Phase 1 — Discovery only
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/install.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/deploy.yml -e @../vars/secrets.yaml

# CMDB 360 (Multisource CMDB)
ansible-playbook -i inventory.yml playbooks/servicenow/cmdb/deploy.yml -e @../vars/secrets.yaml
```

## ServiceNow users (two required)

| User | Secrets key | Roles | Used for |
| ---- | ----------- | ----- | -------- |
| `admin_brooks_lab` | `SN_USER<suffix>` | `admin` on Demo1 and Demo3 (or discovery_admin, cmdb_inst_admin, rest_service, …) | Ansible `deploy.yml` / `discover.yml` |
| `mid_brooks_lab` | `SN_MID_USER<suffix>` | **mid_server** only | MID Server agent on Lab3 (one MID per instance) |

Each instance has its own pair of users (separate passwords). Lab3 runs one MID
per instance: `mid-brooks-lab3` (Demo1, `/opt/servicenow/mid/agent`) and
`mid-brooks-lab3-demo3` (Demo3, `/opt/servicenow/mid-demo3/agent`).

The MID user **cannot** replace the admin user for Phase 1. See [specifications/servicenow/docs/install.md](../../../../specifications/servicenow/docs/install.md).

Run `discovery/diagnose.yml` for a live permission matrix.

## References

- Design: `tmp/ServiceNow_Dynatrace_Integration.md`
- Implementation log: `tmp/20260603_0950_ServiceNow_Dynatrace_Implementation_Notes.md`
- Lab topology: `docs/architecture-and-resources.md`
