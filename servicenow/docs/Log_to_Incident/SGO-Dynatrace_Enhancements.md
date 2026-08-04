# SGO-Dynatrace Enhancements (lab findings for DT / SN account teams)

**Instance:** optimizincdemo1  
**Dynatrace tenant:** pdt20158  
**Date:** 2026-08-03 (generic entity CI-bind redesign)  
**Scope:** Spark / K8s application-log → Davis problem → ServiceNow Event Management → ITSM incident, using **SGO-Dynatrace** only.

This note captures product / configuration gaps found while implementing entity-driven Application Service binding. It is intended for Dynatrace and ServiceNow account teams, plus lab operators.

**Promote timestamp (filter post-cutover noise):** `2026-08-03T14:31:46Z` — also in `tmp/l2i_generic_bind_promote_ts.txt`. Prefer `sys_created_on >=` that time when auditing events/alerts/incidents.

---

## 0. Generic entity CI-bind redesign (2026-08-03)

### Target design

| Layer | Behavior |
| ----- | -------- |
| **Event CI bind** | Prefer OpenPipeline stamps: `spark.as_identifier` → Application Service by **name** (`spark-client` → `Spark Client`; else name equals the identifier string), then optional `identifier` column only if the field is valid and the value matches; else `spark.pod_identifier` → pod CI by name → Contains AS. Else primary ImpactedEntity: `HOST` → host CI (CPU / `spark.event_kind=CPU_EVENT`); `CLOUD_APPLICATION_INSTANCE` → AS via pod Contains; `CUSTOM_DEVICE` kept as legacy fallback only. **No match → leave `cmdb_ci` empty.** |
| **Alert CI bind** | If the alert already has `cmdb_ci`, **keep it**; otherwise run the same generic bind as events. |
| **Incident create** | If the alert has `cmdb_ci`, **use it**; otherwise run the same generic bind. Skip create when still empty. |
| **Propagate** | **Disabled.** CI must be correct on first insert (no event→alert copy safety net). |
| **OOTB AMR `SGO-Dynatrace`** | Remains **inactive** (deploy playbook enforces). |
| **K8s-named BRs/SIs** | Retired (`K8sLogPodCiBind`, `em-*-k8s-log-*`). No K8s-specific bind rules unless called from the generic SI. |

### Active lab artifacts


| Name | Kind | Role |
| ---- | ---- | ---- |
| `ResolveApplicationService` | Script Include | Generic entity→CI (`applyEntityBinding`) |
| `em-event-bind-entity-ci` | BR `em_event` order 5000 | Bind on event insert/update |
| `em-alert-bind-entity-ci` | BR `em_alert` order 5010 | Prefer existing CI; else bind |
| `em-alert-create-log-incident` | BR `em_alert` order 5020 | Prefer alert CI; else bind; create/correlate `Critical log event` |
| `em-event-propagate-entity-ci` | BR `em_event` order 5005 | **Inactive** |

Deploy: `ansible/playbooks/servicenow/incident/deploy.yml`.

### Dynatrace OpenPipeline entities

| Mode | Davis / SN bind | How it is set |
| ---- | --------------- | ------------- |
| Client | `event.type` = `ERROR_EVENT`; `spark.event_kind` = `CRITICAL_LOG_EVENT`; `dt.source_entity` remains OneAgent **HOST**; **SN ignores HOST** when `spark.as_identifier` is present | Custom log source / OpenPipeline stamp `spark.as_identifier=spark-client`; SN resolves AS by name (`Spark Client`) |
| Cluster | Same `ERROR_EVENT` + `spark.event_kind=CRITICAL_LOG_EVENT`; HOST may remain on the problem; **SN ignores HOST** when `spark.pod_identifier` is present | Custom log source stamps `spark.pod_identifier` from path; SN binds AS via pod CI name → Contains |
| Host CPU | `event.type` = `CUSTOM_ALERT`; `spark.event_kind` = `CPU_EVENT` (metric event template) | Primary ImpactedEntity **HOST** → host CI |

Dynatrace Settings API constrains Davis `event.type` to a fixed enum (`ERROR_EVENT`, `CUSTOM_ALERT`, etc.). Lab stamps `spark.event_kind` (`CRITICAL_LOG_EVENT` | `CPU_EVENT`) and **`ResolveApplicationService.applySparkEventTypeRename`** remaps ServiceNow `em_event.type` / `em_alert.type` to those names so the Event Management UI shows the requested Types. Built-in `CPU_SATURATED` is left unchanged.

Davis properties also stamp: `dt.davis.is_merging_allowed=false`, `event.unique_identifier`, `spark.event_kind`, `spark.as_identifier` (Client), `spark.pod_identifier` (Cluster). No `CUSTOM_DEVICE`, `spark.device`, `spark.davis_entity`, or `sn_ci_lookup`.

### Product gap: Cluster CAI mapping cannot happen in OpenPipeline Processing

OpenPipeline **Processing cannot look up entities by name**. Lab **no longer** bakes pod→CAI `fieldsAdd` processors at apply time.

**Workaround (current):** pass `spark.pod_identifier` through the Davis event description / properties to ServiceNow; `ResolveApplicationService` binds Application Service by pod CI name and **does not** use the HOST ImpactedEntity for that path.

**Still desirable from DT:** native OpenPipeline entity lookup, **or** container-context log collection so OneAgent attaches CAI automatically.

Custom log source extracts the pod name from `/mnt/spark/logs/<pod>/…` into `spark.pod_identifier`.

Specs live under `observability/dynatrace/` (flattened; tenant URL from `vars/variables.yaml`, not a `tenants/{id}/` directory).

### Product gap: SGC drops problems without topology CI match unless unmatched-CI events are enabled

**Symptom:** Dynatrace fired brooks-lab webhooks for log problems whose ImpactedEntity is HOST (or otherwise unmatched in SGC topology); some problems did not create SGO events.

**Root cause:** `sn_dynatrace_integ.events_for_unmatched_ci.enabled=false` → syslog `SGO-Dynatrace: Skipping event creation on non matched CI`.

**Lab fix:** set that property to `true` in `ensure_spark_entity_cmdb_bindings.yml` (wired into `events/deploy.yml`). Lab BRs then bind via `spark.as_identifier` / `spark.pod_identifier` (or HOST for CPU).

**Ask SN:** document this property for SGO customers whose Davis primary entity is not in an SGC topology feed.

### Validation snapshot (post-promote)

| Check | Result |
| ----- | ------ |
| Promote | `2026-08-03T14:31:46Z` |
| Stress `run-parallel-all.sh` | exit 0 |
| First audit (all SGO since promote) | 13 events, **0 null `cmdb_ci`**; 12 HOST (CPU / `CUSTOM_ALERT`, `spark.event_kind=CPU_EVENT`) + 1 Cluster log (`spark.pod_identifier` → Spark Master AS) |
| Client path | bind via `spark.as_identifier:spark-client` → Application Service **Spark Client** (`resource` = `spark.as_identifier:spark-client`) |

Filter Spark log rows with problem title / description containing `Spark critical` (or OpenPipeline provider) — do not judge L2I entity quality from all `source=SGO-Dynatrace` rows (CPU HOST noise).

---

## 1. OOTB `SGO-Dynatrace` alert management rule creates incidents before CI bind

### Documentation

ServiceNow product docs (generic AMR, not SGO-specific):

- [Create an alert management rule](https://www.servicenow.com/docs/r/it-operations-management/event-management/create-alert-management-rule.html)
- Related pattern: leave task template empty → `EvtMgmtCustomIncidentPopulator` for field mapping (community / docs), which **populates** the incident the AMR creates — it does **not** attach an arbitrary Business Rule into the AMR.

There is no rich in-instance “design doc” on this SGO rule beyond its record fields and the parent Store app description.

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
| Active (lab)         | `**false**`                                                                                                                                                                                                                                            | **Yes — this is the OOTB rule we turned off**        |
| Sys id               | `7f5e284e07032010b1306a77c4a93523`                                                                                                                                                                                                                     |                                                      |
| Deep link            | [https://optimizincdemo1.service-now.com/nav_to.do?uri=em_alert_management_rule.do?sys_id=7f5e284e07032010b1306a77c4a93523](https://optimizincdemo1.service-now.com/nav_to.do?uri=em_alert_management_rule.do?sys_id=7f5e284e07032010b1306a77c4a93523) |                                                      |


AMRs typically evaluate on a short delay after alert update (product default ~5s via `evt_mgmt.alert_rule_delay`). That delay is **not** a guaranteed “wait until Application Service bind finishes.”

Lab custom creator for comparison:


| Field     | Value                                                                                                                                                                                                                      |
| --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Name      | `em-alert-create-log-incident` (formerly `em-alert-create-k8s-log-incident`)                                                                                                                                               |
| Table     | `sys_script` (Business Rule on `em_alert`)                                                                                                                                                                                 |
| Filter    | `source=SGO-Dynatrace^severity<=3`                                                                                                                                                                                         |
| Order     | `5020` (runs after bind BR `5010`)                                                                                                                                                                                         |
| Sys id    | *(re-resolved after rename — look up by name)*                                                                                                                                                                             |
| Deep link | Search `sys_script` name `em-alert-create-log-incident` on optimizincdemo1                                                                                                                                                 |




### Can we “link” our K8s BR into this AMR?

**No.** AMRs and Business Rules are parallel mechanisms:


| Mechanism                                                          | Role                                                            |
| ------------------------------------------------------------------ | --------------------------------------------------------------- |
| AMR `SGO-Dynatrace`                                                | Product-supported alert → incident (all `source=SGO-Dynatrace`) |
| BR `em-alert-create-log-incident`                                  | Lab create/correlate after generic entity bind                  |
| BR `em-alert-bind-entity-ci` / SI `ResolveApplicationService`      | Generic entity → CI bind (not part of the AMR)                  |


You do **not** register a BR inside an AMR. Options that *are* supported:

1. **Keep OOTB AMR off** for lab; use bind BRs + `em-alert-create-log-incident` for log-to-incident (current).
2. **Narrow OOTB AMR filter** so it only covers standard SGO classes you want OOTB to handle (e.g. host CPU), and **exclude** Spark log / `ERROR_EVENT` (or require `cmdb_ci` class Application Service).
3. **Replace** OOTB create with a **custom AMR** whose filter requires `cmdb_ciISNOTEMPTY` (and ideally Application Service class) — optionally use `EvtMgmtCustomIncidentPopulator` for field mapping.
4. Do **not** run OOTB AMR **and** `em-alert-create-log-incident` together for the same alerts (dual creators).



### Does moving create into the AMR eliminate the CI race?

**Partially, only if the AMR filter requires a bound Application Service CI** (and bind BRs run before the AMR evaluates). Simply “using the AMR instead of the BR” with today’s filter (`source=SGO-Dynatrace` only) does **not** fix the race — that is what created empty-CI incidents.

Using AMR *with* `cmdb_ci` / class conditions can mitigate because of the ~5s delay **plus** re-match on update (`Alert matches filter`), but bind BRs remain mandatory; the AMR must not create until bind succeeded.

### Issue

OOTB rule creates an incident as soon as an SGO alert matches. It does **not** require Application Service `cmdb_ci`. Lab observed empty-CI incidents while the alert later received Spark Master / Spark Client.

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

Dual incident creators when OOTB is active. OOTB often wins with an empty CI. Operators see ITSM incidents that cannot be routed by Application Service. Manual Table API fixes to `incident.cmdb_ci` often do not stick (see §5).

### Recommendation

1. Keep OOTB inactive **or** narrow it to non–log-to-incident SGO alerts (CPU / infra) with standard SGO processing.
2. Log-to-incident stays on bind BRs + `em-alert-create-log-incident` (or a dedicated AMR that requires Application Service CI).
3. Ask SN for a product pattern: “SGO incident AMR must not fire until CI bind complete.”

Lab currently keeps OOTB **inactive** for validation.

### Best practice: growing technology-dependent CI patterns (AMR vs BR)

Goal: inbound events/alerts may carry different Dynatrace entity / CI types; a **single generic bind SI** promotes them to the desired alert/incident CI (host CI or Application Service). Prefer **entity-type methods inside one SI** over separate K8s-named BRs.


| Layer                           | Mechanism                                                 | Owns                                                                                       | Grows how                                                                                            |
| ------------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| **A. Entity → working CI**      | Script Include + thin Business Rules                      | Parse primary `ImpactedEntities`; bind HOST, CUSTOM_DEVICE, CAI→AS, etc.                   | Add methods on `ResolveApplicationService`; keep BR names entity-agnostic                            |
| **B. When to open an incident** | Alert Management Rule (AMR) **or** create BR              | Filter which alerts get incidents                                                          | One policy for infra vs application-log; do not mix bind logic into OOTB AMR                         |
| **C. Field polish on create**   | `EvtMgmtCustomIncidentPopulator` (optional)               | Map alert fields → incident fields when an AMR creates the task                            | Shared helpers; still not entity-bind logic                                                          |


**Recommended split for SGO-Dynatrace:**

1. **Do not** put growing entity→CI logic inside the OOTB AMR.
2. **Do** keep bind logic in **`ResolveApplicationService`** called from thin BRs filtered by `source=SGO-Dynatrace`.
3. **Replace or narrow** OOTB AMR `SGO-Dynatrace` rather than customizing it in place.
4. Prefer **deactivating OOTB** and adding named replacement AMRs over editing the Store-shipped record.
5. Package as update sets / scoped app + git (`servicenow/integrations/…`).

**Will an AMR that “overrides” OOTB eliminate CI races?** Only if its filter **requires the post-bind CI**. The AMR remains the *incident policy* layer; BRs/SIs remain the *entity pattern* layer.

---



## 2. Dual Dynatrace → ServiceNow problem notifications (legacy vs SGO)



### What “ServiceNow Demo 1 - Optimiz” is

It is a **Dynatrace problem notification** (Settings → Problems → Notifications), **not** a ServiceNow Business Rule or Script Include.


| Field                                   | Value                                                                                                                                                                                                                                                                        |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Display name                            | `ServiceNow Demo 1 - Optimiz`                                                                                                                                                                                                                                                |
| Webhook URL                             | `https://optimizincdemo1.service-now.com/api/sn_em_connector/em/inbound_event?source=dynatrace&sys_id=712a39811ba483105488a937b04bcba5`                                                                                                                                      |
| Effect on SN                            | Creates `em_event` / `em_alert` with `**source=Dynatrace**` (legacy connector)                                                                                                                                                                                               |
| Alerting profile                        | `DemoProfile - Optimiz` (no MZ filter)                                                                                                                                                                                                                                       |
| Lab state                               | **Disabled** (keep disabled until exclusive routing is configured)                                                                                                                                                                                                           |
| UI (list — use this if object URL 404s) | [https://pdt20158.apps.dynatrace.com/ui/apps/dynatrace.classic.problems/#settings/builtin:problem.notifications](https://pdt20158.apps.dynatrace.com/ui/apps/dynatrace.classic.problems/#settings/builtin:problem.notifications) — then open **ServiceNow Demo 1 - Optimiz** |
| Alternate classic list                  | [https://pdt20158.live.dynatrace.com/#settings/integration/problemnotifications](https://pdt20158.live.dynatrace.com/#settings/integration/problemnotifications)                                                                                                             |
| Settings objectId                       | `vu9U3hXa3q0AAAABAB1idWlsdGluOnByb2JsZW0ubm90aWZpY2F0aW9ucwAGdGVuYW50AAZ0ZW5hbnQAJDZmMmIxYzg0LTE0OWEtMzkyOS04Y2Y4LWI2YzBiMTU3MTBmOb7vVN4V2t6t`                                                                                                                               |


Brooks-lab (new-school) notification:


| Field            | Value                                                                                           |
| ---------------- | ----------------------------------------------------------------------------------------------- |
| Display name     | `ServiceNow brooks-lab - Spark Observability`                                                   |
| Webhook URL      | `…/inbound_event?source=SGO-Dynatrace`                                                          |
| Alerting profile | `Spark Observability - ServiceNow brooks-lab` (scoped to MZ **Spark Observability**)            |
| Enabled          | Yes                                                                                             |
| UI list          | Same problem-notifications list as above — open **ServiceNow brooks-lab - Spark Observability** |


**Clarification:** Demo 1 is a **problem notification + alerting profile**, not an OpenPipeline. The Spark log OpenPipeline that *creates* Davis problems is separate:


| OpenPipeline     | Value                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------------ |
| Display name     | **Spark Lab - log alerts**                                                                             |
| customId         | `spark-lab-log-alerts`                                                                                 |
| Schema           | `builtin:openpipeline.logs.pipelines`                                                                  |
| Davis processors | `spark-client-warn-error-davis`, `spark-cluster-warn-error-davis`, `spark-enrichment-missing-davis`    |
| Repo             | `observability/dynatrace/integrations/spark-openpipeline-log-alerts-pipeline.json.j2` |




### Do lab BRs / SIs still match `source=Dynatrace`?

**No.** After the SGO-only cutover, filters and script guards are SGO-only:


| Artifact                                 | Source condition                                                                                       |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `em-event-bind-entity-ci`                | `filter_condition=source=SGO-Dynatrace`                                                                |
| `em-event-propagate-entity-ci`           | **inactive**; was `source=SGO-Dynatrace`                                                               |
| `em-alert-bind-entity-ci`                | `filter_condition=source=SGO-Dynatrace`                                                                |
| `em-alert-create-log-incident`           | `filter_condition=source=SGO-Dynatrace^severity<=3` plus `current.source !== 'SGO-Dynatrace' → return` |


Legacy `source=Dynatrace` rows are **ignored** by this automation (by design).

### Why dual webhooks are an issue / how Spark logs became `source=Dynatrace`

Dynatrace can fire **multiple** problem notifications for the same problem when each notification’s alerting profile matches.

1. **Demo 1** used a broad profile (`DemoProfile - Optimiz`) with **no management-zone filter** → matched Spark Client / Master Davis problems → posted to the **legacy** inbound URL → SN stamped `**source=Dynatrace`**.
2. **Brooks-lab** used the MZ-scoped profile → only problems whose impacted entities are in MZ **Spark Observability** post to `**source=SGO-Dynatrace`**.
3. During stress (before Demo 1 was disabled), Spark log `ERROR_EVENT` alerts appeared almost entirely as `source=Dynatrace` with empty CI. Host CPU problems in the MZ appeared as `source=SGO-Dynatrace`.

So Spark logs did **not** “choose” Dynatrace inside ServiceNow. **Dynatrace routed them to the legacy webhook** because Demo 1 was still enabled and matched those problems.

### Do we tweak DT problems or SN event processing?

Prefer **Dynatrace routing**, not SN dual-path processing:


| Approach                                                   | Recommendation                                                                                                           |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Keep Demo 1 disabled (or MZ-exclude Spark Observability)   | **Yes** for lab cutover — legacy rules stay on `source=Dynatrace` for whatever still uses Demo 1; new-school only on SGO |
| Re-add `source=Dynatrace` to lab BRs                       | **No** — that re-entangles connectors and blocks the SGO-only model                                                      |
| Ensure Spark entities are in MZ used by brooks-lab profile | **Yes** (see §4) so new-school problems always hit SGO                                                                   |
| SN: separate legacy connector vs SGO connector             | Already separated by inbound `source=` query param; keep BR filters aligned                                              |


**Desired end state:** both notifications may be **enabled**, but each problem is delivered to **exactly one** webhook:

- Spark Observability MZ (CPU **and** Spark log Davis problems) → brooks-lab → `source=SGO-Dynatrace`  
- Everything else intended for the Optimiz demo → Demo 1 → `source=Dynatrace`

Log-to-Incident BRs remain SGO-only. CPU / infra in the MZ should use **standard SGO** processing (OOTB AMR / SGO bind) — outside Log-to-Incident scope once OOTB is safely narrowed.

### Best practice / minimal Demo-side change (recommendation — **do not apply yet**)

Routing belongs on **alerting profiles / problem notifications**, not on the Spark OpenPipeline (OpenPipeline *creates* problems; notifications *fan out*).

**Preferred minimal change to keep Demo 1 on without stealing lab problems:**

1. Edit alerting profile `**DemoProfile - Optimiz**` (the profile attached to Demo 1).
2. Add a **management zone** constraint that is **disjoint** from **Spark Observability**, **or** add an **event / entity filter** that excludes:
  - management zone **Spark Observability**, and/or  
  - tag `Project:spark-observability`, and/or  
  - entities `CUSTOM_DEVICE` named Spark Client / `CLOUD_APPLICATION` name `spark-*`.
3. Leave brooks-lab profile as the **only** profile that includes MZ **Spark Observability**.
4. Re-enable Demo 1 only after verifying a Spark log problem and a lab CPU problem produce `**source=SGO-Dynatrace` only** (no twin `source=Dynatrace` row).

**Avoid** changing Spark OpenPipeline Davis processors for this — they should keep creating lab problems; the Demo notification should simply not select them.

**Avoid** teaching SN BRs to accept both sources for the same workload — that hides dual delivery instead of fixing it.

### MZ vs tags on alerting profiles (Dynatrace UI note)

The Alerting Profiles form says entities in the configured MZ match the profile and *“It is recommended to use manual tags instead.”* That is about **assignment lag / consistency**, not “do not use MZ for ServiceNow.”

- **MZ filter:** still valid to scope a team or lab; can lag when rules are complex (we saw CAI outside MZ until a workload rule was added).  
- **Tag filter (preferred for notification routing):** use **manual** or **API/OneAgent-applied** tags on the entities that own the problem (auto-tag rules have the same delay caveat). Example keys: `Integration:SGO-ServiceNow` or existing `Project:spark-observability` if applied immediately to CUSTOM_DEVICE / spark workloads / hosts.  
- **Practical pattern:** MZ for access / partitioning; **stable tags** on severity rules for *which webhook* gets the problem (brooks-lab vs Demo 1). Both filters AND with severities/event filters.



### Impact

While both were enabled with overlapping profiles, Spark log incidents were created by **legacy** EM paths with empty CI, and lab SGO BRs never ran on those alerts.

### Recommendation (lab ops)

Until DemoProfile is exclusivity-filtered, keep Demo 1 **disabled**. Then re-enable with the minimal profile filter above.

---



## 3. CUSTOM_DEVICE → Application Service mapping (and what “SOS” means)



### What “SOS” means

**SOS =** `sys_object_source` — ServiceNow’s table that maps an external system’s object id to a CMDB CI.

For SGC / SGO-Dynatrace imports, rows typically look like:

- `name` = `SGO-Dynatrace` (discovery / event source)
- `id` = Dynatrace entity id (e.g. `CUSTOM_DEVICE-BF87A767187C320F` or a compound import id containing it)
- `target_table` / `target_sys_id` = CMDB CI

SGO inbound event matching uses these rows (and related key/value data) to suggest `em_event.cmdb_ci`.

### Issue observed in lab

Automation could not reliably **insert** a bare-id SOS row for the Spark Client `CUSTOM_DEVICE` pointing at Application Service **Spark Client** (ACL / SGC ownership). Lab fell back to:

1. `cmdb_key_value` with key `Dynatrace Instance` = entity id, and/or
2. **By-name convention:** Application Service name **equals** CUSTOM_DEVICE display name (e.g. both `Spark Client`).

Relevant SI logic (`ResolveApplicationService`):

```javascript
// resolveApplicationServiceFromCustomDevice
// Order: SOS → cmdb_key_value → AS name == device display name
if (deviceName) {
  var asByName = new GlideRecord('cmdb_ci_service_discovered');
  asByName.addQuery('name', deviceName);
  // ...
  return { sysId: asByName.sys_id.toString(),
           how: 'Application Service name matches CUSTOM_DEVICE display name' };
}
```



### Clarification for the Spark team

The durable, data-driven contract **does not require hard-coded paths**. It requires:

1. Dynatrace **CUSTOM_DEVICE** whose display name identifies the client application (e.g. `Spark Client`).
2. Matching ServiceNow **Application Service** (`cmdb_ci_service_discovered`) with the **same name**.
3. Optionally a proper SGO SOS (or supported SGC feed) from device → AS when product ACLs allow it.

The Spark team can create the device and the matching Application Service; binding then follows the name (and SOS when present).

### Impact

Without SOS **or** name match **or** `cmdb_key_value`, client-mode alerts cannot resolve an Application Service even when ImpactedEntities correctly list the CUSTOM_DEVICE.

### Recommendation

- Product: allow SGC / automation to upsert CUSTOM_DEVICE → Application Service SOS (or ship a Custom Devices feed).  
- Process: document the **name-parity** convention for app teams.  
- Lab: keep name match + key/value as fallbacks until SOS ACL is resolved.

---



## 4. Management zone missing Kubernetes workloads (`CLOUD_APPLICATION spark-*`)



### What “Master CAI” means

**CAI = Cloud Application Instance** — Dynatrace entity type `CLOUD_APPLICATION_INSTANCE`.  
Example for Spark Master in lab:

- Entity id: `CLOUD_APPLICATION_INSTANCE-4F2D46089A9D634B`  
- Display name: `spark-master-0`  
- Role: Davis `dt.source_entity` / ImpactedEntities target for **cluster-mode** Spark log problems (OpenPipeline remapping).



### Why it was not in the right MZ

MZ **Spark Observability** originally had rules for:

- HOST in host group `spark-observability`  
- KUBERNETES_CLUSTER `brooks-lab`  
- CUSTOM_DEVICE named `Spark Client`

It did **not** include Kubernetes **workloads** (`CLOUD_APPLICATION`) named `spark-`*. Dynatrace MZ schema exposes workload (`CLOUD_APPLICATION`), not CAI instance, as a first-class ME rule type. CAI `spark-master-0` therefore showed `**managementZones: []`** even though the cluster rule existed (no automatic CAI inheritance in practice for these instances).

Brooks-lab problem notification is **MZ-filtered**. Problems whose primary impacted entity is a CAI outside the MZ may not notify SGO (while Demo 1’s unscoped profile still would — see §2).

### Fix applied in lab

Added MZ rule:

- Entity type: `CLOUD_APPLICATION`  
- Condition: name `BEGINS_WITH` `spark-`

Repo file: `observability/dynatrace/management-zones/spark-observability/management-zone.json`.

### Impact

Master / worker log problems could miss the SGO webhook or be inconsistently notified vs Client CUSTOM_DEVICE (which was already in the MZ).

### Recommendation

Keep workload (`spark-*`) rules in the MZ definition. Confirm CAI instances inherit or appear under the MZ after the workload rule. Account teams: document that MZ-scoped SGO notifications require **all** Davis impacted entity types used by OpenPipeline (CUSTOM_DEVICE + workloads/CAIs), not only hosts.

---



## 5. Incident `cmdb_ci` via Table API vs Business Rule GlideRecord



### What was tried

During RCA of an incident created by OOTB EM with **empty** `cmdb_ci`, an agent used the ServiceNow **Table API** (REST `PATCH`/`PUT` on `/api/now/table/incident/{sys_id}`) to set `cmdb_ci` to Application Service **Spark Master** after the fact.

- **Work notes** updates via the same API **succeeded**.  
- `**cmdb_ci` updates via Table API often did not persist** (read-back still empty).

That was a **diagnostic / repair attempt**, not the supported runtime path. Runtime must not depend on Cursor or Ansible “later REST updates” to EM/ITSM records.

### What works

Business Rule `**em-alert-create-log-incident**` sets `cmdb_ci` on insert through server-side `GlideRecord`:

```javascript
var inc = new GlideRecord('incident');
inc.initialize();
inc.cmdb_ci = asSysId;
inc.short_description = 'Critical log event';
// ...
var incSysId = inc.insert();
current.incident = incSysId;
```

If an incident is already linked but has the wrong CI, the same BR updates via GlideRecord:

```javascript
linkedInc.cmdb_ci = asSysId;
linkedInc.work_notes = 'Corrected CI from alert ' + current.number;
linkedInc.update();
```



### Impact

Empty-CI incidents created by OOTB cannot be reliably repaired by external REST. The durable fix is **prevent empty-CI create** (deactivate/narrow OOTB; use bind-then-create BR).

### Recommendation

- Do not document Table API `cmdb_ci` repair as an operational procedure.  
- Prefer BR/SI/native EM for all event/alert/incident mutations.  
- Product: explain why `incident.cmdb_ci` is ignored or overridden on Table API writes in this scope (ACLs, data policies, EM reconciliation).

---



## 6. Related lab automation (reference)


| Name | Kind | Role | Notes |
| ---- | ---- | ---- | ----- |
| `ResolveApplicationService` | Script Include | Generic entity→CI (HOST / CUSTOM_DEVICE / CAI); processing notes; DQL text enrich | Active |
| `em-event-bind-entity-ci` | BR `em_event` order 5000 | Bind on event | Active |
| `em-event-propagate-entity-ci` | BR `em_event` order 5005 | Former event→alert CI copy | **Inactive** |
| `em-alert-bind-entity-ci` | BR `em_alert` order 5010 | Prefer existing CI; else bind | Active |
| `em-alert-create-log-incident` | BR `em_alert` order 5020 | Create/correlate `Critical log event` when CI bound | Active |
| `K8sLogPodCiBind` / `em-*-k8s-*` | Legacy | Renamed/retired | **Inactive** |



### Note on propagate

**Disabled by design** (2026-08-03). Prefer correct first-insert bind on event and alert BRs. If CI still disagrees within a `message_key` set, investigate OPEN vs RESOLVED ImpactedEntities or SGO native vs lab bind — do not re-enable propagate as the default.

---



## 7. SGO `ERROR_EVENT` with `resource` = log file path



### Symptom

Historical `source=SGO-Dynatrace` alerts of `type=ERROR_EVENT` show short descriptions like:

`ERROR_EVENT: Spark Client (/mnt/spark/client-logs/spark-app.log)`

i.e. `**em_alert.resource` = log path**, not `CUSTOM_DEVICE-…` / `CLOUD_APPLICATION_INSTANCE-…`.

Example: Alert0015252 (2026-08-01) — `resource=/mnt/spark/client-logs/spark-app.log`, while `additional_info.ImpactedEntities` was still `**HOST` Lab3** (pre–CUSTOM_DEVICE remapping). Description contained legacy `--- L2I enrichment ---` (old SI that ran Grail and URL enrichment).

### How those are generated

1. **OpenPipeline** (`Spark Lab - log alerts` / `spark-lab-log-alerts`) creates a Davis `ERROR_EVENT` from WARN/ERROR log lines. Early problems impacted the **HOST** (or carried log-file context in problem title/evidence).
2. **Brooks-lab problem notification** posts to SGO inbound (`source=SGO-Dynatrace`).
3. **SGO / EM** compose alert identity fields; `short_description` uses the pattern `ERROR_EVENT: <node> (<resource>)`. When `resource` was filled from log-file / problem evidence (not from our entity stamp), the path appears in the UI.
4. Older lab SI enrichment also rewrote description (and effectively accepted path-oriented identity).

This is **not** the current declarative contract. Current `ResolveApplicationService.applyEntityBinding` **overwrites** `resource` with the Dynatrace entity id when CUSTOM_DEVICE or CAI is present:

```javascript
gr.resource = entity.entityId;  // e.g. CUSTOM_DEVICE-… or CLOUD_APPLICATION_INSTANCE-…
gr.node = entity.name;
```

Post-cutover example: Alert0015317 has `resource=CLOUD_APPLICATION_INSTANCE-4F2D46089A9D634B`, `node=spark-master-0`.

### Recommendation

Treat path-valued `resource` as a **legacy / pre-remap** signal. New Spark log problems should show entity ids in `resource` after bind. If new SGO alerts still get path `resource` with HOST-only ImpactedEntities, fix OpenPipeline Davis `dt.source_entity` / remapping — not SN path matching.

---



## 8. How to narrow SGO processing for infrastructure (CPU / host)

Log-to-Incident BRs should **not** own host CPU. Standard SGO should.

**Target split:**


| Alert class         | Example `em_alert.type` / signal        | CI bind                            | Incident create                                                  |
| ------------------- | --------------------------------------- | ---------------------------------- | ---------------------------------------------------------------- |
| Infra / host        | `CPU_SATURATED`, host `CUSTOM_ALERT`, … | Generic bind → HOST CI             | Narrowed **infra AMR** (re-enable OOTB or clone) when ready      |
| Spark / K8s app log | `ERROR_EVENT` from OpenPipeline Davis   | Generic bind → Application Service | `em-alert-create-log-incident` (or log AMR with CI required)     |


**Minimal way to narrow (lab):**

1. Keep bind/create BRs entity-generic; create BR already skips when `cmdb_ci` empty — optionally add `type=ERROR_EVENT` to create BR filter.
2. **Re-enable** OOTB AMR `SGO-Dynatrace` **only after** changing its alert filter from bare `source=SGO-Dynatrace` to something that **excludes** log `ERROR_EVENT`.
3. Set **Multiple alert rules** carefully when using two AMRs.
4. Validate with one host CPU problem and one Spark log problem — no dual incidents.

Until that filter is applied, leaving OOTB **inactive** avoids empty-CI races on log alerts.

---



## 9. Dynatrace UI navigation (no deep links)

Tenant in browser: `https://pdt20158.apps.dynatrace.com` (or classic `https://pdt20158.live.dynatrace.com`).

### A. Problem notification (Demo 1 vs brooks-lab)

1. Open the Dynatrace environment (pdt20158).
2. Click the **cog / Settings** (left rail or app switcher → **Settings**).
3. Go to **Alerting** → **Problem notifications**
  (Classic path sometimes labeled **Settings → Integration → Problem notifications**).
4. In the list, open:
  - **ServiceNow Demo 1 - Optimiz** (legacy webhook → `source=dynatrace`)  
  - **ServiceNow brooks-lab - Spark Observability** (SGO webhook → `source=SGO-Dynatrace`)
5. On each notification, note **Alerting profile** and **Webhook URL**.

There are **no Davis processors** on the notification. Notifications only *select* problems via the alerting profile and POST them.

### B. Alerting profile (what Demo 1 matches)

1. Settings → **Alerting** → **Problem alerting profiles**.
2. Open **DemoProfile - Optimiz** (used by Demo 1) and **Spark Observability - ServiceNow brooks-lab** (used by brooks-lab).
3. Check **Management zone**, severity rules, and any event filters.
  - To stop Demo 1 from stealing lab problems: exclude MZ **Spark Observability** on DemoProfile (recommendation; not applied yet).



### C. OpenPipeline Davis processors (what *creates* Spark log problems)

Legacy **Demo 1 does not create** Spark log problems. Creation is OpenPipeline → Davis event → problem; then notifications fan out.

1. Settings → **Process and contextualize** → **OpenPipeline** → **Logs**.
2. Open the **Pipelines** tab.
3. Open pipeline **Spark Lab - log alerts** (`customId` `spark-lab-log-alerts`).
4. Open the **Davis** tab (not only Processing).
5. Inspect processors:
  - `spark-client-warn-error-davis`  
  - `spark-cluster-warn-error-davis`  
  - `spark-enrichment-missing-davis`

To see a live problem’s entity: **Problems** app → open problem → **Impacted entities** (CUSTOM_DEVICE / CAI / HOST).

---



## 10. Lab actions already taken (not product changes)

1. OOTB `SGO-Dynatrace` alert management rule → **inactive** (enforced on deploy).
2. Dynatrace notification **ServiceNow Demo 1 - Optimiz** → **disabled** (until DemoProfile exclusivity filter exists).
3. MZ **Spark Observability** → HOST / K8s cluster / CUSTOM_DEVICE Spark Client / `CLOUD_APPLICATION` `spark-*` rules.
4. Lab BRs/SIs → renamed to entity-generic; SGO-only; primary-entity bind; no match → empty `cmdb_ci`.
5. Propagate BR → **inactive**.
6. `sn_dynatrace_integ.events_for_unmatched_ci.enabled=true` so CUSTOM_DEVICE problems create `em_event`s.
7. CUSTOM_DEVICE tagged `Project:spark-observability`.
8. OpenPipeline: Client → CUSTOM_DEVICE; Cluster → CAI via lab bake-in; `dt.davis.is_merging_allowed=false`.

---



## 11. Ask for account teams

1. **SN:** Official guidance to delay or gate OOTB SGO incident creation until CI is present; or support replacing it with a scoped custom rule without dual creators. Clarify AMR vs BR for SGC customers.
2. **DT:** Best practice for two problem notifications on one tenant with **exclusive** alerting-profile / MZ filters (Demo vs Spark Observability).
3. **SN SGC:** CUSTOM_DEVICE → Application Service SOS upsert permissions or a Custom Devices import feed; document `events_for_unmatched_ci.enabled` for CUSTOM_DEVICE primary entities.
4. **DT:** Confirm CAI / workload MZ membership behavior for Kubernetes entities used as Davis `dt.source_entity`.
5. **DT:** OpenPipeline **native** pod-name → `CLOUD_APPLICATION_INSTANCE` lookup (Processing cannot do live entity enrichment today).
6. **SN:** Document why Table API updates to `incident.cmdb_ci` may no-op while GlideRecord in a BR succeeds.
7. **SN SGO:** How `em_alert.resource` is chosen for Davis log `ERROR_EVENT` (entity id vs log file path).

