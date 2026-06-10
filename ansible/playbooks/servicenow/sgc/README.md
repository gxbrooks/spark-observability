# Phase 4 — Service Graph Connector (SGC) + event integration

Automates installation of the ServiceNow Store applications required for the
**Service Graph Connector for Observability – Dynatrace**, and the
**Dynatrace-side** alerting and ServiceNow webhook configuration for brooks-lab.

## Organization

| Path | Purpose |
| ---- | ------- |
| `install.yml` | Install required Store apps + plugins (`common/store_apps.yml`) via CI/CD App Repo Install (by scope) / plugin activation |
| `deploy.yml` | Instance-side SGC validation; reminds operator to run scheduled imports |
| `diagnose.yml` | Component versions (installed vs pinned vs latest), SGC state, CMDB merge state |
| `common/` | Shared vars and reusable tasks (`check_store_apps.yml`, `poll_cicd_progress.yml`) |
| `sources/dynatrace/` | All Dynatrace-specific configuration for the SGC and events |
| `sources/dynatrace/events/` | Dynatrace → ServiceNow event playbooks (deploy / diagnose / test) |
| `sources/dynatrace/tasks/`, `files/` | Dynatrace task fragments and JSON payload templates |

Future SGC or event **sources** (e.g. another APM) get their own directory
under `sources/`. CMDB-specific configuration beyond the SGC (none today)
would live in a `cmdb/` subdirectory.

## Behavior guarantees

Per `standards/automation.md`:

- **Idempotent** — rerunning any playbook has no ill effects.
- **On-needed** — playbooks check current state first and skip actions that are
  already in place (apps already installed, Dynatrace settings objects already
  matching). Where the API cannot report state (e.g. `sys_plugins` is not
  readable by the automation user), the playbook emits an informational message
  that the action is being redone.
- **Version pinning** — required apps and pinned versions live in
  `common/store_apps.yml` (`sn_store_apps`; local to sgc because only these
  playbooks consume it). `diagnose.yml` reports installed vs pinned vs
  latest-available versions. `install.yml` warns on pin drift but does not
  upgrade apps on the shared instance.

## Variables

Context variables come **only** from `vars/variables.yaml` (single source of
truth) via the generated `vars/contexts/servicenow_ansible_vars.yml` and
`dynatrace_ansible_vars.yml`. Playbooks do **not** default context variables —
a missing variable fails the play. Secrets: `vars/secrets.yaml` → `servicenow:`.

Key context variables: `SN_URL`, `SN_DT_LEGACY_CONNECTOR_SYS_ID`,
`DT_API_URL`, `DT_API_TOKEN`, `DT_MANAGEMENT_ZONE`. The Store app manifest
(`sn_store_apps`) is sgc-local in `common/store_apps.yml`.

## Playbooks

```bash
cd ansible

# 0. Store apps + plugins (idempotent; skips what is installed)
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/install.yml -e @../vars/secrets.yaml

# 1. Component versions / SGC / CMDB state
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/diagnose.yml -e @../vars/secrets.yaml

# 2. Instance-side SGC validation
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/deploy.yml -e @../vars/secrets.yaml

# 3. Dynatrace → ServiceNow events (CPU >80%, Spark ERROR logs)
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/diagnose.yml -e @../vars/secrets.yaml

# 4. After running Spark chapters
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/test.yml -e @../vars/secrets.yaml
```

## Preconditions

- `install.yml` automation path requires `admin_brooks_lab` to have
  **`sn_cicd.sys_ci_automation`** (CI/CD App Repo Install + plugin activation).
  When components need installing, a bootstrap preflight
  (`common/check_cicd_bootstrap.yml`) checks that the role record exists
  (i.e. the CI/CD tooling is on the instance) and that the automation user
  holds it, and fails fast naming the exact missing manual step. Perform the
  step and re-run — completed work is skipped. The role can only be granted
  once the CI/CD tooling exists; on a bare instance, activating
  `com.snc.ci_cd` (manual) precedes the grant. See `../docs/install.md` §7
  "Bootstrap sequence".
- Guided Setup (connection, filters, scheduled imports, notification payload
  template) is **manual** — see `../docs/install.md` §7.
- Grant `admin_brooks_lab` **`evt_mgmt_admin`** (or `em_event` read)
  for API validation of `em_event` rows.

## Design references

- `tmp/Dynatrace-ServiceNow SGC.md` — SGC architecture, object mapping, known issues
- `tmp/Dynatrace-ServiceNow-events.md` — event path and validation
- `../docs/install.md` §7 — prerequisites, manual install steps, Guided Setup

Phase 1–3 Discovery lives in `../discovery/`.
