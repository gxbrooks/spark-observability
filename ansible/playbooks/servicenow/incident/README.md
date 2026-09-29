# Log-to-Incident ServiceNow automation playbooks

Deploy Dynatrace (SGC / **SGO-Dynatrace**) → Event Management → ITSM using:
OpenPipeline `sn-*` tags → Automated grouping on `metric_name` + `cmdb_ci` →
**enrich BRs** (`sn-impact`/`sn-urgency`; log alert CI = **service instance**;
K8s dash-key CI for infra) →
**EvtMgmtIncidentHandler** / **EvtMgmtCustomIncidentPopulator** remain for
enrich and for any Flow that still calls Create incident from Alert.
Incident **create** is OOTB AMR **SGO-Dynatrace** (log and metric).

## Event Management layers (who creates what)

| Layer | Who | Creates? | Filter guidance |
| ----- | --- | -------- | --------------- |
| Ingest | SGO webhook | **`em_event`** insert/update (`message_key` = ProblemID) | n/a |
| Event rule (manual EM UI) | EM | Does **not** create the event. Marks events **Ready** | `source=SGO-Dynatrace` only — include Warning (4) and OK/clear (5) so *metric* alerts open and close. Log Clear/OK is rewritten to Major by enrich (durable incidents). |
| Alert rule (manual EM UI) | EM | **Creates/updates `em_alert`**; closes on clear updates | `source=SGO-Dynatrace` (log alerts stay Open; enrich strips Closing) |
| Create AMR `SGO-Dynatrace` | L2I | **Creates/correlates `incident`** | `severity<=3`, not Secondary, not maintenance, CI bound |

Do **not** put `severity<=3` on the Event → Ready rule. That blocks RESOLVED/OK clears from reaching alert processing and also prevents Warning infra events from becoming alerts. `severity<=3` is the **incident promotion** gate only (AMR `SGO-Dynatrace`).

## Create path (OOTB AMR SGO-Dynatrace)

AMR **SGO-Dynatrace** with OOTB subflow **Create Incident** (not the SGC
**SGO-Dynatrace Alert Subflow**) creates incidents for log and metric alerts:

`source=SGO-Dynatrace^maintenance=false^incidentISEMPTY^severity<=3^correlation_group!=Secondary^parentISEMPTY^cmdb_ciISNOTEMPTY`

*Alert changes to filter.* `evt_mgmt.avoid_int_enabled` waits for the grouping
job; the filter still excludes Secondaries.

Virtual Automated/Tag groups use source **Group Alert**. AMR **Create Incident
for Primary Alert** (`source=Group Alert^maintenance=false^incidentISEMPTY`)
tickets those primaries.

BR `em-alert-create-log-incident` stays **inactive**. Reserved AMR
**L2I Create Incident CRITICAL_LOG_EVENT** stays **inactive**.

## Why all-kebab `sn-*` keys (`sn-service-instance`, not `sn-service_instance`)

TBAC reads `additional_info` via a **dot-path** into JSON, e.g.
`ProblemDetailsJSON.rankedEvents[0].customProperties.sn-log-signature`.
Each `.` is a nested-object step, so **dots in the property name break TBAC**.

Lab convention for Dynatrace custom event properties that ServiceNow reads:

| Form | Verdict |
|------|---------|
| `sn.service_instance` | Don't (dots) |
| `sn-service-instance` | Prefer (all kebab) |
| `sn_service_instance` | Avoid here (all-snake not our standard) |
| `sn-service_instance` | Avoid (mixed `-` and `_`) |

## Playbooks

| Playbook | Purpose |
| -------- | ------- |
| `deploy.yml` | Upsert Script Includes, enrich BRs, grouping properties, SGO-Dynatrace AMR |
| `test.yml` | Assert recent SGO-Dynatrace events/alerts and spark-client incidents |
| `diagnose.yml` | Open SGO-Dynatrace alerts, log incidents; includes all `test.yml` checks |

## Active artifacts (after deploy)

| Name | Role |
| ---- | ---- |
| `ResolveApplicationService` | SI resolve helpers (`sn-service-instance`, `k8s-workload-name`, …); `enrichSgoRecord` |
| `EvtMgmtCustomIncidentPopulator` | L2I: incident CI = SI; correlate by SI + `sn-log-signature` |
| `L2IIncidentFromAlert` | Helper → `EvtMgmtIncidentHandler` (job / reprocess) |
| BR `em-event-enrich-sgo` / `em-alert-enrich-sgo` | Before insert/update: stamp `sn-impact`/`sn-urgency`; log CI = service instance; else K8s dash-key CI; **durable log**: rewrite Clear/OK to Major so DT RESOLVED does not close the event/alert |
| BR `em-alert-create-log-incident` | **Inactive.** Replaced by AMR `SGO-Dynatrace` |
| TBAC `L2I short Log4j2 SI + signature` | **Inactive.** Log grouping is Automated `metric_name` + `cmdb_ci` |
| AMR `L2I Create Incident CRITICAL_LOG_EVENT` | **Inactive** (reserved) |
| AMR `SGO-Dynatrace` | **Active.** Log + metric; OOTB **Create Incident** subflow; non-secondary; not maintenance; CI bound; `severity<=3` |
| Correlation rule `L2I Same CI and metric_name` | **Active.** Rule-based: same `cmdb_ci` + same `metric_name` |
| AMR `Create Incident for Primary Alert` | **Active** for `source=Group Alert` only |

## OpenPipeline tags (must be present on Davis events)

| Tag | Purpose |
| --- | ------- |
| `sn-event-kind=CRITICAL_LOG_EVENT` | Gate for incident create |
| `sn-log-signature` | Class:Line; also stamped as `metric_name=Log-Error:{signature}` |
| `sn-log-class` / `sn-log-line` | Parsed parts |
| `sn-environment` | Partition (no cross-env grouping) |
| `sn-service-instance` | Service instance clustering / resolve key |
| `sn-pipeline` | OpenPipeline customId |
| `sn-impact` | Incident impact (1=High, 2=Medium, 3=Low). DT stamps logs/CPU; SN enrich maps OOTB `ProblemSeverity` |
| `sn-urgency` | Incident urgency (same scale). Repeats of the same SI+signature bump urgency. SN **Data Lookup** calculates **priority** from impact × urgency (not set in L2I code) |
| `k8s-pod-name` | Dash alias of `k8s.pod.name` (TBAC-safe). Pod CI lookup |
| `k8s-workload-name` | Dash alias of `k8s.workload.name`. Deployment/workload CI lookup |
| `k8s-workload-kind` | `deployment` / `statefulset` / `daemonset` / `cronjob` / `job` |
| `k8s-cronjob-name` / `k8s-job-name` | CronJob / Job CI lookup when those dimensions are present |
| `k8s.pod.name` | Platform dotted key (JSON bracket in SI; do not put in TBAC keys) |

**Alert severity vs incident priority (current, not redesigned):** `em_alert.severity` is SGO’s 1–5 map of Dynatrace `ProblemSeverity` (this instance: `ERROR`→Major/2, `RESOURCE_CONTENTION`→Warning/4). `incident.priority` is OOTB Data Lookup from `incident.impact` × `incident.urgency`, which the populator copies from `sn-*`. **Only** AMR `SGO-Dynatrace` requires `severity<=3` (Warning alerts may exist; they do not auto-incident). See `servicenow/docs/Log_to_Incident/SGO-Dynatrace_Enhancements.md` for the mapping table and per-context payload attributes.

Standalone custom log source still stamps OneAgent `service_instance`; OpenPipeline maps it to `sn-service-instance`.

## Change-window maintenance (OOTB + Affected CIs)

OOTB **CI in Change Window** (`ImpactManager.getCisInActiveChangeWindow()`) is
the product path. Deploy re-asserts it **active**. It marks only
`change.cmdb_ci`. ServiceNow Event Management describes the OOTB gates as:

1. Change state is **Scheduled** (`-2`) or **Implement** (`-1`). **New (`-5`)
   does not qualify** (OOTB does not mark the primary CI in New).
2. `approval=approved`, not on hold.
3. Now is inside the **planned** `start_date`…`end_date` window **or** the
   **actual** `work_start`…`work_end` window (open-ended while `work_end` is
   empty after Implement sets `work_start`).
4. `cmdb_ci` is populated.

It does **not** mark Affected CIs (`task_ci`). That is a product gap; industry
practice is a second non-advanced rule on `task_ci` / `ci_item`. Deploy upserts
`servicenow/integrations/incident/em_maintenance_rule_affected_cis.json`
(**Affected CIs in Change Window**) with the **same** approval / hold /
Scheduled/Implement / planned-**or**-actual time gates. Advanced `findCisInMaint()` scripts are easy
to drop (wrong return type). The Maintenance Calculator job must be running
(~1 min). Proof is `em_impact_maint_ci.ci_id` (not `ci`). AMR filters already
require `maintenance=false`.

One-time cleanups (for example, deactivating a leftover rule named
**L2I Affected CIs in Change Window**) belong in this directory's `tmp/`
play, not in `deploy.yml`. Git ignores `tmp/`.

The stress driver (`run-stress.sh -cr MINUTES`) creates a **Standard** change,
walks New → Scheduled → Implement (`work_start` set), and moves to **Review**
when the window ends or the suite stops. Normal changes cannot jump to
Implement from REST (assignment-group approval).

Event Management does **not** update CI `operational_status` or CSDM
`life_cycle_stage`. Confirm suppression on `em_impact_maint_ci` /
`em_alert.maintenance`, not CI history.

## Usage

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/incident/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/deploy.yml -e @../vars/secrets.yaml
```
