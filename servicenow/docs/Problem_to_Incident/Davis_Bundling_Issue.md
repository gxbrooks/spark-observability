# Davis problem bundling — worked example (Alert0014495)

This document records a **real lab incident** from 2026-07-09 where Dynatrace Davis bundled client-side and service-side Spark log events into one problem, and ServiceNow alert CI assignment followed the **service-side pod path** instead of the host or Spark Client Application Service.

Related normative discussion: [Problem_to_Incident.adoc — Known limitation — Davis problem bundling](Problem_to_Incident.adoc#known-limitation-davis-bundling).

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

## Why `cmdb_ci` is spark-master-0, not Lab3

Dynatrace and the initial SGO webhook bind the problem to the **Lab3 host** via `HOST-D8207A117616460E` → `sys_object_source` → `cmdb_ci_linux_server` (lab3).

ServiceNow then runs business rule **`em-alert-bind-k8s-log-pod-ci`**, which calls **`K8sLogPodCiBind.applyPodBinding()`** (`servicenow/integrations/incident/K8sLogPodCiBind.si.js`):

1. Scan `description`, `resource`, and `node` for paths matching `/…/logs/<segment>/`.
2. **Skip** segment `spark-client` (client-mode paths are not pod names).
3. For the next valid segment, look up `cmdb_ci_kubernetes_pod` where `name` = segment.
4. Set `em_alert.cmdb_ci` and `em_alert.node` to that pod.

In this alert text:

| Path | Segment after `/logs/` | Binder result |
|------|------------------------|---------------|
| `/mnt/spark/logs/spark-client/lab3/spark-app.log` | `spark-client` | Skipped |
| `/mnt/spark/logs/spark-master-0/spark-app.log` | `spark-master-0` | **Pod CI found → wins** |

So **`cmdb_ci = spark-master-0`** is intentional **service-side pod rebind**, not Dynatrace mis-attribution. The hostname `lab3` appears only as the **second** path segment under `spark-client/` and is never considered for pod binding.

OpenPipeline **`resolve-k8s-pod-entity`** remains **disabled** so problems stay on HOST inside the Spark Observability management zone; ServiceNow performs pod rebind from log paths instead.

## Why incident CI was not Spark Client

Business rule **`em-alert-create-k8s-log-incident`** should resolve **Spark Client** Application Service when alert text contains `/logs/spark-client/`. In this run:

- The bundled description **does** contain `/logs/spark-client/lab3/`.
- Alert0014496 (legacy Dynatrace child) created **INC0013902** on **lab3** host before or in parallel with SGO processing.
- **No incident** was created on Spark Client Application Service (`cmdb_ci_service_discovered` for Spark Client).

This matches the [known bundling limitation](Problem_to_Incident.adoc#known-limitation-davis-bundling): concurrent client + service validation in one Davis window produces **misleading alert and incident CI**.

## Comparison: before vs after local logs

| Aspect | Pre-fix (NFS-shared logs) | Post-fix (local logs + OneAgent restart) |
|--------|---------------------------|------------------------------------------|
| Client `dt.source_entity` | Lab1, Lab2, **and** Lab3 | **Lab3 only** |
| Client `event.name` | `… on spark-client-lab3-par-a-*` | `… on spark-client-lab3` |
| Master alerts | Triplicated across all hosts | **Lab3 only** in same problem |
| Alert `cmdb_ci` | Often spark-master-0 (pod bind) | Still spark-master-0 when bundled with master path |

Local logs fixed **Dynatrace host attribution**; bundling and **`K8sLogPodCiBind`** behavior remain.

## Mitigations for future validation

1. **Split test windows** — run client-only chapter load separately from cluster-heavy chapters; wait **≥15m** (`dt.davis.event_timeout`) between pattern tests.
2. **Do not expect Spark Client AS incidents** when Davis bundles client + master in one problem until remediation is implemented.
3. **Verify client path in isolation** — search ServiceNow for `spark-client-lab3` and `HOST-D8207A117616460E` without Lab1/Lab2 entity IDs on the same alert.
4. **OneAgent** — restart host OneAgent (and/or rollout `dynakube-oneagent`) after NFS/log-path changes; confirm `FILE_STATUS_OK` on Lab3 before chapter runs.

## Open remediation (not implemented)

- Prefer **client path** over pod path in `K8sLogPodCiBind` when **both** `/logs/spark-client/` and a pod log path appear in the same alert.
- Split bundled problems into separate alerts per `event.name` before incident correlation.
- Ensure `em-alert-create-k8s-log-incident` runs and corrects incident CI even when a legacy Dynatrace child pre-links an incident on the host.

## References

| Artifact | Location |
|----------|----------|
| `K8sLogPodCiBind` | `servicenow/integrations/incident/K8sLogPodCiBind.si.js` |
| Pod bind business rules | `em-event-bind-k8s-log-pod-ci`, `em-alert-bind-k8s-log-pod-ci` |
| Incident creation BR | `em-alert-create-k8s-log-incident.br.js` |
| OpenPipeline client event name | `observability/dynatrace/tenants/pdt20158/integrations/spark-openpipeline-log-alerts-pipeline.json.j2` |
| NFS / local logs contract | `spark/docs/nfs-mounts.md` |
