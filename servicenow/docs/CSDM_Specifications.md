---
title: CSDM Specification Format
---

# CSDM Specification Format

This document defines the YAML specification format for **Common Service Data Model (CSDM)** objects, Service Mapping population methods, runtime tags, and dependency relationships. It applies to any deployment that registers Business Applications, Business Services, and Service Instances in a CMDB.

Specifications are written primarily for the **CSDM Modeler** — the person who understands the application architecture and enterprise role of each service. Automation (**deploy processor**) materializes those declarations into the CMDB.

## Purpose

Operations and platform teams need a **data-driven, version-controlled** way to declare CSDM hierarchy, choose how Service Mapping populates application service maps, declare dependency relationships, and apply consistent runtime labels on Kubernetes and Docker workloads.

Authors maintain human-readable **`csdm.yaml`** files per application stack. The **deploy processor** creates or updates CMDB records, links relationships, registers vertical entry points when required, and triggers vertical discovery only where the specification explicitly requests it.

Audiences: **CSDM Modelers**, deploy processor maintainers, discovery operators, platform engineers applying runtime labels, and Service Mapping operators configuring tag-based rules on the instance.

## Definitions

### Document and processing terms

- **CSDM specification** (**`csdm.yaml`**): YAML declaring `business_applications`, `business_services`, and `service_instances`, optional `tag_defaults`, and related attributes for one application or stack.
- **Deploy processor**: Generic automation (Ansible tasks under `csdm/tasks/`) that reads registered specification files and updates the CMDB. The deploy processor **must not** embed names, hosts, or topology from any particular solution.
- **Deploy registry**: In-memory map of object names to CMDB `sys_id` values built during a deploy run, used to resolve cross-file `depends_on` targets.
- **Deferred dependency**: A `depends_on` link whose target CI is not yet in the CMDB; the deploy processor skips the link without failing and reports it for a later run.
- **Runtime tag manifest**: Optional processor output listing merged labels per service instance for orchestration playbooks.

### CSDM object terms

- **Business Application (BA)**: Top-level CSDM object (`cmdb_ci_business_app`).
- **Business Service (BS)**: Logical service under a BA (`cmdb_ci_service`).
- **Service Instance**: Deployable or mappable software unit (CSDM 5.0 term for Application Service). Class `cmdb_ci_service_discovered`; the deploy processor reclasses tag-based service instances to `cmdb_ci_service_by_tags`.
- **Identifier**: Stable machine-readable key (`[a-z0-9-]+`, max 63 characters). Same concept as a web **slug**. Internal logical key only — used for cross-references within specifications, `{host}`/`{host_lower}` expansion, and log labels; **not** sent to ServiceNow and **not** used in any tag.
- **Service instance tag**: The single workload label key **`servicenow.com/service-instance`**. Its value is the service instance display **`name`** (Kubernetes-sanitized for `platform: kubernetes`).
- **Kubernetes label sanitization**: Mapping a display name to the Kubernetes label value charset (max 63 characters; must be empty or begin and end alphanumeric; only alphanumerics, `-`, `_`, `.` in between): characters outside `A-Za-z0-9._-` collapse to `-`, and leading/trailing `-`, `.`, `_` are stripped (for example `Spark Worker` → `Spark-Worker`).
- **Platform**: Runtime environment — `kubernetes`, `docker`, `host`, or `saas`.

### Service Mapping terms

- **Service Mapping (SM)**: ServiceNow capability that builds application service maps from CMDB CIs and relationships.
- **Tag-based Service Mapping**: SM population that groups CMDB CIs by label/tag rules (KVA labels, Docker Compose labels, `cmdb_key_value`). Membership is stored as service → CI associations in **`svc_ci_assoc`**; tag-based services use class `cmdb_ci_service_by_tags`. Does **not** use vertical discovery or `sa_m2m` entry-point registration for map construction.
- **Vertical discovery** (top-down): Classic Service Mapping starting from a registered **entry point**, walking host TCP/process/container relationships via MID Server. In specifications, **`discover: true`** triggers vertical discovery **only** when **`service_mapping: vertical`**.
- **Horizontal Discovery**: Infrastructure discovery (Linux servers, TCP, processes, Docker Pattern, K8s resources) that enriches the CMDB. CSDM deploy **does not** replace horizontal Discovery.
- **Entry point**: A `cmdb_ci_endpoint` CI linked **Depends on::Used by** from an application service and registered in **`sa_m2m_service_entry_point`** for **vertical** Service Mapping only.
- **Docker Pattern**: ServiceNow horizontal discovery probe that discovers Docker containers and creates the process/container relationship graph vertical Service Mapping expects. Distinct from custom container inventory sync that only upserts `cmdb_ci_docker_container` rows.

### Relationship terms

- **`depends_on`**: Consumer → provider **Depends on::Used by** relationships declared on a service instance.
- **Contains::Contained by**: BA → BS → service instance hierarchy.
- **`svc_ci_assoc`**: ServiceNow table holding service → CI membership associations maintained by tag-based Service Mapping. Playbooks do **not** create workload-membership **Contains::Contained by** rows in `cmdb_rel_ci`.
- **Runs on::Runs**: Endpoint CI → Linux server host linkage (vertical entry points).

### Dependency tiers

Authors **should** document `depends_on` entries using tier comments (not stored as CMDB fields).

<table style="margin-left: 1.5em; width: 95%; border-collapse: collapse;">
<colgroup>
<col style="width: 20%">
<col style="width: 25%">
<col style="width: 55%">
</colgroup>
<thead>
<tr><th>Tier</th><th>Name</th><th>Typical targets</th></tr>
</thead>
<tbody>
<tr><td>1</td><td>Data path</td><td>Other application services</td></tr>
<tr><td>2</td><td>Host / runtime</td><td>Not declared on the application service; reached via discovered workload CIs (for example pod or container <strong>Runs on</strong> host)</td></tr>
<tr><td>3</td><td>Cross–business application</td><td>Application services in another BA</td></tr>
<tr><td>4</td><td>Infrastructure enrichment</td><td><code>nfs_server</code>, storage, integrations</td></tr>
</tbody>
</table>

### Identifier and naming

- CSDM **`name`** values **must not** embed **location** or **cluster** tokens (`brooks-lab`, `(Lab3)` as site).
- **Location** **must** use the top-level **`location`** attribute (CMDB `cmn_location`); workloads carry no location label.
- Authors **must not** use **`expand`** to create one Service Instance per node for a horizontally scaled Kubernetes fleet (for example Spark Workers). Use **one** Service Instance and the same `servicenow.com/service-instance` label on every pod; tag-based Service Mapping adds all matching pods as members in `svc_ci_assoc` as they scale.
- Authors **may** use **`expand`** for **host-scoped** agents where each host is a distinct operational Service Instance (for example Elastic Agent or Dynatrace OneAgent per node). With **`expand`**, display **`name`** **may** include a host instance suffix (`Elastic Agent (Lab1)`); **`identifier`** **must** include the host token (`elastic-agent-lab1`).

### Location: CMDB column only

The optional top-level **`location`** attribute sets the CMDB reference (`cmn_location`) on BA/BS/service instance CIs for authoritative CSDM/APM placement, reporting, and filters. Workloads carry **no** location label: the single `servicenow.com/service-instance` tag identifies membership, and host placement of discovered CIs comes from **Runs on** relationships created by discovery.

## Roles and Responsibilities

### CSDM Modeler

The **CSDM Modeler** understands CSDM, the application architecture, and each component's role in the enterprise. The CSDM Modeler **must** author and maintain **`csdm.yaml`** files: business hierarchy, application services, platform classification, Service Mapping method (`tags` vs `vertical` vs `manual`), `depends_on` tiers, identifiers, ownership, and runtime tag intent. The CSDM Modeler **must** register new specification file paths with the deploy processor maintainer. The CSDM Modeler **should** coordinate with platform engineers so Compose/manifest labels match the specification before expecting populated Service Maps.

### Deploy processor

The **deploy processor** is the generic automation (`csdm/tasks/`, invoked by `csdm/deploy.yml`) that materializes CSDM specifications into the CMDB. It **must** validate each service instance, resolve users and locations, upsert CIs, create hierarchy and `depends_on` relationships, set tag population rules for tag-based services via the `/populate_tags` Scripted REST API, register vertical entry points when specified, trigger vertical discovery asynchronously, and emit runtime tag manifests when configured. It **must not** embed application-specific topology.

### Deploy processor maintainer

The **deploy processor maintainer** owns and extends that automation. The maintainer **must** keep the processor solution-independent and maintain the specification file registry in `csdm/common/vars.yml`.

### Discovery operator

The **discovery operator** runs horizontal Discovery (SSH Linux, Docker Pattern, KVA) so infrastructure and workload CIs exist in the CMDB **before** Service Mapping is expected to succeed. The discovery operator **must not** rely on CSDM deploy alone for TCP/process/container enrichment required by vertical discovery.

### Service Mapping operator

The **Service Mapping operator** maintains the tag-based Service Mapping configuration on the ServiceNow instance. The operator **must** ensure the single **Service Instance** tag category (tag key **`servicenow.com/service-instance`**) exists — `service-mapping/common/ensure_tag_categories.yml` configures it; per-service tag population rules are set by the deploy processor, not by hand. The operator **should** monitor vertical discovery jobs triggered by the deploy processor and investigate services stuck in **Requirements**.

## Statements

### 1. Service Mapping

#### 1.1 Service Mapping method by platform

1.1.1 For **Kubernetes** workloads, authors **must** set `platform: kubernetes`, `service_mapping: tags`, and `discover: false`. Kubernetes application services **must not** declare `entry_points` or use vertical Service Mapping.

1.1.2 For **Docker Compose** workloads, authors **should** set `platform: docker`, `service_mapping: tags`, and `discover: false`. Tag-based mapping is the ServiceNow-recommended path when Compose services change frequently or when only container inventory sync is available without Docker Pattern enrichment.

1.1.3 An author **may** set `service_mapping: vertical` and `discover: true` for a Docker Compose application service only when every prerequisite in Statement 1.6 is satisfied, **Docker Pattern** horizontal discovery has run on the host (`discovery_docker_pattern: true` in the deploy registry), and published entry ports are stable across redeploys.

1.1.4 For **host-based** (on-premise) processes running on Linux servers, authors **should** use `service_mapping: tags` when the process can be identified through runtime labels or agent-attributed tags on the host or process CI.

1.1.5 An author **may** use `service_mapping: vertical` and `discover: true` for a host-based process only when the application service declares an `entry_points` entry on a stable host:port, horizontal SSH discovery has created a `cmdb_tcp` row for that port on the target Linux server CI, and that TCP row is linked to the listening process discovered from the same host.

1.1.6 For **SaaS** application services, authors **must** set `platform: saas`, `service_mapping: manual`, and `discover: false`.

1.1.7 Authors **must** choose `service_mapping` per application service using Statements 1.1.1–1.1.6 as normative guidance; the deploy processor enforces the corresponding validation rules in Statement 3.4.

#### 1.2 Rich CSDM without vertical discovery

1.2.1 When using **tag-based** or **manual** mapping, authors **must** still declare a full BA → BS → application service hierarchy with mandatory ownership attributes.

1.2.2 Authors **must** declare **`depends_on`** tiers for failure propagation and Service Map context even when vertical discovery is disabled.

1.2.3 Authors **must** set **`identifier`** on every service instance as an internal logical key. Authors **may** set **`environment`** and **`location`** as CI fields on the service record; these attributes are **not** emitted as workload tags.

1.2.4 Authors **must** apply the runtime **`servicenow.com/service-instance`** label on workloads (and platform-specific keys in Statements 1.3–1.5) when `service_mapping: tags`.

1.2.5 Authors **must** ensure horizontal discovery, KVA, and/or Docker inventory sync run so backing workload CIs exist in the CMDB before expecting tag-based maps to populate.

1.2.6 Tag-based Service Mapping adds discovered workload CIs as service members in **`svc_ci_assoc`** when the service's tag population rule matches labels. **`depends_on`** supplies cross-service and non-host infrastructure edges (for example `nfs_server`) the map does not infer automatically.

1.2.7 Authors **must not** declare Application Service → `cmdb_ci_linux_server` relationships via `depends_on` with `type: linux_server` (or equivalent). When workloads are discovered, the Linux host **must** be reached through the workload CI (for example `cmdb_ci_kubernetes_pod` or `cmdb_ci_docker_container` **Runs on** the host). Hard-coded AS → host edges do not scale with rescheduling and multi-node placement and **must not** be used as a membership or placement model.

1.2.8 Authors **must not** use `expand` to create one Service Instance per Kubernetes node for a horizontally scaled fleet. Authors **must** declare a single Service Instance and apply the same `servicenow.com/service-instance` label on every pod in the fleet so tag-based Service Mapping keeps all pods as members (`svc_ci_assoc`) as replica count changes. Authors **may** use `expand` only for host-scoped agents where each host is itself a distinct Service Instance (for example Elastic Agent or Dynatrace OneAgent).

#### 1.3 Runtime tags — all platforms

When `service_mapping: tags`, authors **must** apply the single **`servicenow.com/service-instance`** key on every workload (Kubernetes pod labels or Docker Compose service labels). Tag-based Service Mapping reads it from **`cmdb_key_value`**. KVA writes Kubernetes labels as **`system`**. Docker Compose labels reach **`cmdb_key_value`** through **`discovery/docker/discover.yml`** (REST upsert) when the integration user has write ACLs, or through an instance-specific label-import path — **Docker Pattern** horizontal discovery enriches container/process relationships but **does not** by itself populate custom **`servicenow.com/*`** rows in this lab.

> **All platforms — servicenow.com key**

<table style="margin-left: 1.5em; width: 95%; border-collapse: collapse;">
<colgroup>
<col style="width: 25%">
<col style="width: 75%">
</colgroup>
<thead>
<tr><th>Label key</th><th>Statement</th></tr>
</thead>
<tbody>
<tr>
<td><code>servicenow.com/service-instance</code></td>
<td>Authors <strong>must</strong> set this label to the service instance display <code>name</code>. For <code>platform: kubernetes</code>, the value <strong>must</strong> be the Kubernetes-sanitized name (for example <code>Spark Worker</code> → <code>Spark-Worker</code>); for Docker Compose and host platforms, the value <strong>must</strong> be the exact display name (spaces allowed). The deploy processor generates the ServiceNow-side tag population rule from the same <code>name</code> with the same sanitization, so workload label and rule always match.</td>
</tr>
</tbody>
</table>

1.3.1 Authors **must** apply the same **`servicenow.com/service-instance`** key on Docker containers as on Kubernetes pods when using tag-based Service Mapping.

1.3.2 Authors **should** declare this key in Docker Compose `labels:` blocks (see `observability/docker-compose.yml`) and in Kubernetes manifest labels; the deploy processor **may** emit a runtime tag manifest under `vars/contexts/csdm_runtime_tags/` for downstream automation.

1.3.3 Authors **must not** apply environment, location, business-application, or business-service label keys on workloads; BA and BS context comes from the CSDM hierarchy, and `environment`/`location` are CI fields on the service record only.

#### 1.4 Runtime tags — Kubernetes

> **Kubernetes — additional keys (<code>tags.kubernetes</code> in csdm.yaml)**

<table style="margin-left: 1.5em; width: 95%; border-collapse: collapse;">
<colgroup>
<col style="width: 25%">
<col style="width: 75%">
</colgroup>
<thead>
<tr><th>Label key</th><th>Statement</th></tr>
</thead>
<tbody>
<tr>
<td><code>app.kubernetes.io/name</code></td>
<td>Authors <strong>must</strong> set this label to the canonical application name for the workload (typically the application service slug or chart name).</td>
</tr>
<tr>
<td><code>app.kubernetes.io/instance</code></td>
<td>Authors <strong>must</strong> set this label to a unique instance name within the cluster (for example, Helm release name).</td>
</tr>
<tr>
<td><code>app.kubernetes.io/component</code></td>
<td>Authors <strong>must</strong> set this label to the component role within the application (for example, <code>master</code>, <code>worker</code>, <code>frontend</code>).</td>
</tr>
<tr>
<td><code>app.kubernetes.io/part-of</code></td>
<td>Authors <strong>must</strong> set this label to the top-level application name (typically the Business Application identifier or product name).</td>
</tr>
<tr>
<td><code>app.kubernetes.io/managed-by</code></td>
<td>Authors <strong>should</strong> set this label to the tool managing the workload (for example, <code>Helm</code>, <code>ansible</code>).</td>
</tr>
<tr>
<td><code>app.kubernetes.io/version</code></td>
<td>Authors <strong>may</strong> set this label to the deployed software version string.</td>
</tr>
</tbody>
</table>

#### 1.5 Runtime tags — Docker Compose

> **Docker Compose — additional keys (<code>tags.docker</code> in csdm.yaml)**

<table style="margin-left: 1.5em; width: 95%; border-collapse: collapse;">
<colgroup>
<col style="width: 25%">
<col style="width: 75%">
</colgroup>
<thead>
<tr><th>Label key</th><th>Statement</th></tr>
</thead>
<tbody>
<tr>
<td><code>com.docker.compose.project</code></td>
<td>Authors <strong>must</strong> set this label to the Compose project name (for example, <code>observability</code>).</td>
</tr>
<tr>
<td><code>com.docker.compose.service</code></td>
<td>Authors <strong>must</strong> set this label to the Compose <strong>service</strong> name from <code>docker-compose.yml</code> (for example, <code>es01</code>), not necessarily the container name or CMDB CI short name.</td>
</tr>
</tbody>
</table>

1.5.1 The CSDM Modeler **must** declare matching values under `tags.docker` in `csdm.yaml` so deploy validation and Service Mapping rules align with Compose labels.

#### 1.6 Vertical discovery prerequisites

Authors **must not** set `discover: true` until all of the following are true for the target application service:

1.6.1 The deploy processor **must** have created a **`cmdb_ci_endpoint`** entry point CI with **Runs on::Runs** to the target Linux server when `service_mapping: vertical`.

1.6.2 The deploy processor **must** have registered that entry point in **`sa_m2m_service_entry_point`** via `SNC.BusinessServiceManager.addEntryPoint`.

1.6.3 The assigned **MID Server** **must** be **Up** and validated on the instance (`ecc_agent.status = Up`).

1.6.4 **Discovery credentials** **must** be valid for SSH (or the relevant probe) on the target host.

1.6.5 **TCP enrichment** **must** exist: a **`cmdb_tcp`** row on the entry **port** on the target Linux server CI, created by horizontal SSH discovery.

1.6.6 **Process linkage** **must** exist: the listener process associated with that TCP row, also from horizontal SSH discovery.

1.6.7 For **Docker vertical** only, **Docker Pattern** horizontal discovery **must** have linked containers to the host/process graph. Custom container inventory sync that only upserts `cmdb_ci_docker_container` rows **must not** be treated as sufficient.

1.6.8 The discovery operator **should** complete horizontal discovery on the target host **before** the deploy processor triggers vertical discovery; if horizontal discovery runs later, operators **should** re-trigger vertical discovery.

1.6.9 When `service_status=requirements` persists after meeting Statements 1.6.1–1.6.8, operators **should** configure **tag-based** mapping per [Tag_Based_Service_Mapping.md](Tag_Based_Service_Mapping.md) (remove stale vertical entry points in the Service Mapping UI when converting) or investigate shared-tenant Service Mapping backlog.

### 2. CSDM Modeler

#### 2.1 Specification files

2.1.1 The CSDM Modeler **must** use YAML lists for `business_applications`, `business_services`, and `service_instances`.

2.1.2 Specifications **may** use Jinja for values resolved from context variable files at deploy time.

2.1.3 Application-specific CSDM names, identifiers, and descriptions **must** live in **`csdm.yaml`**, not in shared context registries.

2.1.4 Each file **should** live at `<application-playbook-dir>/servicenow/csdm.yaml` and **must** be registered in `csdm/common/vars.yml`.

2.1.5 Every BA, BS, and service instance **must** declare an **`identifier`** obeying identifier rules in Definitions; the identifier is an internal logical key and is **not** sent to ServiceNow.

#### 2.2 Business Application attributes

> **Business Application (<code>cmdb_ci_business_app</code>) attributes**

<table style="margin-left: 1.5em; width: 95%; border-collapse: collapse;">
<colgroup>
<col style="width: 25%">
<col style="width: 75%">
</colgroup>
<thead>
<tr><th>Field</th><th>Statement</th></tr>
</thead>
<tbody>
<tr><td><code>name</code></td><td>Authors <strong>must</strong> set the CMDB display name.</td></tr>
<tr><td><code>identifier</code></td><td>Authors <strong>must</strong> set a stable machine key used for cross-references within specifications.</td></tr>
<tr><td><code>business_owner</code></td><td>Authors <strong>must</strong> set a ServiceNow <code>user_name</code>; maps to CMDB <code>owned_by</code> when no <code>business_owner</code> column exists.</td></tr>
<tr><td><code>it_application_owner</code></td><td>Authors <strong>must</strong> set a ServiceNow <code>user_name</code>.</td></tr>
<tr><td><code>operational_status</code></td><td>Authors <strong>must</strong> set <code>"1"</code> for Operational.</td></tr>
<tr><td><code>active</code></td><td>Authors <strong>must</strong> set <code>"true"</code> or <code>"false"</code>.</td></tr>
<tr><td><code>short_description</code></td><td>Authors <strong>should</strong> set a human-readable summary.</td></tr>
</tbody>
</table>

#### 2.3 Business Service attributes

> **Business Service (<code>cmdb_ci_service</code>) attributes**

<table style="margin-left: 1.5em; width: 95%; border-collapse: collapse;">
<colgroup>
<col style="width: 25%">
<col style="width: 75%">
</colgroup>
<thead>
<tr><th>Field</th><th>Statement</th></tr>
</thead>
<tbody>
<tr><td><code>name</code></td><td>Authors <strong>must</strong> set the CMDB display name.</td></tr>
<tr><td><code>identifier</code></td><td>Authors <strong>must</strong> set a stable machine key used for cross-references within specifications.</td></tr>
<tr><td><code>parent_business_application</code></td><td>Authors <strong>must</strong> set the parent BA <code>name</code>.</td></tr>
<tr><td><code>owned_by</code></td><td>Authors <strong>must</strong> set a ServiceNow <code>user_name</code>.</td></tr>
<tr><td><code>business_criticality</code></td><td>Authors <strong>must</strong> set a choice value from Statement 2.7.</td></tr>
<tr><td><code>operational_status</code></td><td>Authors <strong>must</strong> set <code>"1"</code> for Operational.</td></tr>
<tr><td><code>short_description</code></td><td>Authors <strong>should</strong> set a human-readable summary.</td></tr>
</tbody>
</table>

#### 2.4 Service Instance attributes

> **Service Instance (<code>cmdb_ci_service_discovered</code>; reclassed to <code>cmdb_ci_service_by_tags</code> when <code>service_mapping: tags</code>) attributes**

<table style="margin-left: 1.5em; width: 95%; border-collapse: collapse;">
<colgroup>
<col style="width: 25%">
<col style="width: 75%">
</colgroup>
<thead>
<tr><th>Field</th><th>Statement</th></tr>
</thead>
<tbody>
<tr><td><code>name</code></td><td>Authors <strong>must</strong> set the display name; when <code>service_mapping: tags</code> this name (Kubernetes-sanitized for <code>platform: kubernetes</code>) is the <code>servicenow.com/service-instance</code> label value on workloads. Authors <strong>may</strong> use <code>{host}</code> / <code>{host_lower}</code> with <code>expand</code>.</td></tr>
<tr><td><code>identifier</code></td><td>Authors <strong>must</strong> set a stable machine key as an internal logical key (cross-references, <code>{host}</code>/<code>{host_lower}</code> expansion, log labels); it is <strong>not</strong> sent to ServiceNow and <strong>not</strong> used in any tag.</td></tr>
<tr><td><code>parent_business_service</code></td><td>Authors <strong>must</strong> set the parent BS <code>name</code>.</td></tr>
<tr><td><code>owned_by</code></td><td>Authors <strong>must</strong> set a ServiceNow <code>user_name</code>.</td></tr>
<tr><td><code>business_criticality</code></td><td>Authors <strong>must</strong> set a choice value from Statement 2.7.</td></tr>
<tr><td><code>operational_status</code></td><td>Authors <strong>must</strong> set <code>"1"</code> for Operational.</td></tr>
<tr><td><code>platform</code></td><td>Authors <strong>must</strong> set <code>kubernetes</code>, <code>docker</code>, <code>host</code>, or <code>saas</code>.</td></tr>
<tr><td><code>environment</code></td><td>Authors <strong>may</strong> set a value (or inherit from <code>tag_defaults</code>); stored as a CI field on the service record and <strong>not</strong> emitted as a workload tag.</td></tr>
<tr><td><code>location</code></td><td>Authors <strong>may</strong> set the CMDB location name; stored as a CI field on the service record and <strong>not</strong> emitted as a workload tag.</td></tr>
<tr><td><code>service_mapping</code></td><td>Authors <strong>must</strong> set <code>tags</code>, <code>vertical</code>, or <code>manual</code> per Statements 1.1.1–1.1.6.</td></tr>
<tr><td><code>discover</code></td><td>Authors <strong>must</strong> set <code>false</code> for Kubernetes, SaaS, and tag-based Docker/host; authors <strong>may</strong> set <code>true</code> only with <code>service_mapping: vertical</code> and Statement 1.6 satisfied.</td></tr>
<tr><td><code>depends_on</code></td><td>Authors <strong>should</strong> declare tiered consumer → provider lists.</td></tr>
<tr><td><code>tags</code></td><td>Authors <strong>must</strong> declare nested <code>kubernetes</code> and/or <code>docker</code> maps when <code>service_mapping: tags</code>.</td></tr>
<tr><td><code>entry_points</code></td><td>Authors <strong>must</strong> declare when <code>service_mapping: vertical</code> and <code>discover: true</code> on Docker/host.</td></tr>
<tr><td><code>expand</code></td><td>Authors <strong>may</strong> set <code>inventory_group</code> for per-host <em>agent</em> Application Services only (see Statement 1.2.8). Authors <strong>must not</strong> expand horizontally scaled Kubernetes fleets.</td></tr>
<tr><td><code>short_description</code></td><td>Authors <strong>should</strong> set a human-readable summary.</td></tr>
</tbody>
</table>

#### 2.5 Platform-specific modeling rules

##### 2.5.1 Kubernetes

2.5.1.1 The CSDM Modeler **must** set `platform: kubernetes`, `service_mapping: tags`, and `discover: false`.

2.5.1.2 The CSDM Modeler **must** supply `tags.kubernetes` per Statement 1.4.

2.5.1.3 The CSDM Modeler **must not** declare `entry_points` for Kubernetes application services.

##### 2.5.2 Docker Compose

2.5.2.1 The CSDM Modeler **must** set `platform: docker`.

2.5.2.2 The CSDM Modeler **should** set `service_mapping: tags` and `discover: false` for Compose stacks (ServiceNow recommended path).

2.5.2.3 The CSDM Modeler **may** set `service_mapping: vertical` and `discover: true` only when every Statement 1.6 prerequisite is met and entry ports are stable.

2.5.2.4 When tag-based, the CSDM Modeler **must** declare `tags.docker` per Statement 1.5 and apply the **`servicenow.com/service-instance`** label on Compose services.

2.5.2.5 When vertical, the CSDM Modeler **must** declare `entry_points` with `host_lookup_name` resolving to a Linux server CI.

##### 2.5.3 Host

2.5.3.1 The CSDM Modeler **must** set `platform: host`.

2.5.3.2 The CSDM Modeler **should** set `service_mapping: tags` when process identification can be expressed through labels.

2.5.3.3 The CSDM Modeler **may** set `service_mapping: vertical` and `discover: true` only when Statement 1.1.5 and Statement 1.6 apply.

2.5.3.4 When vertical with `discover: true`, the CSDM Modeler **must** declare `entry_points`.

##### 2.5.4 SaaS

2.5.4.1 The CSDM Modeler **must** set `platform: saas`, `service_mapping: manual`, and `discover: false`.

#### 2.6 depends_on, csdm_defaults, and csdm_op

2.6.1 The CSDM Modeler **must** use `depends_on` on application services for consumer → provider relationships.

2.6.2 Each item **may** be a string (application service `name`) or a mapping with `name` and optional `type` (`nfs_server`, `business_service`). Authors **must not** use `type: linux_server` (see Statement 1.2.7). The deploy processor **may** still resolve `linux_server` for legacy cleanup, but new specifications **must not** declare it.

2.6.3 The CSDM Modeler **should** set `csdm_defaults` at file scope for shared owners and criticality.

2.6.4 For **`csdm_op`**, authors **may** set `insert` (default, upsert) or `delete`. Delete entries **must** include `name`; the deploy processor removes relationships then the CI.

#### 2.7 Allowed values

2.7.1 **`business_criticality`:** `1 - most critical`, `2 - somewhat critical`, `3 - less critical`, `4 - not critical`. The deploy processor writes this value to the ServiceNow CMDB column **`busines_criticality`** (platform spelling).

2.7.2 **`environment`:** `on-prem`, `dev`, `stage`, `prod`, `lab`

### 3. Deploy processor

#### 3.1 Deploy order

3.1.1 The deploy processor **must** run `csdm_op: delete` in order: application services → business services → business applications (before inserts in the same file).

3.1.2 The deploy processor **must** create inserts in order: business applications → business services → application services → entry points (when applicable).

3.1.3 The deploy processor **must** run a second pass for all `depends_on` after every specification file in the run has been processed.

3.1.4 Deferred targets **must not** fail the play; the deploy processor **must** report them.

#### 3.2 CMDB materialization

3.2.1 The deploy processor **must** resolve `user_name` values to `sys_user.sys_id` before create or patch.

3.2.2 The deploy processor **must** map YAML `business_owner` to CMDB `owned_by` when the instance has no `business_owner` column.

3.2.3 The deploy processor **must** create **Contains::Contained by** for BA → BS → service instance hierarchy.

3.2.4 The deploy processor **must** create **Depends on::Used by** for `depends_on` entries.

#### 3.3 Service Mapping triggers

3.3.1 The deploy processor **must** trigger vertical discovery asynchronously when `service_mapping: vertical` and `discover: true`; it **must not** wait for completion.

3.3.2 The deploy processor **must not** trigger vertical discovery for `platform: kubernetes`, `service_mapping: tags`, or `service_mapping: manual`.

3.3.3 For vertical entry points, the deploy processor **must** create `cmdb_ci_endpoint` with **Runs on::Runs** to host and register via Service Mapping Operations REST API (`addEntryPoint`).

3.3.4 For tag-based services, the deploy processor **must not** create entry points or call `addEntryPoint`.

3.3.5 The deploy processor **may** emit a runtime tag manifest under `vars/contexts/csdm_runtime_tags/` for downstream label application.

3.3.6 For services with `service_mapping: tags`, the deploy processor **must** reclass the service to **`cmdb_ci_service_by_tags`** and call the `/populate_tags` Scripted REST API (backed by `csdm/files/sm_populate_tag_list.js`), which sets the tag population rule via `SMServiceByTagsUtils.updateServiceFromTagsList()`, sets service metadata (populator, checksum, category values), and triggers `SNC.ServicePopulatorRunner('INTERACTIVE')` so membership recalculates immediately.

3.3.7 The deploy processor **must** derive the tag population rule value from the service instance **`name`**, applying Kubernetes sanitization for `platform: kubernetes`, so the rule always matches the workload label.

#### 3.4 Validation

3.4.1 The deploy processor **must** reject Kubernetes application services that declare `service_mapping: vertical` or `discover: true`.

3.4.2 The deploy processor **must** reject SaaS application services unless `service_mapping: manual` and `discover: false`.

3.4.3 The deploy processor **must** reject tag-based application services without a `tags` map.

3.4.4 The deploy processor **must** reject tag-based application services with `discover: true`.

3.4.5 The deploy processor **must** reject vertical application services with `discover: true` and no `entry_points`.

### 4. Discovery operator

4.1 The discovery operator **must** run horizontal Linux Discovery on target hosts before expecting vertical host or Docker entry-point enrichment (Statements 1.6.5–1.6.6).

4.2 The discovery operator **must** run KVA for Kubernetes clusters before expecting tag-based K8s maps to populate.

4.3 The discovery operator **must** run ServiceNow **Docker Pattern** horizontal discovery on Docker hosts where vertical Service Mapping or container/process enrichment is required (for example, Lab3 with `discovery_docker_pattern: true`).

4.4 The discovery operator **must** run **`discovery/docker/discover.yml`** on Docker hosts where tag-based Service Mapping depends on **`cmdb_key_value`** rows from Compose labels; that playbook reads labels from `docker inspect` and upserts **`cmdb_key_value`** (matching only **`servicenow.com/*`** keys) when the integration user has write ACLs.

4.5 When **`cmdb_key_value`** REST insert returns HTTP 403, operators **must** extend table ACLs so **`cmdb_inst_admin`** appears in **Requires role** on the active **create**, **write**, and **delete** ACLs for table **`cmdb_key_value`** — see `docs/install.md` §6.3. Read access is usually satisfied out of the box via **`cmdb_read`**. KVA populates Kubernetes labels as user **`system`**, which is a separate internal path.

4.6 The discovery operator **should** ensure the MID Server is **Up** before triggering horizontal discovery (`discovery/discover.yml` or Discover Now in the UI).

### 5. Service Mapping operator

5.1 The Service Mapping operator **must** ensure the single **Service Instance** tag category (tag key **`servicenow.com/service-instance`**, defined as `sn_csdm_tag_key_service_instance` in `service-mapping/common/vars.yml`) exists on the instance; `service-mapping/common/ensure_tag_categories.yml` configures it. The operator **must not** author per-service tag population rules by hand — the deploy processor sets them (Statements 3.3.6–3.3.7).

5.2 The Service Mapping operator **should** monitor `process_status` and `service_status` on `cmdb_ci_service_discovered` after vertical triggers.

5.3 When migrating Docker services from vertical to tag-based, the operator **should** remove stale entry-point dependencies in the Service Mapping UI and reset `process_status` / `service_status` on affected application services per [Tag_Based_Service_Mapping.md](Tag_Based_Service_Mapping.md).

## Commentary

### Why the workload tag uses the display name

There is a single workload tag: **`servicenow.com/service-instance`**, whose value is the service instance display **`name`**. For `platform: kubernetes` the value is sanitized to the Kubernetes label value charset (max 63 characters, alphanumeric at both ends, only alphanumerics, `-`, `_`, `.` in between); Docker Compose and host platforms use the exact display name, spaces allowed. The deploy processor generates the ServiceNow-side tag population rule from the same `name` with the same sanitization, so the workload label and the rule always match. **`identifier`** stays internal — cross-references within specs, `{host}`/`{host_lower}` expansion, and log labels — and never reaches ServiceNow. Environment and location scoping tags were dropped as unnecessary in this lab; `environment` and `location` remain optional CI fields on the service record.

Matching on display names is deliberate and accepted as brittle: renaming a service instance in the spec requires updating the hardcoded label values in `ansible/roles/spark/templates/spark-*.yaml.j2` and `observability/docker-compose.yml`. Drift is detected — the comparator flags workloads whose tag matches no service, and membership fails closed — but not prevented.

### Why Docker Compose uses tag-based mapping in this lab

ServiceNow **allows** vertical discovery for Docker but **recommends** tags for Compose stacks that change frequently. Vertical discovery requires a traversable graph from entry point → TCP → process → container. Container inventory sync that only upserts `cmdb_ci_docker_container` rows without **cmdb_rel_ci** relationships leaves vertical discovery stuck in **Requirements** — tag-based mapping with Compose labels is the reliable path when the **`servicenow.com/service-instance`** label is on services and label sync has populated **`cmdb_key_value`**.

### Document rendering and tables

The VS Code built-in Markdown preview applies **`markdown.styles`** CSS inconsistently to wrapped `<div>` blocks and markdown pipe tables. For reliable table column widths and indentation:

- **Pandoc** (`pandoc CSDM_Specifications.md -o CSDM_Specifications.pdf --css=csdm-spec.css`) respects inline HTML `<colgroup>` widths used in this document.
- **Quarto** wraps Pandoc and simplifies multi-format publish (HTML/PDF) with shared CSS.
- **Markdown Preview Enhanced** (VS Code extension) applies custom CSS more predictably than the default preview.

Authors **should** prefer inline HTML tables with explicit `<colgroup>` percentages (25% / 75%) for normative attribute tables in this TPG.

### Deferred linking

Infrastructure targets and cross-file application services may not exist on first deploy. The second-pass linker resolves registry → CMDB lookup → defer without duplicate relationships.

### Why Service Instances must not Depends on linux_server

Tag-based maps already place workloads under the Service Instance as members (**`svc_ci_assoc`**). Discovery and SGC already place pods/containers on hosts (**Runs on**). Declaring service → `cmdb_ci_linux_server` in `depends_on` duplicates placement as a static edge that drifts when pods reschedule. Prefer the discovered path: Service Instance → member (`svc_ci_assoc`) → pod → Runs on → host. Keep `depends_on` for cross-service and non-host infrastructure (for example NFS).

### Why horizontally scaled fleets use one Service Instance

Creating one Service Instance per node for Spark Workers (or similar Deployments) couples CSDM cardinality to inventory size and breaks when replica sets move or new nodes join. One Service Instance whose `servicenow.com/service-instance` label is shared across pods lets tag-based Service Mapping keep every matching pod as a member. Reserve `expand` for agents that are intentionally one Service Instance per host.

## References

- ServiceNow CSDM documentation (Business Application, Business Service, Application Service)
- ServiceNow [Quick Start Guide for Service Mapping](https://www.servicenow.com/community/itom-articles/quick-start-guide-for-service-mapping/ta-p/3521583)
- [Tag_Based_Service_Mapping.md](Tag_Based_Service_Mapping.md) — instance UI paths, tag categories, ACL/Docker Pattern notes, and which application services need rules
- Kubernetes [Recommended Labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/)
- Kubernetes [Labels and Selectors — Syntax and character set](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#syntax-and-character-set)
- `meta-standards/tpgs-for-tpgs.md` — TPG structure and numbered Statements subsections
- `meta-standards/keywords-for-standards.md` — must, should, may
