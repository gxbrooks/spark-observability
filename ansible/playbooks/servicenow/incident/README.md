# Log-to-Incident ServiceNow automation playbooks

Deploy Dynatrace (SGC / **SGO-Dynatrace**) → Event Management → ITSM using:
OpenPipeline `sn-*` tags → Tag-Based Alert Clustering →
**EvtMgmtIncidentHandler** / **EvtMgmtCustomIncidentPopulator**
(incident CI = **service instance**). Bind BRs are inactive.

## Create path (AMR + Create incident from Alert)

Target: AMR **L2I Create Incident CRITICAL_LOG_EVENT** → Flow action
**Create incident from Alert** → `EvtMgmtIncidentHandler` →
`EvtMgmtCustomIncidentPopulator` (SI + `sn-log-signature`).

Interim: BR `em-alert-create-log-incident` (after insert/update) calls
`EvtMgmtIncidentHandler.createIncidentNoUpdate(alert, false)` — same
populator path as the Flow action. `autoOpen=false` is required while the
L2I AMR is inactive (`autoOpen=true` demands a matching `em_alert_rule`).
AMR stays **inactive** to avoid the OOTB Create Incident subflow (skips populator).
Deactivate the BR when an admin publishes the Flow and activates the AMR.

## Why dash keys (`sn-log-signature`) not dots (`sn.log.signature`)

TBAC reads `additional_info` via a **dot-path** into JSON, e.g.
`ProblemDetailsJSON.rankedEvents[0].customProperties.sn-log-signature`.
Each `.` is a nested-object step. Flat Davis keys that themselves contain
dots (e.g. `sn.log.signature`) cannot be resolved by that walk. Dashes keep
the path segment atomic while remaining readable.

## Playbooks

| Playbook | Purpose |
| -------- | ------- |
| `deploy.yml` | Upsert Script Includes, handler shim BR, TBAC; deactivate bind BRs + OOTB AMRs |
| `verify_log_incident_bindings.yml` | Assert recent SGO-Dynatrace events/alerts |
| `diagnose.yml` | Open SGO-Dynatrace alerts, log incidents; optional alert↔incident lookup |

## Active artifacts (after deploy)

| Name | Role |
| ---- | ---- |
| `ResolveApplicationService` | SI resolve helpers (`sn-service_instance`, `k8s.pod.name`, …) |
| `EvtMgmtCustomIncidentPopulator` | L2I: incident CI = SI; correlate by SI + `sn-log-signature` |
| `L2IIncidentFromAlert` | Helper → `EvtMgmtIncidentHandler` (job / reprocess) |
| BR `em-alert-create-log-incident` | Shim → `EvtMgmtIncidentHandler.createIncidentNoUpdate` |
| TBAC `L2I short Log4j2 SI + signature` | Groups on `sn-environment` + `sn-service_instance` + `sn-log-signature` |
| AMR `L2I Create Incident CRITICAL_LOG_EVENT` | **Inactive** (activate with published Create-incident-from-Alert Flow) |
| OOTB `Create Incident for Primary Alert` / `SGO-Dynatrace` | **Inactive** |
| Bind / propagate BRs | **Inactive** |

## OpenPipeline tags (must be present on Davis events)

| Tag | Purpose |
| --- | ------- |
| `sn-event_kind=CRITICAL_LOG_EVENT` | Gate for incident create |
| `sn-log-signature` | Class:Line clustering / incident short description |
| `sn-log-class` / `sn-log-line` | Parsed parts |
| `sn-environment` | Partition (no cross-env grouping) |
| `sn-service_instance` | Service instance clustering / resolve key |
| `sn-pipeline` | OpenPipeline customId |
| `k8s.pod.name` | K8s bind key (unchanged) |

Standalone custom log source still stamps OneAgent `service_instance`; OpenPipeline maps it to `sn-service_instance`.

## Usage

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/incident/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/deploy.yml -e @../vars/secrets.yaml
```
