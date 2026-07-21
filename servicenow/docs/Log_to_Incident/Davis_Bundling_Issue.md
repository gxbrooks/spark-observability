# Davis problem bundling — worked example (Alert0014495)

This document records a **real lab incident** from 2026-07-09 where Dynatrace Davis bundled client-side and service-side Spark log events into one problem, and ServiceNow alert CI assignment followed the **service-side pod path** instead of the host or Spark Client Application Service.

Related normative discussion: [Log_to_Incident.adoc — Known limitation — Davis problem bundling](Log_to_Incident.adoc#known-limitation-davis-bundling).

## Context

After moving application logs off NFS to **node-local** `/mnt/spark/logs` (see [spark/docs/nfs-mounts.md](../../../spark/docs/nfs-mounts.md)), a full chapter load on Lab3 produced WARN/ERROR lines in:

| Log | Path |
|-----|------|
| Client driver | `/mnt/spark/logs/spark-client/lab3/spark-app.log` |
| Spark master pod | `/mnt/spark/logs/spark-master-0/spark-app.log` |

OneAgent on Lab3 was restarted so custom log paths reported `FILE_STATUS_OK`. Dynatrace attributed both event types to **Lab3 host only** (`dt.source_entity: HOST-D8207A117616460E`) — the NFS triple-host duplication was fixed.

## The bundled problem

Davis correlated concurrent chapter activity into **one problem** (P-2607343), detected at **11:45 UTC** on 2026-07-09. ServiceNow received a **single** SGO-Dynatrace alert whose description concatenates **both** log-derived events.

### Alert0014495 (SGO-Dynatrace)

| Field | Value |
|-------|-------|
| **Number** | Alert0014495 |
| **Source** | SGO-Dynatrace |
| **Created** | 2026-07-09 07:46:21 (CDT) |
| **`node`** | `spark-master-0` |
| **`cmdb_ci`** | **spark-master-0** (`cmdb_ci_kubernetes_pod`) |
| **Dynatrace host in text** | Lab3 |
| **`dt.source_entity`** | `HOST-D8207A117616460E` (Lab3 only) |

**Bundled event 1 — client-side:**

```
Application log WARN on spark-client-lab3
Application WARN on /mnt/spark/logs/spark-client/lab3/spark-app.log:
  2026-07-09 06:45:09 WARN Utils:244 - Set SPARK_LOCAL_IP if you need to bind to another address
dt.davis.event_timeout: 15m
dt.source_entity: HOST-D8207A117616460E
event.name: Application log WARN on spark-client-lab3
event.type: ERROR_EVENT
```

**Bundled event 2 — service-side:**

```
Application log WARN on spark-master-0
Application WARN on /mnt/spark/logs/spark-master-0/spark-app.log:
  2026-07-09 06:45:30 WARN Master:250 - Got status update for unknown executor app-20260709064510-0008/12
dt.davis.event_timeout: 15m
dt.source_entity: HOST-D8207A117616460E
event.name: Application log WARN on spark-master-0
event.type: ERROR_EVENT
```

**Legacy child alert:** Alert0014496 (Dynatrace) at the same timestamp → **INC0013902** on **lab3** host CI (“Multiple infrastructure problems”), not Spark Client AS.

## Why `cmdb_ci` was spark-master-0, not Lab3

Dynatrace and the initial SGO webhook bound the problem to the **Lab3 host** via `HOST-D8207A117616460E` → `sys_object_source` → `cmdb_ci_linux_server` (lab3).

ServiceNow then ran **`K8sLogPodCiBind.applyPodBinding()`**, which skipped `spark-client` and rebound to **`spark-master-0`**.

## Remediation (implemented 2026-07-20)

### Dynatrace — distinct `dt.source_entity` for clients

| Change | Location |
|--------|----------|
| CUSTOM_DEVICE **Spark Client** (`customDeviceId=spark-client`, `uiBased=true`) | `apply_spark_client_custom_device.yml` |
| MZ rule: `CUSTOM_DEVICE` ENTITY_NAME = Spark Client | `management-zones/spark-observability/management-zone.json` |
| OpenPipeline `resolve-spark-client-entity`: `lookupEntity(CUSTOM_DEVICE, "Spark Client")` | `spark-openpipeline-log-alerts-pipeline.json.j2` |

Client Davis events must **not** remain on the OneAgent HOST. They bind to **`CUSTOM_DEVICE-…`** so Davis does not merge them with service-side HOST/pod events on Lab3.

Deploy: `ansible/playbooks/servicenow/sgc/sources/dynatrace/events/deploy.yml` (requires `entities.write` on `DT_API_TOKEN`).

### ServiceNow — bind alerts/incidents to Spark Client AS

| Change | Behavior |
|--------|----------|
| `ResolveApplicationService.applySparkClientAlertBinding()` | Sets `em_event` / `em_alert.cmdb_ci` to Application Service **Spark Client** when `/logs/spark-client/` is present; `message_key` prefix `SparkClient-` |
| Bind BRs (`em-event-bind-…`, `em-alert-bind-…`) | Call client bind **first**; only then `K8sLogPodCiBind` |
| `K8sLogPodCiBind` | **No-op** when text contains `/logs/spark-client/` |
| `em-alert-create-k8s-log-incident` | Aligns `em_alert.cmdb_ci` with resolved AS (Spark Client or Contains parent) |

Deploy: `ansible/playbooks/servicenow/incident/deploy.yml`.

**Incident CI** for clients remains **`cmdb_ci_service_discovered` Spark Client** (`identifier: spark-client`) — never a laptop/mobile host CI.

## Comparison: before vs after local logs

| Aspect | Pre-fix (NFS-shared logs) | Post-fix (local logs + OneAgent restart) |
|--------|---------------------------|------------------------------------------|
| Client `dt.source_entity` | Lab1, Lab2, **and** Lab3 | **Lab3 only** (pre-CUSTOM_DEVICE) |
| Client `event.name` | `… on spark-client-lab3-par-a-*` | `… on spark-client-lab3` |
| Master alerts | Triplicated across all hosts | **Lab3 only** in same problem |
| Alert `cmdb_ci` | Often spark-master-0 (pod bind) | Still spark-master-0 when bundled (pre-SN remediation) |

## Validation checklist (after remediation deploy)

1. Confirm CUSTOM_DEVICE exists and is in MZ **Spark Observability**.
2. Emit a client WARN; problem `dt.source_entity` starts with `CUSTOM_DEVICE-` (not `HOST-D8207A117616460E`).
3. Concurrent master WARN should be a **separate** Davis problem (or at least not share the client entity).
4. SGO `em_alert.cmdb_ci` = **Spark Client**; incident on Spark Client AS.
5. Service-only master WARN still binds alert to **spark-master-0** pod → incident Spark Master AS.

## References

| Artifact | Location |
|----------|----------|
| CUSTOM_DEVICE apply | `ansible/.../tasks/apply_spark_client_custom_device.yml` |
| OpenPipeline client entity | `resolve-spark-client-entity` in `spark-openpipeline-log-alerts-pipeline.json.j2` |
| `ResolveApplicationService` | `servicenow/integrations/incident/ResolveApplicationService.si.js` |
| `K8sLogPodCiBind` | `servicenow/integrations/incident/K8sLogPodCiBind.si.js` |
| NFS / local logs contract | `spark/docs/nfs-mounts.md` |
