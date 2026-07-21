# Log-to-Incident ServiceNow automation playbooks

Deploy and validate K8s application log → Dynatrace → ServiceNow Event Management → ITSM incident automation.

## Playbooks

| Playbook | Purpose |
| -------- | ------- |
| `deploy.yml` | Deploy `K8sLogPodCiBind`, `ResolveApplicationService` (incl. Spark Client alert bind), and business rules |
| `verify_log_incident_bindings.yml` | Assert recent SGO-Dynatrace events have pod CI and log path resource |
| `diagnose.yml` | Open alerts, log incidents, business rules, legacy `source=Dynatrace` alerts; optional alert↔incident lookup |
| `reprocess_spark_log_events.yml` | Re-run pod CI binding on existing `em_event` rows (after-update BR) |
| `reprocess_spark_log_alerts.yml` | Re-run pod CI binding on existing `em_alert` rows |

## Usage

```bash
cd ansible

# Deploy automation to ServiceNow
ansible-playbook -i inventory.yml playbooks/servicenow/incident/deploy.yml -e @../vars/secrets.yaml

# Verify recent pipeline (after chapter run or synthetic log)
ansible-playbook -i inventory.yml playbooks/servicenow/incident/verify_log_incident_bindings.yml -e @../vars/secrets.yaml

# Diagnose a specific alert and find its incident
ansible-playbook -i inventory.yml playbooks/servicenow/incident/diagnose.yml -e @../vars/secrets.yaml \
  -e spark_alert_number=Alert0014216

# Reprocess historical rows after BR or enrichment changes
ansible-playbook -i inventory.yml playbooks/servicenow/incident/reprocess_spark_log_events.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/incident/reprocess_spark_log_alerts.yml -e @../vars/secrets.yaml
```

## Finding the incident for an alert

ServiceNow links alerts to incidents through **`em_alert.incident`** on optimizincdemo1 (reference to the incident record). That populates the incident **Alerts** tab. Incidents created before the business rule set this field may only appear in **Comments** / **Work notes**. Search **Incidents** with:
- **Short description** = `Event Log WARN` or `Event Log ERROR` with matching **Created** time.

Use `diagnose.yml` with `-e spark_alert_number=Alert00…` to query via the Table API.
