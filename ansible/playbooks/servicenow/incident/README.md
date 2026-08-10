# Log-to-Incident ServiceNow automation playbooks

Deploy and validate Dynatrace (SGC / **SGO-Dynatrace**) → Event Management → ITSM incident automation using **generic entity → CI** binding.

Playbooks under `tasks/ensure_*.yml` **upsert ServiceNow artifacts** (Script Includes, Business Rules). Those artifacts perform bind/create at runtime; the playbooks do not insert events, alerts, or incidents directly.

## Playbooks

| Playbook | Purpose |
| -------- | ------- |
| `deploy.yml` | Upsert `ResolveApplicationService` and generic SGO-Dynatrace BRs; deactivate legacy K8s/Spark BRs + OOTB AMR |
| `verify_log_incident_bindings.yml` | Assert recent SGO-Dynatrace events have service instance / host CI |
| `diagnose.yml` | Open SGO-Dynatrace alerts, log incidents, business rules; optional alert↔incident lookup |
| `reprocess_spark_log_events.yml` | Touch existing `em_event` rows to re-run entity bind BR |
| `reprocess_spark_log_alerts.yml` | Touch existing `em_alert` rows to re-run entity bind BR |

## Active artifacts (after deploy)

| Name | Role |
| ---- | ---- |
| `ResolveApplicationService` | Generic bind: `service_instance`→SI; `k8s.pod.name`→pod→SI; else HOST/CAI; remaps type via `log.event_kind` |
| `em-event-bind-entity-ci` | Before insert/update on `em_event` (order 5000) |
| `em-alert-bind-entity-ci` | Before insert/update on `em_alert` (order 5010); keeps existing `cmdb_ci` if set |
| `em-alert-create-log-incident` | Before insert/update on `em_alert` (order 5020); prefers alert CI else rebinds |
| `em-event-propagate-entity-ci` | **Inactive** (former event→alert propagate safety net) |
| OOTB AMR `SGO-Dynatrace` | **Inactive** |

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
- **Short description** = `Critical log event` with matching **Created** time.

Use `diagnose.yml` with `-e spark_alert_number=Alert00…` to query via the Table API.

Incidents created by `em-alert-create-log-incident` use short description **Critical log event** and require a bound `cmdb_ci` on the alert first.
