# CMDB 360 (Multisource CMDB)

Ansible playbooks to enable **CMDB 360** (formerly Multisource CMDB) on the
ServiceNow instance. CMDB 360 tracks which discovery source proposed each CI
attribute when IRE merges updates from Discovery, SGC, KVA, and other sources.

## Playbooks

| Playbook | Purpose |
| -------- | ------- |
| `deploy.yml` | Verify ITOM Discovery license via CI/CD activate API (non-fatal warn), set CMDB 360 sys_properties |
| `diagnose.yml` | License state, sys_properties, sample `cmdb_multisource_data` rows |

## Prerequisites

- `admin_brooks_lab` with `cmdb_inst_admin` (sys_properties) and ideally
  `sn_cicd.sys_ci_automation` (plugin activation API)
- ITOM Discovery entitlement on the instance (`com.snc.itom.discovery.license`)

See [servicenow/docs/install.md](../../../../servicenow/docs/install.md) §7 for roles and bootstrap.

## Usage

```bash
cd ansible

ansible-playbook -i inventory.yml playbooks/servicenow/cmdb/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/cmdb/diagnose.yml -e @../vars/secrets.yaml
```

## Typical brooks-lab sequence

After `cmdb/deploy.yml`:

1. `discovery/discover.yml` — CI Discovery scan (IRE-populated CIs)
2. `sgc/sources/dynatrace/start.yml` — SGO-Dynatrace import cascade

Or use the top-level orchestrator: `playbooks/servicenow/start.yml`.
