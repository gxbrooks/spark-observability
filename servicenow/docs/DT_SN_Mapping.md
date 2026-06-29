---
title: ServiceNow and Dynatrace object mapping (SGC integration)
---

# ServiceNow and Dynatrace object mapping

This document describes how **ServiceNow CMDB/CSDM** objects relate to **Dynatrace entities** in the brooks-lab integration (Service Graph Connector for Observability – Dynatrace, `sn_dynatrace_integ`, discovery source **`SGO-Dynatrace`**).

The integration is **asymmetric**: Dynatrace topology and problems flow into ServiceNow via SGC scheduled imports and the problem webhook. **CMDB objects are not injected into Dynatrace.**

Related documents: [DT_SN_Specification_Guide.md](DT_SN_Specification_Guide.md), [DT_SN_Comparison_Process.md](DT_SN_Comparison_Process.md), [install.md](install.md) §7.

---

## What should be in both CMDB and Dynatrace (correlation anchors)

These are the same real-world objects represented in two systems. They should align at defined join keys so IRE merge, SGC import, event CI binding, and compare reports stay consistent.

| Entity | ServiceNow (brooks-lab) | Dynatrace | Correlation key |
|--------|---------------------------|-----------|-----------------|
| **Physical / VM hosts** | `cmdb_ci_linux_server` from Discovery, filtered by location | `HOST` in scoped management zone | Normalized hostname / FQDN; IRE merges SGC import into Discovery CI |
| **Kubernetes cluster** | KVA cluster CI | `KUBERNETES_CLUSTER` | Documented name map in `dynatrace-correlation.yaml` (e.g. `brooks-lab` ↔ `spark-observability-k8s`) |
| **K8s nodes** | KVA node CIs | K8s node entities | Cluster + node name |
| **Scoped workloads** | Pod/deployment CIs with `servicenow.io/*` labels | Matching K8s entities in management zone | Labels / identifiers ↔ `csdm.yaml` application services |
| **Docker containers** (when in scope) | `cmdb_ci_docker_container` from Docker Pattern | Process groups / containers on host | Host + container name / Compose labels |

**Not 1:1 correlated by SGC:**

- **CSDM Business Applications, Business Services, Application Services** — authored in ServiceNow (`*.csdm.yaml` deploy). Dynatrace has its own application and service entities; binding is via **tags**, **process groups**, and **vertical service mapping**, not a direct SGC entity import of the CSDM tree.
- **Business metadata** (`owned_by`, `business_criticality`, BA/BS hierarchy) — ServiceNow-owned; Dynatrace does not mirror these.

---

## Indirect / tag-based (both sides should “cover” the same workload, not the same record)

Tag-based Service Mapping uses runtime labels as the join key between discovered workload CIs and CSDM Application Services.

| Concept | ServiceNow | Dynatrace |
|---------|------------|-----------|
| Application service identity | `cmdb_key_value`: `servicenow.io/application-service-identifier` | Optional mirrored tags on host/process; primarily aligned via same labels on K8s/Docker workloads |
| Environment / location | `servicenow.io/environment`, `servicenow.io/location` on workload CIs | Management zone membership + auto-tags (`Environment`, `Project`, …) from Ansible deploy |
| Workload scope | Tag-based SM binds pod/container CI → Application Service | Process groups and K8s entities in management zone covering the same hosts |

Both platforms should **observe the same workloads**; they do not share a single shared record. Compare checks that canonical tag bindings exist in CMDB and that hosts/clusters sit in the expected management zone.

---

## CMDB-only (ServiceNow authoritative; not imported from Dynatrace)

| Object | Table / class | Role |
|--------|---------------|------|
| Business Application | `cmdb_ci_business_app` | Portfolio / ownership hierarchy |
| Business Service | `cmdb_ci_service` | Capability grouping under BA |
| Application Service (CSDM) | `cmdb_ci_service_discovered` | Service Mapping target; declared in `*.csdm.yaml` |
| CSDM relationships | `cmdb_rel_ci` (Contains, Depends on::Used by) | Hierarchy and declared dependencies |
| Discovery-authoritative host attributes | `cmdb_ci_linux_server` (location, operational status from Discovery) | Authoritative when IRE merges SGC overlay |
| Tag bindings (authoritative for SM) | `cmdb_key_value` on workload CIs | Join key for tag-based mapping |

SGC does not create or update these CSDM business objects. It may add **child** topology CIs and relationships beneath hosts.

---

## Dynatrace-only (not mirrored as CMDB CIs until SGC import)

| Entity | Dynatrace type | Notes |
|--------|----------------|-------|
| Smartscape service | `SERVICE` | DT monitoring unit; may map to `cmdb_ci_service_auto` **after** SGC import |
| Process group | `PROCESS_GROUP` | Often correlates to containers/workloads, not 1:1 with Application Service |
| Dynatrace “application” | `APPLICATION` / custom application | Smartscape app entity; **not** the same as CSDM Business Application |
| Metric / log event definitions | Settings 2.0 objects | Detection rules (CPU threshold, Spark log DQL); not CMDB CIs |
| Problem | Davis problem object | Forwarded to ServiceNow as `em_event`, not stored as a CI |

After SGC scheduled import, many of these become CMDB CIs with `discovery_source` containing **`SGO-Dynatrace`**, optionally merged with Discovery/KVA CIs via IRE.

---

## SGC-injected topology (Dynatrace → CMDB)

SGC scheduled imports (Hosts job triggers a cascade) create or update CMDB rows and relationships:

| Import feed | Typical CMDB class |
|-------------|-------------------|
| Hosts | `cmdb_ci_linux_server` / computer |
| Processes | Process CIs |
| Process groups | Process group CIs |
| Services | Service CIs (e.g. `cmdb_ci_service_auto`) |
| Applications | Application CIs |
| Application relationships | `cmdb_rel_ci` (Depends on, Calls, Runs on, …) |
| K8s cluster / node / pod / namespace | `cmdb_ci_kubernetes_*` |
| Custom applications | Custom app CIs |

**Event binding sidecar:** `sys_object_source` rows with `name = SGO-Dynatrace`, `id` = Dynatrace `entityId`, pointing at the merged CI — used when problems arrive via the SGO-Dynatrace webhook.

---

## Extra attributes Dynatrace adds (on correlated CMDB objects)

### Written to CMDB by SGC import / IRE merge

| Attribute / artifact | Where | Source |
|---------------------|-------|--------|
| `discovery_source` | Merged CI | Includes `SGO-Dynatrace` alongside Discovery/KVA |
| `sys_object_source` | Separate table | Dynatrace `entityId` → `target_sys_id` / `target_table` for event CI binding |
| `host` reference | Child CIs (process, process group, …) | DT topology “runs on” mapping |
| `location` | Infra CIs that were empty | Inherited from host via `sgc_inherit_location_from_host` business rule |
| New child CIs + `cmdb_rel_ci` | Topology | Services, process groups, DT apps, K8s entities not created by Discovery/CSDM |

SGC generally **does not overwrite** CSDM-owned fields (`owned_by`, `business_criticality`, BA/BS parents) on merged hosts.

### Compare report overlay (informational; not CMDB writes)

On matched host rows, compare adds:

- `dynatrace_entity_id`
- `dynatrace_display_name`
- `dynatrace_management_zones`
- `dynatrace_url`

These come from the Dynatrace Entities API at compare time.

### Event path (`em_event`)

When a problem fires, SGC mapping resolves `entityId` through `sys_object_source` and sets **`cmdb_ci`** and **`cmdb_ci_type`** on the event row.

---

## CMDB → Dynatrace

**None.** CMDB CIs are not pushed into Dynatrace. Alignment uses shared specification (`*.csdm.yaml`, `region.yaml`), runtime workload labels, and parallel Ansible configuration of management zones and auto-tags.
