# Phase 4 — Dynatrace SGC + event integration

Automates **Dynatrace-side** alerting and ServiceNow webhook configuration for brooks-lab.
ServiceNow Store apps (SGC) must be installed on the instance before CMDB topology import.

## Prerequisites (ServiceNow instance)

Install from **ServiceNow Store** in order:

1. Observability Commons for CMDB (`sn_observability`)
2. Integrations Commons for CMDB (`sn_cmdb_int_util`)
3. CMDB CI Class Model (`sn_cmdb_ci_class`)
4. Event Management (`sn_em_ai`)
5. **Service Graph Connector for Observability – Dynatrace** (`sn_dynatrace_integ`)

Complete **Guided Setup** under **Dynatrace Observability → Setup** (connection, filters, scheduled imports, notification payload template).

Grant `admin_brooks_lab` **`event_management_admin`** (or em_event read) for API validation of `em_event` rows.

## Playbooks

```bash
cd ansible

# CMDB / SGC state
ansible-playbook -i inventory.yml playbooks/servicenow/cmdb/diagnose.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/cmdb/deploy.yml -e @../vars/secrets.yaml

# Dynatrace → ServiceNow events (CPU >80%, Spark ERROR logs)
ansible-playbook -i inventory.yml playbooks/servicenow/cmdb/events/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/cmdb/events/diagnose.yml -e @../vars/secrets.yaml

# After running Spark chapters
ansible-playbook -i inventory.yml playbooks/servicenow/cmdb/events/test.yml -e @../vars/secrets.yaml
```

## Design references

- `tmp/Dynatrace-ServiceNow SGC.md` — SGC architecture, object mapping, known issues
- `tmp/Dynatrace-ServiceNow-events.md` — event path and validation
- `tmp/ServiceNow_Dynatrace_Integration.md` — overall CMDB policy

Phase 1–3 Discovery lives in `../discovery/`.
