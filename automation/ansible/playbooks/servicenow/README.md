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
| `csdm/` | Thin wrappers around **sn-sync** (`deploy.yml` / `undeploy.yml` / `diagnose.yml`) |
| `sgc/` | Phase 4: Service Graph Connector + event integration. `install.yml` installs required Store apps/plugins; `sources/<source>/` holds per-source (currently `dynatrace/`) configuration, including `sources/dynatrace/events/` for the alerting webhook |
| *(future)* `incident/` | Incident integrations |

Top-level orchestrators: `install.yml`, `deploy.yml`, `start.yml`, `diagnose.yml`
(import child playbooks in order; `diagnose.yml` also reports which instance owns
each lab component and fails at its end when no instance is fully active), plus
`stop.yml` (stop feeding the active instance). Global playbooks import these with tag
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
| `SN_INSTANCES` | `variables.yaml` → service-now context | Instance registry, one entry per `id` (`demo1`, `demo3`): `url`, `secrets_suffix`, `mid_server_name`, `mid_installer_deb_url` (used only when Lab3 has no MID, or with `-e sn_mid_switch_method=reinstall`), `dt_problem_notification_name`, `dt_sgc_api_token_name` |
| `SN_URL` | `variables.yaml` → service-now context | Demo1 URL. Playbooks use `SN_INSTANCES.<id>.url`; the non-Ansible tools (`servicenow/comparator`, `create-sn-change-window.py`) derive the active instance with `servicenow/sn_active_instance.py` (`SN_TARGET=<id>` overrides) |
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

brooks-lab feeds **one** ServiceNow instance at a time, the **active instance**
(Demo1 or Demo3). Nothing records it: every run **derives** it from the Lab3 MID
(`config.xml` `url` and service running), the enabled brooks-lab Dynatrace
problem notification, and the KVA informer Helm release (`instance.name`,
replicas). An instance is active only when all three agree; `diagnose.yml` is the
consistency check and fails at its end otherwise. Every ServiceNow playbook takes:

| Value | Effect |
| ----- | ------ |
| *(omitted)* | The active instance; in `switch` and `any` mode, else the MID's owner (e.g. after `stop.yml`) |
| `demo1` / `demo3` | That instance |
| `all` | Rejected |

[`tasks/target.yml`](tasks/target.yml) is the first `import_playbook` of every
ServiceNow playbook. The importing playbook sets its mode:

| Mode | Playbooks | Behaviour |
| ---- | --------- | --------- |
| `switch` | every `install.yml`, `deploy.yml`, `start.yml` | Switch the lab to the target first: disable the other instances' brooks-lab Dynatrace problem notifications, **reconfigure** the Lab3 MID for the target if another instance owns it (it then auto-upgrades to the target's build; install only when Lab3 has no MID or with `-e sn_mid_switch_method=reinstall`), repoint the KVA informer via Helm (or park it at 0 replicas when the target lacks the Kubernetes Visibility Agent app), make sure the MID's signing key is active and the MID validated, enable the target's notification. No change when everything already points at the target. |
| `active` | every `test.yml` | Require a consistent active instance (fail listing the inconsistencies otherwise) and fail when `-e target` names another instance. |
| `any` | every `diagnose.yml`, `csdm/undeploy.yml`, `stop.yml`, `discovery/stop.yml` | Either instance; inconsistencies are reported as an ignored ERROR and the playbook continues; a note when the target is not active. |

Resolution and activation happen once per run, so aggregators such as
`servicenow/deploy.yml` or the whole-lab `playbooks/deploy.yml` switch once.
`sgc/sources/dynatrace/events/deploy.yml --tags openpipeline` (only the
Dynatrace OpenPipeline log alerts) also runs the guard, though it changes only
the Dynatrace tenant.

`incident/deploy.yml` runs on whichever instance is active (Demo3 included). It
changes instance-wide Event Management settings, which stay on an instance after
a switch away.

Design and status: [Multi_Target_ServiceNow.md](../../../../specifications/servicenow/docs/Multi_Target_ServiceNow.md).

Full prerequisite checklist: **[specifications/servicenow/docs/install.md](../../../../specifications/servicenow/docs/install.md)**

SSH discovery private key is generated on first `discovery/install.yml` run and
stored at `vars/sn_discovery_id_ed25519` (gitignored).

## Entry points

```bash
cd automation/ansible

# Every command below takes -e target=demo1|demo3 (default: the active instance).
# install/deploy/start with another target switch the lab to that instance.
ansible-playbook -i inventory.yml playbooks/servicenow/diagnose.yml
# Full ServiceNow stack (or run individual playbooks below)
ansible-playbook -i inventory.yml playbooks/servicenow/install.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/start.yml --tags discovery_scan -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/start.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/diagnose.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/stop.yml -e @../vars/secrets.yaml
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
| `mid_brooks_lab` | `SN_MID_USER<suffix>` | **mid_server** only | MID Server agent on Lab3 (one MID, owned by the active instance) |

Each instance has its own pair of users (separate passwords). Lab3 runs one MID
(`/opt/servicenow/mid/agent`, unit `mid_brooks_lab3`), registered with the active
instance as `mid-brooks-lab3` (Demo1) or `mid-brooks-lab3-demo3` (Demo3). A switch
reconfigures it for the target (`config.xml` url, user, password, name) and the
MID auto-upgrades to the target's build; see
[Multi_Target_ServiceNow.md](../../../../specifications/servicenow/docs/Multi_Target_ServiceNow.md).

The MID user **cannot** replace the admin user for Phase 1. See [specifications/servicenow/docs/install.md](../../../../specifications/servicenow/docs/install.md).

Run `discovery/diagnose.yml` for a live permission matrix.

## References

- Design: `tmp/ServiceNow_Dynatrace_Integration.md`
- Implementation log: `tmp/20260603_0950_ServiceNow_Dynatrace_Implementation_Notes.md`
- Lab topology: `docs/architecture-and-resources.md`
