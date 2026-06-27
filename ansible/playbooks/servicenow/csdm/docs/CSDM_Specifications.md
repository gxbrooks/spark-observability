---
title: CSDM Specification Format
---

# CSDM Specification Format

This document defines the YAML specification format for **Common Service Data Model (CSDM)** objects, Service Mapping population methods, runtime tags, and dependency relationships. It applies to any deployment that registers Business Applications, Business Services, and Application Services in a CMDB.

Specifications are written primarily for the **CSDM Modeler** — the person who understands the application architecture and enterprise role of each service. Automation (**deploy processor**) materializes those declarations into the CMDB.

## Purpose

Operations and platform teams need a **data-driven, version-controlled** way to declare CSDM hierarchy, choose how Service Mapping populates application service maps, declare dependency relationships, and apply consistent runtime labels on Kubernetes and Docker workloads.

Authors maintain human-readable **`csdm.yaml`** files per application stack. The **deploy processor** creates or updates CMDB records, links relationships, registers vertical entry points when required, and triggers vertical discovery only where the specification explicitly requests it.

Audiences: **CSDM Modelers**, deploy processor maintainers, discovery operators, platform engineers applying runtime labels, and Service Mapping operators configuring tag-based rules on the instance.

## Definitions

### Document and processing terms

- **CSDM specification** (**`csdm.yaml`**): YAML declaring `business_applications`, `business_services`, and `application_services`, optional `tag_defaults`, and related attributes for one application or stack.
- **Deploy processor**: Generic automation (Ansible tasks under `csdm/tasks/`) that reads registered specification files and updates the CMDB. The deploy processor **must not** embed names, hosts, or topology from any particular solution.
- **Deploy registry**: In-memory map of object names to CMDB `sys_id` values built during a deploy run, used to resolve cross-file `depends_on` targets.
- **Deferred dependency**: A `depends_on` link whose target CI is not yet in the CMDB; the deploy processor skips the link without failing and reports it for a later run.
- **Runtime tag manifest**: Optional processor output listing merged labels per application service instance for orchestration playbooks.

### CSDM object terms

- **Business Application (BA)**: Top-level CSDM object (`cmdb_ci_business_app`).
- **Business Service (BS)**: Logical service under a BA (`cmdb_ci_service`).
- **Application Service**: Deployable or mappable software unit (`cmdb_ci_service_discovered`).
- **Identifier**: Stable machine-readable key (`[a-z0-9-]+`, max 63 characters). Same concept as a web **slug**.
- **Platform**: Runtime environment — `kubernetes`, `docker`, `host`, or `saas`.

### Service Mapping terms

- **Service Mapping (SM)**: ServiceNow capability that builds application service maps from CMDB CIs and relationships.
- **Tag-based Service Mapping**: SM population that groups CMDB CIs by label/tag rules (KVA labels, Docker Compose labels, `cmdb_key_value`). Does **not** use vertical discovery or `sa_m2m` entry-point registration for map construction.
- **Vertical discovery** (top-down): Classic Service Mapping starting from a registered **entry point**, walking host TCP/process/container relationships via MID Server. In specifications, **`discover: true`** triggers vertical discovery **only** when **`service_mapping: vertical`**.
- **Horizontal Discovery**: Infrastructure discovery (Linux servers, TCP, processes, Docker Pattern, K8s resources) that enriches the CMDB. CSDM deploy **does not** replace horizontal Discovery.
- **Entry point**: A `cmdb_ci_endpoint` CI linked **Depends on::Used by** from an application service and registered in **`sa_m2m_service_entry_point`** for **vertical** Service Mapping only.
- **Docker Pattern**: ServiceNow horizontal discovery probe that discovers Docker containers and creates the process/container relationship graph vertical Service Mapping expects. Distinct from custom container inventory sync that only upserts `cmdb_ci_docker_container` rows.

### Relationship terms

- **`depends_on`**: Consumer → provider **Depends on::Used by** relationships declared on an application service.
- **Contains::Contained by**: BA → BS → application service hierarchy.
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
<tr><td>2</td><td>Host / runtime</td><td><code>linux_server</code> CIs</td></tr>
<tr><td>3</td><td>Cross–business application</td><td>Application services in another BA</td></tr>
<tr><td>4</td><td>Infrastructure enrichment</td><td><code>nfs_server</code>, storage, integrations</td></tr>
</tbody>
</table>

### Identifier and naming

- CSDM **`name`** values **must not** embed **location** or **cluster** tokens (`brooks-lab`, `(Lab3)` as site).
- **Location** **must** use the top-level **`location`** attribute (CMDB `cmn_location`) and matching runtime labels.
- With **`expand`**, display **`name`** **may** include host instance suffix (`Spark Worker (Lab1)`); **`identifier`** **must** include the host token (`spark-worker-lab1`).

### Location: CMDB column vs runtime label

<table style="margin-left: 1.5em; width: 95%; border-collapse: collapse;">
<colgroup>
<col style="width: 25%">
<col style="width: 30%">
<col style="width: 45%">
</colgroup>
<thead>
<tr><th>Mechanism</th><th>Where it lives</th><th>Purpose</th></tr>
</thead>
<tbody>
<tr>
<td><code>location</code> (YAML top-level)</td>
<td>CMDB reference on BA/BS/application service CIs</td>
<td>Authoritative CSDM/APM placement; reporting and filters</td>
</tr>
<tr>
<td><code>servicenow.io/location</code> (runtime label)</td>
<td>Kubernetes labels / Docker Compose labels → <code>cmdb_key_value</code> via discovery</td>
<td>Tag-based Service Mapping rules; correlates discovered workload CIs</td>
</tr>
</tbody>
</table>

Authors **must** set both to the same location name (`cmn_location.name`, for example `brooks-lab`). The CMDB column is the system-of-record for CSDM objects the deploy processor creates. Labels propagate placement to dynamically discovered CIs (pods, containers) so Service Mapping can group them without manual CMDB edits.

## Roles and Responsibilities

### CSDM Modeler

The **CSDM Modeler** understands CSDM, the application architecture, and each component's role in the enterprise. The CSDM Modeler **must** author and maintain **`csdm.yaml`** files: business hierarchy, application services, platform classification, Service Mapping method (`tags` vs `vertical` vs `manual`), `depends_on` tiers, identifiers, ownership, and runtime tag intent. The CSDM Modeler **must** register new specification file paths with the deploy processor maintainer. The CSDM Modeler **should** coordinate with platform engineers so Compose/manifest labels match the specification before expecting populated Service Maps.

### Deploy processor

The **deploy processor** is the generic automation (`csdm/tasks/`, invoked by `csdm/deploy.yml`) that materializes CSDM specifications into the CMDB. It **must** validate each application service, resolve users and locations, upsert CIs, create hierarchy and `depends_on` relationships, register vertical entry points when specified, trigger vertical discovery asynchronously, and emit runtime tag manifests when configured. It **must not** embed application-specific topology.

### Deploy processor maintainer

The **deploy processor maintainer** owns and extends that automation. The maintainer **must** keep the processor solution-independent and maintain the specification file registry in `csdm/common/vars.yml`.

### Discovery operator

The **discovery operator** runs horizontal Discovery (SSH Linux, Docker Pattern, KVA) so infrastructure and workload CIs exist in the CMDB **before** Service Mapping is expected to succeed. The discovery operator **must not** rely on CSDM deploy alone for TCP/process/container enrichment required by vertical discovery.

### Service Mapping operator

The **Service Mapping operator** configures tag-based Service Mapping rules on the ServiceNow instance (typically keyed on **servicenow.io/application-service-identifier**). The operator **must** configure rules before tag-based application services can reach **operational** map status. The operator **should** monitor vertical discovery jobs triggered by the deploy processor and investigate services stuck in **Requirements**.

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

1.2.3 Authors **must** set **`identifier`**, **`environment`**, **`location`**, and **`service_tier`** (recommended) on every application service.

1.2.4 Authors **must** apply runtime **servicenow.io/** labels on workloads (and platform-specific keys in Statements 1.3–1.5) when `service_mapping: tags`.

1.2.5 Authors **must** ensure horizontal discovery, KVA, and/or Docker inventory sync run so backing workload CIs exist in the CMDB before expecting tag-based maps to populate.

1.2.6 Tag-based Service Mapping adds **Contains** relationships from application services to discovered workload CIs when instance rules match labels. **`depends_on`** supplies cross-service and infrastructure edges the map does not infer automatically.

#### 1.3 Runtime tags — all platforms

When `service_mapping: tags`, authors **must** apply the following **servicenow.io/** keys on every workload (Kubernetes pod labels or Docker Compose service labels). Tag-based Service Mapping reads these from **`cmdb_key_value`**. KVA writes Kubernetes labels as **`system`**. Docker Compose labels reach **`cmdb_key_value`** through **`discovery/docker/discover.yml`** (REST upsert) when the integration user has write ACLs, or through an instance-specific label-import path — **Docker Pattern** horizontal discovery enriches container/process relationships but **does not** by itself populate custom **`servicenow.io/*`** rows in this lab.

> **All platforms — servicenow.io keys**

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
<td><code>servicenow.io/application-identifier</code></td>
<td>Authors <strong>must</strong> set this label to the Business Application <code>identifier</code> declared in <code>csdm.yaml</code> (for example, <code>observability-platform</code>).</td>
</tr>
<tr>
<td><code>servicenow.io/business-service-identifier</code></td>
<td>Authors <strong>must</strong> set this label to the parent Business Service <code>identifier</code> (for example, <code>elasticsearch</code>).</td>
</tr>
<tr>
<td><code>servicenow.io/application-service-identifier</code></td>
<td>Authors <strong>must</strong> set this label to the Application Service <code>identifier</code>; this value <strong>must</strong> match the primary tag-based Service Mapping rule on the instance.</td>
</tr>
<tr>
<td><code>servicenow.io/environment</code></td>
<td>Authors <strong>must</strong> set this label to the application service <code>environment</code> or to <code>tag_defaults.environment</code> when the service inherits it (for example, <code>on-prem</code>).</td>
</tr>
<tr>
<td><code>servicenow.io/location</code></td>
<td>Authors <strong>must</strong> set this label to the same location name as the top-level <code>location</code> attribute (for example, <code>brooks-lab</code>).</td>
</tr>
<tr>
<td><code>servicenow.io/service-tier</code></td>
<td>Authors <strong>should</strong> set this label to the application service <code>service_tier</code> (for example, <code>data</code>, <code>web</code>, <code>ingest</code>).</td>
</tr>
<tr>
<td><code>servicenow.io/cluster</code></td>
<td>Authors <strong>should</strong> set this label to the application service <code>cluster</code> when <code>platform: kubernetes</code>.</td>
</tr>
<tr>
<td><code>servicenow.io/namespace</code></td>
<td>Authors <strong>may</strong> set this label to the application service <code>namespace</code> when <code>platform: kubernetes</code>.</td>
</tr>
</tbody>
</table>

1.3.1 Authors **must** apply the same **servicenow.io/** keys on Docker containers as on Kubernetes pods when using tag-based Service Mapping.

1.3.2 Authors **should** declare these keys in Docker Compose `labels:` blocks (see `observability/docker-compose.yml`) and in Kubernetes manifest labels; the deploy processor **may** emit a runtime tag manifest under `vars/contexts/csdm_runtime_tags/` for downstream automation.

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

2.1.1 The CSDM Modeler **must** use YAML lists for `business_applications`, `business_services`, and `application_services`.

2.1.2 Specifications **may** use Jinja for values resolved from context variable files at deploy time.

2.1.3 Application-specific CSDM names, identifiers, and descriptions **must** live in **`csdm.yaml`**, not in shared context registries.

2.1.4 Each file **should** live at `<application-playbook-dir>/servicenow/csdm.yaml` and **must** be registered in `csdm/common/vars.yml`.

2.1.5 Every BA, BS, and application service **must** declare an **`identifier`** obeying identifier rules in Definitions.

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
<tr><td><code>identifier</code></td><td>Authors <strong>must</strong> set a stable machine key used in <code>servicenow.io/application-identifier</code>.</td></tr>
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
<tr><td><code>identifier</code></td><td>Authors <strong>must</strong> set a stable machine key used in <code>servicenow.io/business-service-identifier</code>.</td></tr>
<tr><td><code>parent_business_application</code></td><td>Authors <strong>must</strong> set the parent BA <code>name</code>.</td></tr>
<tr><td><code>owned_by</code></td><td>Authors <strong>must</strong> set a ServiceNow <code>user_name</code>.</td></tr>
<tr><td><code>busines_criticality</code></td><td>Authors <strong>must</strong> set a choice value from Statement 2.7.</td></tr>
<tr><td><code>operational_status</code></td><td>Authors <strong>must</strong> set <code>"1"</code> for Operational.</td></tr>
<tr><td><code>short_description</code></td><td>Authors <strong>should</strong> set a human-readable summary.</td></tr>
</tbody>
</table>

#### 2.4 Application Service attributes

> **Application Service (<code>cmdb_ci_service_discovered</code>) attributes**

<table style="margin-left: 1.5em; width: 95%; border-collapse: collapse;">
<colgroup>
<col style="width: 25%">
<col style="width: 75%">
</colgroup>
<thead>
<tr><th>Field</th><th>Statement</th></tr>
</thead>
<tbody>
<tr><td><code>name</code></td><td>Authors <strong>must</strong> set the display name; authors <strong>may</strong> use <code>{host}</code> / <code>{host_lower}</code> with <code>expand</code>.</td></tr>
<tr><td><code>identifier</code></td><td>Authors <strong>must</strong> set a stable machine key that <strong>must</strong> match <code>servicenow.io/application-service-identifier</code> when tag-based.</td></tr>
<tr><td><code>parent_business_service</code></td><td>Authors <strong>must</strong> set the parent BS <code>name</code>.</td></tr>
<tr><td><code>owned_by</code></td><td>Authors <strong>must</strong> set a ServiceNow <code>user_name</code>.</td></tr>
<tr><td><code>busines_criticality</code></td><td>Authors <strong>must</strong> set a choice value from Statement 2.7.</td></tr>
<tr><td><code>operational_status</code></td><td>Authors <strong>must</strong> set <code>"1"</code> for Operational.</td></tr>
<tr><td><code>platform</code></td><td>Authors <strong>must</strong> set <code>kubernetes</code>, <code>docker</code>, <code>host</code>, or <code>saas</code>.</td></tr>
<tr><td><code>environment</code></td><td>Authors <strong>must</strong> set a value or inherit from <code>tag_defaults</code>.</td></tr>
<tr><td><code>location</code></td><td>Authors <strong>must</strong> set the CMDB location name; authors <strong>must</strong> match <code>servicenow.io/location</code> on workloads.</td></tr>
<tr><td><code>service_mapping</code></td><td>Authors <strong>must</strong> set <code>tags</code>, <code>vertical</code>, or <code>manual</code> per Statements 1.1.1–1.1.6.</td></tr>
<tr><td><code>discover</code></td><td>Authors <strong>must</strong> set <code>false</code> for Kubernetes, SaaS, and tag-based Docker/host; authors <strong>may</strong> set <code>true</code> only with <code>service_mapping: vertical</code> and Statement 1.6 satisfied.</td></tr>
<tr><td><code>service_tier</code></td><td>Authors <strong>should</strong> set <code>web</code>, <code>app</code>, <code>data</code>, <code>ingest</code>, <code>control-plane</code>, or <code>compute</code>.</td></tr>
<tr><td><code>cluster</code></td><td>Authors <strong>should</strong> set when <code>platform: kubernetes</code>.</td></tr>
<tr><td><code>namespace</code></td><td>Authors <strong>may</strong> set when <code>platform: kubernetes</code>.</td></tr>
<tr><td><code>depends_on</code></td><td>Authors <strong>should</strong> declare tiered consumer → provider lists.</td></tr>
<tr><td><code>tags</code></td><td>Authors <strong>must</strong> declare nested <code>kubernetes</code> and/or <code>docker</code> maps when <code>service_mapping: tags</code>.</td></tr>
<tr><td><code>entry_points</code></td><td>Authors <strong>must</strong> declare when <code>service_mapping: vertical</code> and <code>discover: true</code> on Docker/host.</td></tr>
<tr><td><code>expand</code></td><td>Authors <strong>may</strong> set <code>inventory_group</code> for per-host instances.</td></tr>
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

2.5.2.4 When tag-based, the CSDM Modeler **must** declare `tags.docker` per Statement 1.5 and apply **servicenow.io/** labels on Compose services.

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

2.6.2 Each item **may** be a string (application service `name`) or a mapping with `name` and optional `type` (`linux_server`, `nfs_server`, `business_service`).

2.6.3 The CSDM Modeler **should** set `csdm_defaults` at file scope for shared owners and criticality.

2.6.4 For **`csdm_op`**, authors **may** set `insert` (default, upsert) or `delete`. Delete entries **must** include `name`; the deploy processor removes relationships then the CI.

#### 2.7 Allowed values

2.7.1 **`busines_criticality`:** `1 - most critical`, `2 - somewhat critical`, `3 - less critical`, `4 - not critical`

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

3.2.3 The deploy processor **must** create **Contains::Contained by** for BA → BS → application service hierarchy.

3.2.4 The deploy processor **must** create **Depends on::Used by** for `depends_on` entries.

#### 3.3 Service Mapping triggers

3.3.1 The deploy processor **must** trigger vertical discovery asynchronously when `service_mapping: vertical` and `discover: true`; it **must not** wait for completion.

3.3.2 The deploy processor **must not** trigger vertical discovery for `platform: kubernetes`, `service_mapping: tags`, or `service_mapping: manual`.

3.3.3 For vertical entry points, the deploy processor **must** create `cmdb_ci_endpoint` with **Runs on::Runs** to host and register via Service Mapping Operations REST API (`addEntryPoint`).

3.3.4 For tag-based services, the deploy processor **must not** create entry points or call `addEntryPoint`.

3.3.5 The deploy processor **may** emit a runtime tag manifest under `vars/contexts/csdm_runtime_tags/` for downstream label application.

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

4.4 The discovery operator **must** run **`discovery/docker/discover.yml`** on Docker hosts where tag-based Service Mapping depends on **`cmdb_key_value`** rows from Compose labels; that playbook reads labels from `docker inspect` and upserts **`cmdb_key_value`** when the integration user has write ACLs.

4.5 When **`cmdb_key_value`** REST insert returns HTTP 403, operators **must** extend table ACLs so **`cmdb_inst_admin`** appears in **Requires role** on the active **create**, **write**, and **delete** ACLs for table **`cmdb_key_value`** — see `docs/install.md` §6.3. Read access is usually satisfied out of the box via **`cmdb_read`**. KVA populates Kubernetes labels as user **`system`**, which is a separate internal path.

4.6 The discovery operator **should** ensure the MID Server is **Up** before triggering horizontal discovery (`discovery/discover.yml` or Discover Now in the UI).

### 5. Service Mapping operator

5.1 The Service Mapping operator **must** configure tag-based rules matching **servicenow.io/application-service-identifier** (or the configured prefix) before tag-based application services can reach operational status.

5.2 The Service Mapping operator **should** monitor `process_status` and `service_status` on `cmdb_ci_service_discovered` after vertical triggers.

5.3 When migrating Docker services from vertical to tag-based, the operator **should** remove stale entry-point dependencies in the Service Mapping UI and reset `process_status` / `service_status` on affected application services per [Tag_Based_Service_Mapping.md](Tag_Based_Service_Mapping.md).

## Commentary

### Why identifiers and tags overlap

CSDM display **`name`** values are human-oriented. Tags and Service Mapping rules require stable machine keys. **`identifier`** is the single source of truth; top-level **`environment`**, **`location`**, and **`service_tier`** duplicate into **servicenow.io/** label keys so SM rules do not parse nested YAML.

### Why Docker Compose uses tag-based mapping in this lab

ServiceNow **allows** vertical discovery for Docker but **recommends** tags for Compose stacks that change frequently. Vertical discovery requires a traversable graph from entry point → TCP → process → container. Container inventory sync that only upserts `cmdb_ci_docker_container` rows without **cmdb_rel_ci** relationships leaves vertical discovery stuck in **Requirements** — tag-based mapping with Compose labels is the reliable path when **servicenow.io/** labels are on services and **Docker Pattern** or KVA has populated **`cmdb_key_value`**.

### Document rendering and tables

The VS Code built-in Markdown preview applies **`markdown.styles`** CSS inconsistently to wrapped `<div>` blocks and markdown pipe tables. For reliable table column widths and indentation:

- **Pandoc** (`pandoc CSDM_Specifications.md -o CSDM_Specifications.pdf --css=csdm-spec.css`) respects inline HTML `<colgroup>` widths used in this document.
- **Quarto** wraps Pandoc and simplifies multi-format publish (HTML/PDF) with shared CSS.
- **Markdown Preview Enhanced** (VS Code extension) applies custom CSS more predictably than the default preview.

Authors **should** prefer inline HTML tables with explicit `<colgroup>` percentages (25% / 75%) for normative attribute tables in this TPG.

### Deferred linking

Infrastructure targets and cross-file application services may not exist on first deploy. The second-pass linker resolves registry → CMDB lookup → defer without duplicate relationships.

## References

- ServiceNow CSDM documentation (Business Application, Business Service, Application Service)
- ServiceNow [Quick Start Guide for Service Mapping](https://www.servicenow.com/community/itom-articles/quick-start-guide-for-service-mapping/ta-p/3521583)
- [Tag_Based_Service_Mapping.md](Tag_Based_Service_Mapping.md) — instance UI paths, tag categories, ACL/Docker Pattern notes, and which application services need rules
- Kubernetes [Recommended Labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/)
- `meta-standards/tpgs-for-tpgs.md` — TPG structure and numbered Statements subsections
- `meta-standards/keywords-for-standards.md` — must, should, may
