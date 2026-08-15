# SGO-Dynatrace Enhancements (lab findings for DT / SN account teams)

**Instance:** optimizincdemo1  
**Dynatrace tenant:** pdt20158  
**Date:** 2026-08-14 (Spark-independent L2I patterns: Standalone + K8s short Log4j2; AMR+TBAC tags; thin create BR; sn-impact enrich; K8s dash-key CI)  
**Scope:** short Log4j2 application-log → Davis problem → ServiceNow Event Management → ITSM incident, using **SGO-Dynatrace** only.

This note is the **design of record** for the lab Log-to-Incident path, plus product / configuration gaps for Dynatrace and ServiceNow account teams. Historical dead-ends (CUSTOM_DEVICE, `spark.*` bind/pipeline attributes, unified pipelines) are marked **Historical** only where they still explain a gap.

**Promote timestamp:** write `tmp/l2i_pattern_promote_ts.txt` on each cutover.

---

## 0. Current design of record (2026-08-10 — sn-* dash tags + handler create path)

### Attribute basename: `sn-*` (solution-specific; dashes, not dots)

Dots in attribute names break ServiceNow TBAC nested-path walks into
`additional_info` JSON. Use dashes so
`…customProperties.sn-log-signature` is one path segment.

| Attribute | Role |
| --------- | ---- |
| `sn-log-class` / `sn-log-line` | Parsed short Log4j2 `Class:Line` (OpenPipeline) |
| `sn-log-signature` | `Class:Line` clustering / incident short description |
| `sn-event_kind` | SN semantic type (`CRITICAL_LOG_EVENT` / `CPU_EVENT`) |
| `sn-environment` | Environment partition (no cross-env grouping) |
| `sn-service_instance` | Service instance clustering / resolve key |
| `sn-pipeline` | OpenPipeline customId stamp |
| `sn-impact` | SN incident impact (1/2/3). DT stamps where it can (OpenPipeline, metric events); SN enrich maps ProblemSeverity otherwise |
| `sn-urgency` | SN incident urgency (1/2/3). Correlated repeats bump toward 1; SN Data Lookup calculates **priority** from impact × urgency |
| `k8s-pod-name` | Dash alias of `k8s.pod.name` (TBAC-safe). Log events; pod CI lookup |
| `k8s-workload-name` | Dash alias of `k8s.workload.name`. Workload problems → deployment/statefulset/cronjob CI |
| `k8s-workload-kind` | `deployment` / `statefulset` / `daemonset` / `cronjob` / `job` |
| `k8s-cronjob-name` / `k8s-job-name` | CronJob / Job execution CI lookup |
| `k8s.pod.name` | Platform dotted key (still stamped; SN reads via JSON bracket, never TBAC dot-walk) |
| `service_instance` | Standalone OneAgent custom-source stamp (mapped → `sn-service_instance`) |

### How alert severity and incident priority are computed today

These are **three different numbers**. This lab does **not** yet calculate alert severity or incident priority from `sn-impact`/`sn-urgency`; that is deferred.

| Field | Who sets it | How |
| ----- | ----------- | --- |
| **`em_event.severity` / `em_alert.severity`** (Event Management 1–5: Critical…OK) | SGO field mapping from Dynatrace `ProblemSeverity` | Observed on this instance: `ERROR` → **Major (2)**; `RESOURCE_CONTENTION` → **Warning (4)** (docs that say Minor/3 for contention are wrong here). `PERFORMANCE` typically Warning. `AVAILABILITY` typically Critical/Major. We do **not** overwrite this. |
| **`sn-impact` / `sn-urgency`** (ITSM 1=High, 2=Medium, 3=Low) | Dynatrace when it can; else `em-event-enrich-sgo` / `em-alert-enrich-sgo` | OpenPipeline logs: ERROR=2/2, WARN=3/3. Host CPU metric event: 2/2. OOTB Davis/K8s: mapped from `ProblemSeverity` (table below). Stored in `additional_info` customProperties **and** description tokens so every SGO-Dynatrace event has them. |
| **`incident.impact` / `incident.urgency`** | `EvtMgmtCustomIncidentPopulator.applySnPriorityToTask` | Copies `sn-impact`/`sn-urgency` from the alert. Repeat alerts for the same SI+`sn-log-signature` **bump urgency** toward 1 (and take the more severe impact). |
| **`incident.priority`** | ServiceNow **Data Lookup** (`incident` Priority lookup, impact × urgency) | Not set in L2I code. Example: impact 3 + urgency 1 → priority 3. Changing this mapping is a later task. |

Create-incident gate is still `severity<=3` on the shim BR, so Warning (4) CPU/K8s alerts get `sn-*` but **no incident** until that policy is revisited.

### Initial `sn-impact` / `sn-urgency` mapping (tunable)

| Source | sn-impact | sn-urgency |
| ------ | --------- | ---------- |
| OpenPipeline log ERROR | 2 | 2 |
| OpenPipeline log WARN | 3 | 3 |
| Host CPU metric event (`sn-event_kind=CPU_EVENT`) | 2 | 2 |
| `ProblemSeverity=AVAILABILITY` (OOTB, SN enrich) | 1 | 2 |
| `ProblemSeverity=ERROR` | 2 | 2 |
| `ProblemSeverity=RESOURCE_CONTENTION` | 2 | 2 |
| `ProblemSeverity=PERFORMANCE` | 2 | 3 |
| `ProblemSeverity=CUSTOM_ALERT` / other | 3 | 3 |
| No ProblemSeverity: EM severity 1 / 2 / 3 / 4–5 | 1/1, 2/2, 2/3, 3/3 | same |

### Webhook / event attributes by context

Dynatrace problem notification body is still `ProblemDetailsJSON` + `ImpactedEntities` (`sgc-problem-notification-payload.json.j2`). Attributes SN uses live in `rankedEvents[0].customProperties` (and description tokens). **Dash keys** are required wherever TBAC or a Glide condition would otherwise treat `.` as a JSON path walk. Script Includes read dotted platform keys with `customProperties['k8s.workload.name']` (bracket), then copy a dash alias.

| Context | Who can stamp | Required / used attributes | Alert CI lookup |
| ------- | ------------- | -------------------------- | --------------- |
| **K8s / Standalone short Log4j2** | OpenPipeline Davis (`dt.davis.is_merging_allowed=false`) | `sn-event_kind`, `sn-log-signature`, `sn-environment`, `sn-service_instance`, `sn-pipeline`, `sn-impact`, `sn-urgency`; K8s also `k8s-pod-name`, `k8s-workload-name`, `k8s-workload-kind`, `k8s-namespace-name` | **Alert CI = service instance** (enrich overwrites HOST/pod SOS). Incident CI = same SI |
| **Host CPU metric event** | Metric event `eventTemplate.metadata` | `sn-event_kind=CPU_EVENT`, `sn-environment`, `sn-impact=2`, `sn-urgency=2` | HOST via SGO SOS (`ImpactedEntities[0].type=HOST`) |
| **OOTB K8s workload** (CPU close to limits, etc.) | DT metric dimensions on the problem; **cannot** add OpenPipeline metadata | Platform: `k8s.workload.name`, `k8s.workload.kind`, `k8s.namespace.name`, `k8s.cluster.name`; `ImpactedEntities[0].type=CLOUD_APPLICATION`, `name=<workload>`. SN enrich copies `k8s-workload-name` / `k8s-workload-kind` | Deployment (or kind table) by **name** (`k8s-workload-name` or entity name). SGC 1.15.0 has no Workload data source — SOS/`correlation_id` usually empty |
| **OOTB K8s pod / CAI** | DT | `k8s.pod.name` (platform); SN copies `k8s-pod-name` | `cmdb_ci_kubernetes_pod` by name |
| **OOTB CronJob / Job** | DT when those dimensions exist | `k8s.cronjob.name` / `k8s.job.name`; SN copies `k8s-cronjob-name` / `k8s-job-name` | `cmdb_ci_kubernetes_cron_job` / `cmdb_ci_kubernetes_job` by name |
| **OOTB host CPU_SATURATED** (Davis idle) | None (no metadata schema) | `ProblemSeverity` only | HOST SOS; SN enrich fills `sn-*` from severity |

**Dotted-lookup rule:** never put `k8s.workload.name` in a TBAC `additional_info_key` or a `sys_script` filter condition. Use `k8s-workload-name`. JSON.parse + bracket access in `ResolveApplicationService.getCustomProperty` is safe.

**Why both `event.type` and `sn-event_kind`?** Dynatrace Settings API constrains Davis `event.type` to a fixed enum (`ERROR_EVENT`, `CUSTOM_ALERT`, …). `sn-event_kind` carries the ServiceNow UI type; `ResolveApplicationService.applyLogEventTypeRename` remaps `em_event.type` / `em_alert.type`. Built-in `CPU_SATURATED` is left unchanged.

### End-to-end contract

| Pattern | Log emission | OneAgent ingest | OpenPipeline | Alert CI | Incident CI |
| ------- | ------------ | --------------- | ------------ | -------- | ----------- |
| **Standalone App with short Log4j2 logs** | RollingFile under lab path (`/mnt/spark/client-logs/…`) | Custom log source stamps `service_instance` | `standalone-short-log4j2-log-alerts` | HOST (ImpactedEntity) | Service instance from `service_instance` |
| **K8s App with short Log4j2 logs** | Console → container stdout | DynaKube `logMonitoring: {}` → `Container Output` + `k8s.pod.name` | `k8s-short-log4j2-log-alerts` | Pod CI | Service instance via pod → `svc_ci_assoc` |
| **Host CPU** | Metric event | Host OneAgent | `sn-event_kind=CPU_EVENT` on metric template | HOST | (CPU path; not log SI correlation) |

Specs: `standalone-short-log4j2-*.json.j2`, `k8s-short-log4j2-openpipeline.json.j2`, `l2i-openpipeline-routing-entries.json.j2`, `dynakube.yaml.j2`.

### ServiceNow enterprise path (handler create + TBAC)

| Layer | Behavior |
| ----- | -------- |
| **OpenPipeline tags** | `sn-event_kind`, `sn-log-signature`, `sn-environment`, `sn-service_instance`, `sn-pipeline` (+ `k8s.pod.name`) in Davis custom properties and description tokens. |
| **TBAC** | Definition **L2I short Log4j2 SI + signature** exact-matches those customProperties keys so alerts share a group only within the same env + SI + Class:Line. |
| **Alert CI** | **Log** (`CRITICAL_LOG_EVENT` / `sn-service_instance`): **service instance** (enrich overwrites SGO HOST/pod SOS). **Infra** (CPU / K8s workload): HOST via SOS, or `cmdb_ci_kubernetes_*` from `k8s-workload-name`. |
| **Incident create** | Target: AMR + Flow action **Create incident from Alert**. Interim: BR shim → `EvtMgmtIncidentHandler.createIncident`. AMR reserved **inactive** (OOTB Create Incident subflow skips populator). |
| **Incident CI** | `EvtMgmtCustomIncidentPopulator` sets **service instance**; correlates open incidents by SI + `Critical log event — Class:Line`. |
| **assignment_group** | Not set in L2I (hold). Best practice when enabled: copy CI `support_group` → incident `assignment_group`. |
| **Bind BRs** | **Purged.** Do not republish. Enrich BRs stamp `sn-*` and K8s dash-key CI only. |

### CMDB / mixed grouping — additional noise reduction (#3)

Beyond tag clustering on **env + SI + signature**, ServiceNow Mixed / CMDB-based grouping can collapse alerts that share **service topology** even when signatures differ:

| Extra grouping | Noise reduction | What it takes here |
| -------------- | --------------- | ------------------ |
| **CMDB / service map** (alerts on CIs under the same Application Service) | One group when Master WARN, Worker WARN, and Client errors fire during the same outage window — ops sees “Spark Worker service degraded” instead of N signature tickets | (1) Keep alert CI as **pod/HOST** with reliable `svc_ci_assoc` to the SI; (2) enable Mixed grouping with CMDB + our TBAC definition; (3) accept coarser incidents (may merge distinct Class:Line defects) or use CMDB grouping only for severity≥Critical |
| **Same host / node** | Node pressure (CPU + many worker pods) → one infra-oriented group | CMDB Runs-on edges from pod→node→host must be current (SGC/KVA); add a TBAC/CMDB definition scoped to HOST |
| **Change / maintenance window** | Suppress L2I incidents during deploy | Wire `maintenance=true` on alerts (already excluded by AMR filter) via change calendars |

**Recommendation for this lab:** keep TBAC at **env + SI + signature** (defect-level tickets). Add CMDB mixed grouping later only if operators want outage-level super-groups, and gate it so `log.event_kind=CRITICAL_LOG_EVENT` still creates SI-scoped incidents via the populator (one incident per signature under the group primary).

### Active lab artifacts

| Name | Kind | Role |
| ---- | ---- | ---- |
| `ResolveApplicationService` | Script Include | SI resolve helpers (`sn-*`); `enrichSgoRecord` (impact/urgency + K8s dash-key CI) |
| `EvtMgmtCustomIncidentPopulator` | Script Include | L2I SI CI + correlate by `sn-log-signature` |
| `L2IIncidentFromAlert` | Script Include | Helper → `EvtMgmtIncidentHandler` |
| `em-event-enrich-sgo` / `em-alert-enrich-sgo` | BR (before) | Stamp `sn-impact`/`sn-urgency`; bind workload/pod CI from dash keys |
| `em-alert-create-log-incident` | BR (shim) | `EvtMgmtIncidentHandler.createIncidentNoUpdate` |
| `L2I short Log4j2 SI + signature` | TBAC definition | Tag cluster: `sn-environment` + SI + signature |
| `L2I Create Incident CRITICAL_LOG_EVENT` | AMR | **Inactive** until published Create-incident-from-Alert Flow |
| Bind / propagate BRs; OOTB primary / SGO AMRs | — | Bind BRs **purged**; OOTB AMRs **inactive** |

**Product gap:** OOTB remediation subflow **Create Incident** does not invoke `EvtMgmtIncidentHandler` / `EvtMgmtCustomIncidentPopulator` on this instance. Deploy user also cannot insert `sysauto_script`. Until a Flow uses action **Create incident from Alert** (or an admin creates `L2IProcessPendingAlerts`), the handler shim BR is required.

Deploy: `ansible/playbooks/servicenow/incident/deploy.yml`.

### Product gap: OpenPipeline cannot look up entities by name

OpenPipeline **Processing cannot look up entities by name**. Lab **does not** bake pod→CAI `fieldsAdd` processors at apply time.

**Current workaround:** stamp `k8s.pod.name` (already on Container Output) into Davis description / properties; ServiceNow binds service instance by pod CI name. Client bind uses `service_instance` from the custom log source, not a Dynatrace CUSTOM_DEVICE.

**Still desirable from DT:** native OpenPipeline entity lookup / PGI→pod remapping so SN can rely on ImpactedEntity alone. Until then SN prefers the stamped `k8s.pod.name` for durable CMDB Contains traversal.

### Product gap: SGC drops problems without topology CI match unless unmatched-CI events are enabled

**Symptom:** Dynatrace fired brooks-lab webhooks for log problems whose ImpactedEntity is HOST (or otherwise unmatched in SGC topology); some problems did not create SGO events.

**Root cause:** `sn_dynatrace_integ.events_for_unmatched_ci.enabled=false` → syslog `SGO-Dynatrace: Skipping event creation on non matched CI`.

**Lab fix:** set that property to `true` in `ensure_spark_entity_cmdb_bindings.yml` (wired into `events/deploy.yml`). Lab BRs then bind via `service_instance` / `k8s.pod.name` (or HOST for CPU).

**Ask SN:** document this property for SGO customers whose Davis primary entity is not in an SGC topology feed (common for Client HOST file-tail and any residual HOST-primary Cluster problems).

### Validation snapshot (post-promote)

| Check | Result |
| ----- | ------ |
| Promote | `2026-08-03T14:31:46Z` |
| Stress `run-parallel-all.sh` | exit 0 |
| First audit (all SGO since promote) | 13 events, **0 null `cmdb_ci`**; 12 HOST (CPU / `CUSTOM_ALERT`, `spark.event_kind=CPU_EVENT`) + 1 Cluster log (`spark.pod_identifier` → Spark Master AS) |
| Client path | bind via `spark.service_instance:Spark-Client` → service instance **Spark Client** (`resource` = `spark.service_instance:Spark-Client`) |

Filter Spark log rows with problem title / description containing `Spark critical` (or OpenPipeline provider) — do not judge L2I entity quality from all `source=SGO-Dynatrace` rows (CPU HOST noise).

---

## 1. OOTB `SGO-Dynatrace` alert management rule creates incidents before CI bind

### Documentation

ServiceNow product docs (generic AMR, not SGO-specific):

- [Create an alert management rule](https://www.servicenow.com/docs/r/it-operations-management/event-management/create-alert-management-rule.html)
- Related pattern: leave task template empty → `EvtMgmtCustomIncidentPopulator` for field mapping (community / docs), which **populates** the incident the AMR creates — it does **not** attach an arbitrary Business Rule into the AMR.

### What it is (lab summary)

This is **not** a Business Rule (`sys_script`). It is an Event Management **Alert Management Rule** shipped with Store app **Service Graph Connector for Observability - Dynatrace** (`sn_dynatrace_integ` 1.15.0).

| Field                | Lab value                                                                                                                                                                                                                                              | Meaning                                              |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------- |
| Name                 | `SGO-Dynatrace`                                                                                                                                                                                                                                        |                                                      |
| Type                 | `incident`                                                                                                                                                                                                                                             | Action is incident create                            |
| Alert filter         | `source=SGO-Dynatrace`                                                                                                                                                                                                                                 | Matches **all** SGO alerts (CPU, log, etc.)          |
| Automatic execution  | `2` = **Alert matches filter**                                                                                                                                                                                                                         | Re-applies on matching updates                       |
| Multiple alert rules | `2` = **Stop search for additional rules**                                                                                                                                                                                                             | After this rule, other AMRs are not searched         |
| Order                | `10`                                                                                                                                                                                                                                                   | High priority (low number)                           |
| Incident template    | *(empty)*                                                                                                                                                                                                                                              | Uses default / `EvtMgmtCustomIncidentPopulator` path |
| Active (lab)         | **false**                                                                                                                                                                                                                                              | **Yes — this is the OOTB rule we turned off**        |
| Sys id               | `7f5e284e07032010b1306a77c4a93523`                                                                                                                                                                                                                     |                                                      |
| Deep link            | [https://optimizincdemo1.service-now.com/nav_to.do?uri=em_alert_management_rule.do?sys_id=7f5e284e07032010b1306a77c4a93523](https://optimizincdemo1.service-now.com/nav_to.do?uri=em_alert_management_rule.do?sys_id=7f5e284e07032010b1306a77c4a93523) |                                                      |

AMRs typically evaluate on a short delay after alert update (product default ~5s via `evt_mgmt.alert_rule_delay`). That delay is **not** a guaranteed “wait until service instance bind finishes.”

Lab custom creator for comparison:

| Field     | Value                                                                                                                                                                                                                      |
| --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Name      | `em-alert-create-log-incident` (formerly `em-alert-create-k8s-log-incident`)                                                                                                                                               |
| Table     | `sys_script` (Business Rule on `em_alert`)                                                                                                                                                                                 |
| Filter    | `source=SGO-Dynatrace^severity<=3`                                                                                                                                                                                         |
| Order     | `5020` (runs after bind BR `5010`)                                                                                                                                                                                         |
| Sys id    | *(re-resolved after rename — look up by name)*                                                                                                                                                                             |
| Deep link | Search `sys_script` name `em-alert-create-log-incident` on optimizincdemo1                                                                                                                                                 |

### Can we “link” our create BR into this AMR?

**No.** AMRs and Business Rules are parallel mechanisms:

| Mechanism                                                     | Role                                                            |
| ------------------------------------------------------------- | --------------------------------------------------------------- |
| AMR `SGO-Dynatrace`                                           | Product-supported alert → incident (all `source=SGO-Dynatrace`) |
| BR `em-alert-create-log-incident`                             | Lab create/correlate via handler + populator                    |
| `EvtMgmtCustomIncidentPopulator`                              | Incident CI = service instance (not part of the AMR)            |

You do **not** register a BR inside an AMR. Options that *are* supported:

1. **Keep OOTB AMR off** for lab; use `em-alert-create-log-incident` (handler shim) for log-to-incident until a published Create-incident-from-Alert Flow owns create.
2. **Narrow OOTB AMR filter** so it only covers standard SGO classes you want OOTB to handle (e.g. host CPU), and **exclude** Spark log / `ERROR_EVENT` (or require `cmdb_ci` class service instance).
3. **Replace** OOTB create with a **custom AMR** whose filter requires `cmdb_ciISNOTEMPTY` (and ideally service instance class) — optionally use `EvtMgmtCustomIncidentPopulator` for field mapping.
4. Do **not** run OOTB AMR **and** `em-alert-create-log-incident` together for the same alerts (dual creators).

### Does moving create into the AMR eliminate the CI race?

**Partially, only if the AMR filter requires a bound service instance CI** (SGO must finish `sys_object_source` bind before the AMR evaluates). Simply “using the AMR instead of the BR” with today’s filter (`source=SGO-Dynatrace` only) does **not** fix the race — that is what created empty-CI incidents.

### Issue

OOTB rule creates an incident as soon as an SGO alert matches. It does **not** require service instance `cmdb_ci`. Lab observed empty-CI incidents while the alert later received Spark Master / Spark Client.

### Lab creator behavior (desired)

`em-alert-create-log-incident` refuses to create until a CI is bound:

```javascript
// servicenow/integrations/incident/em_alert_create_log_incident.br.js
if (current.cmdb_ci.nil()) {
  var bind = resolver.applyEntityBinding(current);
  if (!bind.bound) {
    resolver.appendProcessingNote(
      current,
      'em-alert-create-log-incident: skipped incident create — no CI bound (' +
        (bind.note || 'unknown') + ')'
    );
    return;
  }
}
inc.cmdb_ci = asSysId;
inc.short_description = 'Critical log event';
```

### Impact

Dual incident creators when OOTB is active. OOTB often wins with an empty CI. Operators see ITSM incidents that cannot be routed by service instance. Manual Table API fixes to `incident.cmdb_ci` often do not stick (see §5).

### Recommendation

1. Keep OOTB inactive **or** narrow it to non–log-to-incident SGO alerts (CPU / infra) with standard SGO processing.
2. Log-to-incident stays on `em-alert-create-log-incident` (or a dedicated AMR that requires service instance CI). Bind BRs are purged.
3. Ask SN for a product pattern: “SGO incident AMR must not fire until CI bind complete.”

### Best practice: growing technology-dependent CI patterns (AMR vs BR)

| Layer                           | Mechanism                                    | Owns                                                                 | Grows how                                                                 |
| ------------------------------- | -------------------------------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| **A. Entity → working CI**      | Script Include + thin Business Rules         | Parse bind keys / ImpactedEntities; bind HOST, AS, CAI→AS, etc.      | Add methods on `ResolveApplicationService`; keep BR names entity-agnostic |
| **B. When to open an incident** | Alert Management Rule (AMR) **or** create BR | Filter which alerts get incidents                                    | One policy for infra vs application-log; do not mix bind logic into OOTB  |
| **C. Field polish on create**   | `EvtMgmtCustomIncidentPopulator` (optional)  | Map alert fields → incident fields when an AMR creates the task      | Shared helpers; still not entity-bind logic                               |

**Recommended split for SGO-Dynatrace:**

1. **Do not** put growing entity→CI logic inside the OOTB AMR.
2. **Do** keep bind logic in **`ResolveApplicationService`** called from thin BRs filtered by `source=SGO-Dynatrace`.
3. **Replace or narrow** OOTB AMR `SGO-Dynatrace` rather than customizing it in place.
4. Prefer **deactivating OOTB** and adding named replacement AMRs over editing the Store-shipped record.
5. Package as update sets / scoped app + git (`servicenow/integrations/…`).

---

## 2. Dual Dynatrace → ServiceNow problem notifications (legacy vs SGO)

### What “ServiceNow Demo 1 - Optimiz” is

It is a **Dynatrace problem notification** (Settings → Problems → Notifications), **not** a ServiceNow Business Rule or Script Include.

| Field                                   | Value                                                                                                                                                                                                                                                                        |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Display name                            | `ServiceNow Demo 1 - Optimiz`                                                                                                                                                                                                                                                |
| Webhook URL                             | `https://optimizincdemo1.service-now.com/api/sn_em_connector/em/inbound_event?source=dynatrace&sys_id=712a39811ba483105488a937b04bcba5`                                                                                                                                      |
| Effect on SN                            | Creates `em_event` / `em_alert` with **`source=Dynatrace`** (legacy connector)                                                                                                                                                                                               |
| Alerting profile                        | `DemoProfile - Optimiz` (no MZ filter)                                                                                                                                                                                                                                       |
| Lab state                               | **Disabled** (keep disabled until exclusive routing is configured)                                                                                                                                                                                                           |
| UI (list — use this if object URL 404s) | [https://pdt20158.apps.dynatrace.com/ui/apps/dynatrace.classic.problems/#settings/builtin:problem.notifications](https://pdt20158.apps.dynatrace.com/ui/apps/dynatrace.classic.problems/#settings/builtin:problem.notifications) — then open **ServiceNow Demo 1 - Optimiz** |
| Alternate classic list                  | [https://pdt20158.live.dynatrace.com/#settings/integration/problemnotifications](https://pdt20158.live.dynatrace.com/#settings/integration/problemnotifications)                                                                                                             |

Brooks-lab (new-school) notification:

| Field            | Value                                                                                           |
| ---------------- | ----------------------------------------------------------------------------------------------- |
| Display name     | `ServiceNow brooks-lab - Spark Observability`                                                   |
| Webhook URL      | `…/inbound_event?source=SGO-Dynatrace`                                                          |
| Alerting profile | `Spark Observability - ServiceNow brooks-lab` (scoped to MZ **Spark Observability**)            |
| Enabled          | Yes                                                                                             |
| UI list          | Same problem-notifications list as above — open **ServiceNow brooks-lab - Spark Observability** |

**Clarification:** Demo 1 is a **problem notification + alerting profile**, not an OpenPipeline. The Spark log OpenPipeline that *creates* Davis problems is separate:

| OpenPipeline     | Value                                                                                               |
| ---------------- | --------------------------------------------------------------------------------------------------- |
| Display name     | **Spark Lab - log alerts**                                                                          |
| customId         | `spark-lab-log-alerts`                                                                              |
| Schema           | `builtin:openpipeline.logs.pipelines`                                                               |
| Davis processors | `spark-client-warn-error-davis`, `spark-cluster-warn-error-davis`, `spark-enrichment-missing-davis` |
| Repo             | `observability/dynatrace/integrations/spark-openpipeline-log-alerts-pipeline.json.j2`               |

### Do lab BRs / SIs still match `source=Dynatrace`?

**No.** After the SGO-only cutover, filters and script guards are SGO-only:

| Artifact                       | Source condition                                                                            |
| ------------------------------ | ------------------------------------------------------------------------------------------- |
| `em-alert-create-log-incident` | `filter_condition=source=SGO-Dynatrace^severity<=3^incidentISEMPTY` plus `current.source !== 'SGO-Dynatrace' → return` |

Legacy `source=Dynatrace` rows are **ignored** by this automation (by design).

### Why dual webhooks are an issue

Dynatrace can fire **multiple** problem notifications for the same problem when each notification’s alerting profile matches.

1. **Demo 1** used a broad profile (`DemoProfile - Optimiz`) with **no management-zone filter** → matched Spark Client / Master Davis problems → posted to the **legacy** inbound URL → SN stamped **`source=Dynatrace`**.
2. **Brooks-lab** used the MZ-scoped profile → only problems whose impacted entities are in MZ **Spark Observability** post to **`source=SGO-Dynatrace`**.
3. During stress (before Demo 1 was disabled), Spark log `ERROR_EVENT` alerts appeared almost entirely as `source=Dynatrace` with empty CI. Host CPU problems in the MZ appeared as `source=SGO-Dynatrace`.

So Spark logs did **not** “choose” Dynatrace inside ServiceNow. **Dynatrace routed them to the legacy webhook** because Demo 1 was still enabled and matched those problems.

### Do we tweak DT problems or SN event processing?

Prefer **Dynatrace routing**, not SN dual-path processing:

| Approach                                                   | Recommendation                                                                                                           |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Keep Demo 1 disabled (or MZ-exclude Spark Observability)   | **Yes** for lab cutover — legacy rules stay on `source=Dynatrace`; new-school only on SGO                                 |
| Re-add `source=Dynatrace` to lab BRs                       | **No** — that re-entangles connectors and blocks the SGO-only model                                                      |
| Ensure Spark entities are in MZ used by brooks-lab profile | **Yes** (see §4) so new-school problems always hit SGO                                                                   |
| SN: separate legacy connector vs SGO connector             | Already separated by inbound `source=` query param; keep BR filters aligned                                              |

**Desired end state:** both notifications may be **enabled**, but each problem is delivered to **exactly one** webhook:

- Spark Observability MZ (CPU **and** Spark log Davis problems) → brooks-lab → `source=SGO-Dynatrace`
- Everything else intended for the Optimiz demo → Demo 1 → `source=Dynatrace`

### Best practice / minimal Demo-side change (recommendation — **do not apply yet**)

Routing belongs on **alerting profiles / problem notifications**, not on the Spark OpenPipeline.

1. Edit alerting profile **`DemoProfile - Optimiz`** (the profile attached to Demo 1).
2. Add a **management zone** constraint that is **disjoint** from **Spark Observability**, **or** add an **event / entity filter** that excludes MZ **Spark Observability** and/or tag `Project:spark-observability`.
3. Leave brooks-lab profile as the **only** profile that includes MZ **Spark Observability**.
4. Re-enable Demo 1 only after verifying a Spark log problem and a lab CPU problem produce **`source=SGO-Dynatrace` only**.

**Avoid** teaching SN BRs to accept both sources for the same workload — that hides dual delivery instead of fixing it.

### MZ vs tags on alerting profiles (Dynatrace UI note)

The Alerting Profiles form says entities in the configured MZ match the profile and *“It is recommended to use manual tags instead.”* That is about **assignment lag / consistency**, not “do not use MZ for ServiceNow.”

- **MZ filter:** still valid to scope a team or lab; can lag when rules are complex.
- **Tag filter (preferred for notification routing):** use **manual** or **API/OneAgent-applied** tags on the entities that own the problem.
- **Practical pattern:** MZ for access / partitioning; **stable tags** on severity rules for *which webhook* gets the problem.

### Impact / recommendation (lab ops)

While both were enabled with overlapping profiles, Spark log incidents were created by **legacy** EM paths with empty CI, and lab SGO BRs never ran on those alerts. Until DemoProfile is exclusivity-filtered, keep Demo 1 **disabled**.

---

## 3. Historical — CUSTOM_DEVICE / SOS / name-parity client bind

> **Historical.** Current design does **not** use a Dynatrace CUSTOM_DEVICE for Client Mode. Client bind is `spark.service_instance` → service instance **name-first** (see §0). Kept because SOS / name-parity lessons still apply to other SGO entity classes, and CUSTOM_DEVICE remains a **legacy fallback** in `ResolveApplicationService` if an old problem still carries that entity.

### What “SOS” means

**SOS =** `sys_object_source` — ServiceNow’s table that maps an external system’s object id to a CMDB CI.

For SGC / SGO-Dynatrace imports, rows typically look like:

- `name` = `SGO-Dynatrace` (discovery / event source)
- `id` = Dynatrace entity id (e.g. `HOST-…`, `CLOUD_APPLICATION_INSTANCE-…`)
- `target_table` / `target_sys_id` = CMDB CI

### Historical lab issue (CUSTOM_DEVICE → Spark Client AS)

Automation could not reliably **insert** a bare-id SOS row for a Spark Client `CUSTOM_DEVICE` pointing at service instance **Spark Client** (ACL / SGC ownership). Lab fell back to name match and/or `cmdb_key_value`.

**Current Client contract:** OpenPipeline stamps `spark.service_instance=Spark-Client`; SN resolves service instance **Spark Client** by name (then optional `identifier` column). No CUSTOM_DEVICE, no `spark.device`, no `sn_ci_lookup`.

### Recommendation (still valid for other entity types)

- Product: allow SGC / automation to upsert entity → service instance SOS when product ACLs allow it.
- Process: document name-parity conventions where display name is the durable key.
- Lab Client path: prefer stamped `spark.service_instance` over ImpactedEntity HOST / legacy CUSTOM_DEVICE.

---

## 4. Management zone missing Kubernetes workloads (`CLOUD_APPLICATION spark-*`)

### What “CAI” means

**CAI = Cloud Application Instance** — Dynatrace entity type `CLOUD_APPLICATION_INSTANCE` (e.g. display name `spark-master-0`). Cluster Mode Container Output can carry CAI/PGI entity context from the OneAgent Log module; SN still stamps / prefers **`spark.pod_identifier`** for CMDB Contains bind.

### Why workloads were missing from the MZ

MZ **Spark Observability** originally had rules for HOST, KUBERNETES_CLUSTER, and (historically) CUSTOM_DEVICE Spark Client. It did **not** include Kubernetes **workloads** (`CLOUD_APPLICATION`) named `spark-*`. Dynatrace MZ schema exposes workload (`CLOUD_APPLICATION`), not CAI instance, as a first-class ME rule type. CAI instances could show empty `managementZones` even when a cluster rule existed.

Brooks-lab problem notification is **MZ-filtered**. Problems whose primary impacted entity is outside the MZ may not notify SGO (while Demo 1’s unscoped profile still would — see §2).

### Fix applied in lab

Added MZ rule: entity type `CLOUD_APPLICATION`, name `BEGINS_WITH` `spark-`.  
Repo: `observability/dynatrace/management-zones/spark-observability/management-zone.json`.

### Recommendation

Keep workload (`spark-*`) rules in the MZ. Confirm CAI instances inherit or appear under the MZ after the workload rule. Account teams: document that MZ-scoped SGO notifications require **all** Davis impacted entity types used by the lab (hosts for Client file-tail / CPU, and Kubernetes workloads/CAIs for Cluster Container Output).

---

## 5. Incident `cmdb_ci` via Table API vs Business Rule GlideRecord

### What was tried

During RCA of an incident created by OOTB EM with **empty** `cmdb_ci`, an agent used the ServiceNow **Table API** to set `cmdb_ci` after the fact.

- **Work notes** updates via the same API **succeeded**.
- **`cmdb_ci` updates via Table API often did not persist** (read-back still empty).

That was a **diagnostic / repair attempt**, not the supported runtime path.

### What works

Business Rule **`em-alert-create-log-incident`** sets `cmdb_ci` on insert through server-side `GlideRecord`. Runtime must not depend on external REST “later updates” to EM/ITSM records.

### Recommendation

- Do not document Table API `cmdb_ci` repair as an operational procedure.
- Prefer BR/SI/native EM for all event/alert/incident mutations.
- Product: explain why `incident.cmdb_ci` is ignored or overridden on Table API writes in this scope (ACLs, data policies, EM reconciliation).

---

## 6. Related lab automation (reference)

| Name | Kind | Role | Notes |
| ---- | ---- | ---- | ----- |
| `ResolveApplicationService` | Script Include | SI resolve helpers; type remap; processing notes | Active |
| `em-alert-create-log-incident` | BR `em_alert` order 5020 | AMR shim → `EvtMgmtIncidentHandler` | Active |
| Bind / propagate BRs (`em-*-bind-*`, `em-event-propagate-*`) | — | **Purged** (SGO native bind) | Deleted |
| `K8sLogPodCiBind` / `em-*-k8s-*` create BRs | Legacy | Renamed/retired | **Inactive** |

### Note on bind / propagate BRs

**Purged (2026-08-14).** Alert CI bind is SGO `sys_object_source`. Incident CI is `EvtMgmtCustomIncidentPopulator`. Do not republish bind or propagate BRs.

---

## 7. Historical — SGO `ERROR_EVENT` with `resource` = log file path

> **Historical / pre–generic-bind.** Current bind overwrites `resource` with `spark.service_instance:…` or `spark.pod_identifier:…` (or entity id on ImpactedEntity fallbacks). Path-valued `resource` indicates a pre-cutover or unbound row.

### Symptom (historical)

Older `source=SGO-Dynatrace` alerts of `type=ERROR_EVENT` showed short descriptions like:

`ERROR_EVENT: Spark Client (/mnt/spark/client-logs/spark-app.log)`

i.e. **`em_alert.resource` = log path**, while `ImpactedEntities` was still **HOST**, and description sometimes contained legacy `--- L2I enrichment ---` text.

### Recommendation

Treat path-valued `resource` as a **legacy** signal. New Spark log problems should show bind keys in `resource` after `applyEntityBinding`. If new SGO alerts still get path `resource` with HOST-only ImpactedEntities and no `spark.service_instance` / `spark.pod_identifier`, fix OpenPipeline stamps — not SN path matching.

---

## 8. How to narrow SGO processing for infrastructure (CPU / host)

Log-to-Incident BRs should **not** own host CPU. Standard SGO should.

**Target split:**

| Alert class         | Example signal                                      | CI bind                            | Incident create                                              |
| ------------------- | --------------------------------------------------- | ---------------------------------- | ------------------------------------------------------------ |
| Infra / host        | `CPU_SATURATED`, host `CUSTOM_ALERT` / `CPU_EVENT`  | Generic bind → HOST CI             | Narrowed **infra AMR** (re-enable OOTB or clone) when ready  |
| Spark / K8s app log | `ERROR_EVENT` + `spark.event_kind=CRITICAL_LOG_EVENT` | Generic bind → service instance | `em-alert-create-log-incident` (or log AMR with CI required) |

**Minimal way to narrow (lab):**

1. Keep bind/create BRs entity-generic; create BR already skips when `cmdb_ci` empty — optionally add log-type filter.
2. **Re-enable** OOTB AMR `SGO-Dynatrace` **only after** changing its alert filter from bare `source=SGO-Dynatrace` to something that **excludes** log critical events.
3. Set **Multiple alert rules** carefully when using two AMRs.
4. Validate with one host CPU problem and one Spark log problem — no dual incidents.

Until that filter is applied, leaving OOTB **inactive** avoids empty-CI races on log alerts.

---

## 9. Dynatrace UI navigation (no deep links)

Tenant in browser: `https://pdt20158.apps.dynatrace.com` (or classic `https://pdt20158.live.dynatrace.com`).

### A. Problem notification (Demo 1 vs brooks-lab)

1. Open the Dynatrace environment (pdt20158).
2. Settings → **Alerting** → **Problem notifications**.
3. Open **ServiceNow Demo 1 - Optimiz** (legacy → `source=dynatrace`) and **ServiceNow brooks-lab - Spark Observability** (SGO → `source=SGO-Dynatrace`).
4. On each notification, note **Alerting profile** and **Webhook URL**.

Notifications only *select* problems via the alerting profile and POST them — they do not create Davis events.

### B. Alerting profile

1. Settings → **Alerting** → **Problem alerting profiles**.
2. Open **DemoProfile - Optimiz** and **Spark Observability - ServiceNow brooks-lab**.
3. Check **Management zone**, severity rules, and any event filters.

### C. OpenPipeline Davis processors (what *creates* Spark log problems)

1. Settings → **Process and contextualize** → **OpenPipeline** → **Logs**.
2. Pipelines → **Spark Lab - log alerts** (`spark-lab-log-alerts`).
3. **Davis** tab: `spark-client-warn-error-davis`, `spark-cluster-warn-error-davis`, `spark-enrichment-missing-davis`.
4. **Processing** tab: Client AS stamp / instance compose; Cluster `enrich-cluster-from-k8s` from `k8s.pod.name` on Container Output.

To see a live problem’s entity: **Problems** → open problem → **Impacted entities** (HOST for Client file-tail / CPU; CAI/PGI/HOST for Cluster Container Output as attached by OneAgent).

---

## 10. Lab actions already taken (not product changes)

1. OOTB `SGO-Dynatrace` alert management rule → **inactive** (enforced on deploy).
2. Dynatrace notification **ServiceNow Demo 1 - Optimiz** → **disabled** (until DemoProfile exclusivity filter exists).
3. MZ **Spark Observability** → HOST / K8s cluster / `CLOUD_APPLICATION` `spark-*` rules (CUSTOM_DEVICE Spark Client rule is historical).
4. Lab BRs/SIs → entity-generic; SGO-only; name-first AS bind; type remap via `spark.event_kind`; no match → empty `cmdb_ci`.
5. Propagate BR → **inactive**.
6. `sn_dynatrace_integ.events_for_unmatched_ci.enabled=true` so HOST-primary (and other unmatched) problems still create `em_event`s for lab bind.
7. **Cluster app logs:** Log4j2 Console + DynaKube `logMonitoring: {}` → Container Output; custom log source **Client paths only**; OpenPipeline enriches Cluster from `k8s.pod.name`.
8. **Removed from current design:** CUSTOM_DEVICE client entity, path-tail Cluster custom source (`/mnt/spark/logs`), OpenPipeline CAI bake-in, `sn_ci_lookup` / `spark.device` / `spark.davis_entity`.

---

## 11. Ask for account teams

1. **SN:** Official guidance to delay or gate OOTB SGO incident creation until CI is present; or support replacing it with a scoped custom rule without dual creators. Clarify AMR vs BR for SGC customers.
2. **DT:** Best practice for two problem notifications on one tenant with **exclusive** alerting-profile / MZ filters (Demo vs Spark Observability).
3. **SN SGC:** Document `events_for_unmatched_ci.enabled` for customers whose Davis primary entity is HOST (Client file-tail) or otherwise unmatched in topology feeds.
4. **DT:** Confirm CAI / workload MZ membership behavior for Kubernetes entities used with Container Output log streams.
5. **DT:** OpenPipeline **native** pod-name → entity lookup (Processing cannot do live entity enrichment today). Cluster stdout path reduces but does not remove the need for SN-side `spark.pod_identifier` bind.
6. **SN:** Document why Table API updates to `incident.cmdb_ci` may no-op while GlideRecord in a BR succeeds.
7. **SN SGO:** How `em_alert.resource` is chosen for Davis log `ERROR_EVENT` (bind key vs log file path vs entity id).
