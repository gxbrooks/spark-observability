# Dynatrace Entity Types and Relationships Reference

> Source: Dynatrace Semantic Dictionary / Smartscape Topology Model  
> API views: `dt.entity.*` (Grail / DQL)

---

## Dynatrace entities

Entities are organized by domain. Each entity has a unique ID, a detected name, lifetime timestamps, management zones, and tags.

> **ServiceNow SGC mapping:** Service Graph Connector for Observability – Dynatrace (`sn_dynatrace_integ` **v1.15.x**), discovery source **`SGO-Dynatrace`**. The paragraph immediately after each entity description states the CMDB class when SGC imports that type; if omitted, SGC does not create a CMDB CI for that Dynatrace entity. **Attribute tables** list RTE/IRE field mappings; **ServiceNow relationships** tables list `cmdb_rel_ci` edges from Smartscape imports; **Tag-based relationships** tables list `cmdb_key_value` keys whose **values** name a target CMDB record (membership by tag, not a Smartscape edge). See [DT_SN_Mapping.md](../DT_SN_Mapping.md), [Tag_Based_Service_Mapping.md](../Tag_Based_Service_Mapping.md), and [docker_model.md](docker_model.md).


### Tag-based relationships (`cmdb_key_value`)

In brooks-lab, **tags are relationships by another name**: each `cmdb_key_value` row stores a label on a CMDB CI. Tag-based Service Mapping matches those rows against an Application Service filter and creates **`cmdb_rel_ci` Contains::Contained by** edges. SGC copies Dynatrace entity tags the same way when **`DT_TAGS`** or auto-tag rules populate the Dynatrace entity.

Storage: **`cmdb_key_value.configuration_item`** → tagged CI; **`key`** / **`value`** → label pair.

#### Canonical CSDM keys (all platforms)

| Key | Value field |
| --- | --- |
| `servicenow.io/application-service-identifier` | `cmdb_ci_service_discovered.identifier` |
| `servicenow.io/application-identifier` | `cmdb_ci_business_app.identifier` |
| `servicenow.io/business-service-identifier` | `cmdb_ci_service.identifier` |
| `servicenow.io/environment` | `cmdb_ci_service_discovered.environment` |
| `servicenow.io/location` | `cmn_location.name` |

1. Keys are written to **`cmdb_key_value`** on workload CIs: `cmdb_ci_docker_container`, `cmdb_ci_kubernetes_pod`, `cmdb_ci_linux_server`, and (via SGC) `cmdb_ci_appl` / `cmdb_ci_group`.
2. The tag **value** must equal the target field on the CSDM CI (for example `cmdb_ci_service_discovered.identifier` from `*.csdm.yaml`).
3. When tag-based Service Mapping runs, parent **`cmdb_ci_service_discovered`** → **Contains::Contained by** → tagged workload CI.

#### Docker Compose keys (bridge + identity)

| Key | Value field |
| --- | --- |
| `com.docker.compose.service` | Compose service name (string) |
| `com.docker.compose.project` | Compose project name (string) |

1. Written by **`discovery/docker/discover.yml`** onto **`cmdb_ci_docker_container`** from `docker inspect` labels.
2. Not in the Dynatrace problem webhook unless mirrored via **`DT_TAGS`** onto the Dynatrace process group entity.
3. **`com.docker.compose.service`** bridges **`cmdb_ci_appl`** (process group CI) to **`cmdb_ci_docker_container`** on the same **`cmdb_ci_linux_server`** when the process group CI lacks `servicenow.io/*` tags.

#### Kubernetes keys (KVA + pod label sync)

| Key | Value field |
| --- | --- |
| `app.kubernetes.io/name` | Workload name (string) |
| `app.kubernetes.io/instance` | Helm release / instance (string) |
| `app.kubernetes.io/component` | Component role (string) |
| `app.kubernetes.io/part-of` | Product / business-app name (string) |

1. KVA writes **`app.kubernetes.io/*`** to **`cmdb_key_value`** on **`cmdb_ci_kubernetes_pod`** as user **`system`**.
2. **`discovery/k8s/sync_pod_labels.yml`** writes **`servicenow.io/*`** on the same pod CIs.
3. **`app.kubernetes.io/name`** is an alternate Service Mapping key when the canonical `servicenow.io/application-service-identifier` row is missing (compare report marks **`alternate_tag_only`**).

#### Dynatrace → CMDB tag copy (SGC)

| DT source | Key on DT entity | On class |
| --- | --- |
| Compose `DT_TAGS=…` | `servicenow.io/application-service-identifier` | `cmdb_ci_appl` / `cmdb_ci_group` |
| Auto-tag rules | `Environment`, `Project`, … | `cmdb_ci_computer`, `cmdb_ci_appl`, `cmdb_ci_service_auto`, … |
| Entity tags (any) | user-defined | Any SGC-imported CI |

1. SGC scheduled import copies Dynatrace entity tags into **`cmdb_key_value`** on the merged CMDB CI.
2. Only keys listed above participate in CSDM tag-based Service Mapping unless you add custom Tag Categories on the instance.

### 1. Core Application Stack (OneAgent-Monitored)

These are the primary entities discovered by OneAgent and form the backbone of Dynatrace's Smartscape topology.

#### 1.1 HOST — `dt.entity.host`
A physical or virtual machine running OneAgent. Dynatrace auto-discovers its OS, CPU, memory, disks, and network interfaces. This is the foundational compute entity.

Imported by the **SGO-Dynatrace Hosts** scheduled import (Hosts V2 cascade). IRE maps to **`cmdb_ci_computer`** and OS-specific subclasses (for example `cmdb_ci_linux_server`, `cmdb_ci_win_server`, `cmdb_ci_solaris_server`). Merges with Discovery/KVA host CIs when hostname identification rules match.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` / `detectedName` | `name`, `host_name` (IRE identifier) |
| `ipAddress` / `ipAddresses[]` | `ip_address` |
| `osType` | `os` (drives computer subclass selection) |
| `entityId` | `sys_object_source.id` |
| `tags` (key/value pairs) | `cmdb_key_value` rows on the CI |
| — | `discovery_source` includes `SGO-Dynatrace` |


**ServiceNow relationships** (Application Relationships + topology imports):

| DT rel | cmdb_rel_ci |
| --- | --- |
| `runs` (inverse `runs_on`) | Runs on::Runs: `HOST` → process / process group CI |
| `contains` | Contains::Contained by: `HOST` → disk / NIC CI (when imported) |
| `same_as` | IRE merge (see note) |

1. **`runs`**: parent `cmdb_ci_computer` (host), child `cmdb_ci_appl` or `cmdb_ci_group` (process tier).
2. **`same_as`**: IRE merge with cloud VM CIs; may not leave a visible `cmdb_rel_ci` row after merge.

**Tag-based relationships** (host agents):

| Key | Value field |
| --- | --- |
| `servicenow.io/application-service-identifier` | `cmdb_ci_service_discovered.identifier` |
| `servicenow.io/environment` | `cmdb_ci_service_discovered.environment` |
| `servicenow.io/location` | `cmn_location.name` |

1. Tags are on **`cmdb_ci_linux_server`**, written by **`discovery/host/sync_tags.yml`**.
2. Tag-based Service Mapping creates **`cmdb_rel_ci` Contains::Contained by** from **`cmdb_ci_service_discovered`** (parent) to **`cmdb_ci_linux_server`** (child).


#### 1.2 HOST_GROUP — `dt.entity.host_group`
A logical grouping of hosts used to apply shared monitoring settings, tags, and alerting policies across multiple hosts.


#### 1.3 PROCESS_GROUP — `dt.entity.process_group`
A group of identical process instances (e.g., all instances of a Tomcat JVM running the same app). Dynatrace automatically groups process instances that share the same technology, binary, and configuration.

Imported by **SGO-Dynatrace Process Groups** feed. Mapped to **`cmdb_ci_group`** (Group class) — the grouping entity for like processes in Smartscape service maps. Event problems may still reference `PROCESS_GROUP-…` in `sys_object_source` depending on import generation and IRE merge.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |
| `runs_on` → HOST | `host` reference + `cmdb_rel_ci` Runs on::Runs |
| `tags` (key/value pairs) | `cmdb_key_value` rows on the CI |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `runs_on` | Runs on::Runs: `cmdb_ci_group` → `cmdb_ci_computer` |
| `instance_of` (inverse) | Contains::Contained by: `cmdb_ci_group` → `cmdb_ci_appl` |
| `calls` / `called_by` | Depends on::Used by (Application Relationships import) |
| `group_of` | Depends on::Used by: `cmdb_ci_service_auto` → `cmdb_ci_group` |

1. SGC maps Dynatrace **PROCESS_GROUP** to **`cmdb_ci_group`**; IRE may merge to **`cmdb_ci_appl`**.
2. **`calls` / `called_by`** edges come from the Application Relationships import feed.

**Tag-based relationships:**

| Key | Value field |
| --- | --- |
| `servicenow.io/application-service-identifier` | `cmdb_ci_service_discovered.identifier` |
| `servicenow.io/environment` | `cmdb_ci_service_discovered.environment` |
| `servicenow.io/location` | `cmn_location.name` |

1. When set via **`DT_TAGS`** in Compose/K8s and copied by SGC, tags land on **`cmdb_ci_appl`** or **`cmdb_ci_group`** (process group CI). Incident lookup: tag value → **`cmdb_ci_service_discovered.identifier`**.
2. Without **`DT_TAGS`**, process group CIs usually lack `servicenow.io/*` rows — bridge via **`cmdb_rel_ci` Runs on::Runs** to **`cmdb_ci_linux_server`**, then match **`cmdb_ci_docker_container`** or **`cmdb_ci_kubernetes_pod`** tags on that host/cluster.


#### 1.4 PROCESS_GROUP_INSTANCE — `dt.entity.process_group_instance`
A single running process detected on a specific host — for example, one specific JVM process. It is an instance of a Process Group.

Imported via the **Processes / Process Groups** cascade. Mapped to **`cmdb_ci_appl`** (Application class). v1.14.1+ normalizes executable path and command-line parameters before IRE identification to avoid cross-OS duplicate CIs.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `executable` / command line | IRE identifier (normalized path + parameters) |
| `entityId` | `sys_object_source.id` |
| `runs_on` → HOST | `host` reference + Runs on::Runs relationship |
| `tags` (key/value pairs) | `cmdb_key_value` rows on the CI |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `runs_on` | Runs on::Runs: `cmdb_ci_appl` → `cmdb_ci_computer` |
| `instance_of` | Contains::Contained by: `cmdb_ci_group` → `cmdb_ci_appl` |
| `runs_on` | Depends on::Used by: `cmdb_ci_service_auto` → `cmdb_ci_appl` |

1. **`instance_of`**: parent **`cmdb_ci_group`**, child **`cmdb_ci_appl`**.

#### 1.5 SERVICE — `dt.entity.service`
A logical service discovered by Dynatrace based on the technology and entry point of a Process Group (e.g., a Java web service, a Node.js app, a .NET WCF service). Services track request rates, response times, and error rates.

Imported by **SGO-Dynatrace Services** feed. Default target is **`cmdb_ci_service_calculated`** (Calculated Application Service). When Dynatrace `serviceType` is **`DATABASE_SERVICE`**, SGC maps to **`cmdb_ci_db_instance`** instead (onboarding guide).

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` (+ environment context in v1.14.1+) | `name` |
| `entityId` | `sys_object_source.id` |
| `serviceType` | CMDB class selection (`DATABASE_SERVICE` → db instance) |
| `tags` (key/value pairs) | `cmdb_key_value` rows on the CI |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `runs_on` | Depends on::Used by: `cmdb_ci_service_auto` → `cmdb_ci_group` |
| `calls` / `called_by` | Depends on::Used by: `SERVICE` → peer service / app CI |
| `served_by` (inverse `serves`) | Depends on::Used by: `cmdb_ci_service_calculated` → `cmdb_ci_service_auto` |
| `balanced_by` | Connects to::Connected by / Depends on::Used by: `cmdb_ci_cloud_load_balancer` → `cmdb_ci_service_auto` |

#### 1.6 SERVICE_INSTANCE — `dt.entity.service_instance`
A specific instance of a service running on a given Process Group Instance. Used for fine-grained tracking when multiple instances of a service run in parallel.


#### 1.7 SERVICE_METHOD — `dt.entity.service_method`
An individual endpoint or operation within a service (e.g., `/api/checkout` or `OrderService.createOrder()`). Dynatrace captures key requests and top-X requests used for baselining.


#### 1.8 DISK — `dt.entity.disk`
A disk or storage volume attached to a host. Monitored for I/O throughput, latency, and utilization.


#### 1.9 NETWORK_INTERFACE — `dt.entity.network_interface`
A network interface card (NIC) on a host. Monitored for bandwidth utilization, packet loss, and errors.


---

### 2. Application & User Experience (RUM / Synthetic)

Entities related to frontend/user-facing monitoring.

#### 2.1 APPLICATION — `dt.entity.application`
A Real User Monitoring (RUM) web application. Represents the frontend experience monitored via injected JavaScript (OneAgent RUM). Tracks page load times, user actions, errors, and Apdex scores.

Imported by **SGO-Dynatrace Applications** feed. Mapped to **`cmdb_ci_service_calculated`** — the same Calculated Application Service class used for Smartscape **SERVICE** entities (top-level RUM application becomes a calculated service node in the SGC service map).

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |
| `tags` (key/value pairs) | `cmdb_key_value` rows on the CI |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `calls` | Depends on::Used by: `APPLICATION` → `cmdb_ci_service_calculated` (SERVICE) |
| `monitored_by` | Monitors::Monitored by: `Synthetic CI` → APPLICATION (when synthetic CIs imported) |

#### 2.2 MOBILE_APPLICATION — `dt.entity.mobile_application`
A native mobile app (iOS/Android) monitored via the Dynatrace Mobile SDK. Tracks crashes, user sessions, network requests, and custom actions.

Imported with **Applications** when the mobile app is in scope. Mapped to **`cmdb_ci_service_calculated`**.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `calls` | Depends on::Used by: `cmdb_ci_service_calculated` → `cmdb_ci_service_auto` |

#### 2.3 CUSTOM_APPLICATION — `dt.entity.custom_application`
An application monitored using a custom RUM approach (e.g., smart TV, IoT app) via the Dynatrace JavaScript or OpenKit SDK.

Imported by **SGO-Dynatrace Custom Applications** feed (`sn_dynatrace_integ_sgo_dynatrace_custom_applications`). Mapped to **`cmdb_ci_service_calculated`**.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `calls` | Depends on::Used by: `cmdb_ci_service_calculated` → `cmdb_ci_service_auto` |

#### 2.4 APPLICATION_METHOD — `dt.entity.application_method`
*(Discontinued in Smartscape)* A RUM user action (e.g., a button click or page navigation event). Used in Classic Dynatrace for problem analysis.


#### 2.5 APPLICATION_METHOD_GROUP — `dt.entity.application_method_group`
*(Discontinued in Smartscape)* A group of application methods within an application. Used in Classic problem analysis.


#### 2.6 SYNTHETIC_TEST — `dt.entity.synthetic_test`
A Dynatrace-managed synthetic monitor — typically a browser-based clickpath test that simulates user interaction with a web application from a defined location.


#### 2.7 SYNTHETIC_TEST_STEP — `dt.entity.synthetic_test_step`
An individual step within a synthetic browser test (e.g., "click login button" or "verify page title").


#### 2.8 EXTERNAL_SYNTHETIC_TEST — `dt.entity.external_synthetic_test`
A synthetic test run by a third-party monitoring tool (e.g., Catchpoint, Apica) that feeds availability data into Dynatrace.


#### 2.9 HTTP_CHECK — `dt.entity.http_check`
A lightweight HTTP availability check (ping monitor) that tests a URL endpoint for uptime and response time from a Dynatrace location.


#### 2.10 HTTP_CHECK_STEP — `dt.entity.http_check_step`
An individual step within a multi-step HTTP check.


#### 2.11 BROWSER — `dt.entity.browser`
*(Discontinued in Smartscape)* Represented browser types/families used in Classic Dynatrace RUM for problem analysis.


---

### 3. Kubernetes Entities

Entities auto-discovered when OneAgent or the Dynatrace Operator monitors containerized workloads.

#### 3.1 KUBERNETES_CLUSTER — `dt.entity.kubernetes_cluster`
The top-level Kubernetes cluster entity. Dynatrace discovers this via the Dynatrace Operator or OneAgent on cluster nodes.

Imported by **SGO-Dynatrace Kubernetes Cluster** feed. Mapped to **`cmdb_ci_kubernetes_cluster`**. Merges with KVA Informer cluster CIs when cluster name identification matches.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` / cluster name | `name` |
| `entityId` | `sys_object_source.id` |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `contains` | Contains::Contained by: `CLUSTER` → node / namespace CI |
| `clustered_by` (inverse) | Member of::Members or Contains: `workload` → cluster (RTE-dependent) |

#### 3.2 KUBERNETES_NODE — `dt.entity.kubernetes_node`
A worker or control-plane node within a Kubernetes cluster. Tracked for CPU, memory, pod capacity, and conditions (Ready, MemoryPressure, etc.).

Imported by **SGO-Dynatrace Kubernetes Node** feed. Mapped to **`cmdb_ci_kubernetes_node`** with **Runs on::Runs** to the underlying host CI when present.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |
| cluster relationship | `cmdb_rel_ci` to cluster CI |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `belongs_to` / `clustered_by` | Contains::Contained by: `CLUSTER` → node CI |
| `runs_on` | Runs on::Runs: `NODE` → underlying `cmdb_ci_computer` |
| `runs` | Runs on::Runs: `cmdb_ci_kubernetes_pod` → `cmdb_ci_kubernetes_node` |

#### 3.3 KUBERNETES_SERVICE — `dt.entity.kubernetes_service`
A Kubernetes Service resource (ClusterIP, NodePort, LoadBalancer). Represents the network entry point routing traffic to Pods.

Imported by Kubernetes service imports in the SGC cascade. Mapped to **`cmdb_ci_kubernetes_service`**.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |
| namespace / cluster | parent `cmdb_rel_ci` links |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `belongs_to` | Contains::Contained by: `NAMESPACE` → K8s service CI |
| `cluster_of` / `calls` | Depends on::Used by: `K8s service` → workload / Smartscape service |

#### 3.4 CLOUD_APPLICATION — `dt.entity.cloud_application`
A Kubernetes workload — such as a Deployment, StatefulSet, DaemonSet, Job, or CronJob. This is the Dynatrace model for a running application definition in Kubernetes.

Imported as a Kubernetes workload (Deployment/StatefulSet/DaemonSet). Mapped to **`cmdb_ci_kubernetes_deployment`** (or workload subclass supported by `sn_cmdb_ci_class`).

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `belongs_to` | Contains::Contained by: `NAMESPACE` → deployment CI |
| `clustered_by` | Contains::Contained by: `CLUSTER` → deployment (via namespace) |
| `instantiates` | Contains::Contained by: `DEPLOYMENT` → pod CI |

#### 3.5 CLOUD_APPLICATION_INSTANCE — `dt.entity.cloud_application_instance`
A single Kubernetes Pod. It is an instance of a Cloud Application (workload). Tracked for container restarts, resource requests/limits, and scheduling status.

Imported by **SGO-Dynatrace Kubernetes Pod** feed. Mapped to **`cmdb_ci_kubernetes_pod`**.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |
| `runs_on` node | Runs on::Runs to node CI |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `instance_of` | Contains::Contained by: `DEPLOYMENT` → pod CI |
| `runs_on` | Runs on::Runs: `cmdb_ci_kubernetes_pod` → `cmdb_ci_kubernetes_node` |
| `contains` | Contains::Contained by: `cmdb_ci_kubernetes_pod` → `cmdb_ci_docker_container` / `cmdb_ci_appl` |

**Tag-based relationships** (pod CIs):

| Key | Value field |
| --- | --- |
| `servicenow.io/application-service-identifier` | `cmdb_ci_service_discovered.identifier` |
| `servicenow.io/environment` | `cmdb_ci_service_discovered.environment` |
| `servicenow.io/location` | `cmn_location.name` |
| `app.kubernetes.io/name` | Workload name (string) |
| `app.kubernetes.io/component` | Component role (string) |
| `app.kubernetes.io/part-of` | Product name (string) |

1. Tags are on **`cmdb_ci_kubernetes_pod`**. `servicenow.io/*` from **`discovery/k8s/sync_pod_labels.yml`**; `app.kubernetes.io/*` from KVA.
2. Dynatrace **`CLOUD_APPLICATION_INSTANCE`** binds to the same pod CI via **`sys_object_source`** — tags are on the CMDB row, not in the problem webhook payload.
3. Service Mapping match creates **`cmdb_rel_ci` Contains::Contained by** from **`cmdb_ci_service_discovered`** to **`cmdb_ci_kubernetes_pod`**.


#### 3.6 CLOUD_APPLICATION_NAMESPACE — `dt.entity.cloud_application_namespace`
A Kubernetes Namespace. Provides logical isolation scope for workloads, services, and pods within a cluster.

Imported by **SGO-Dynatrace Kubernetes Namespace** feed. Mapped to **`cmdb_ci_kubernetes_namespace`**.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `belongs_to` / `clustered_by` | Contains::Contained by: `CLUSTER` → namespace CI |
| `contains` | Contains::Contained by: `NAMESPACE` → workload / service CI |


### 4. Docker & Compose Entities

Docker workloads on bare-metal or VM hosts use a **dual CMDB path** in brooks-lab — unlike Kubernetes, where SGC owns the full cluster hierarchy:

| Path | Source | CMDB result |
| --- | --- |
| **SGC topology import** | OneAgent on container host; Smartscape process/container entities | `cmdb_ci_computer`, `cmdb_ci_group`, `cmdb_ci_appl`, `cmdb_ci_service_auto` / `cmdb_ci_service_calculated`, optional `cmdb_ci_docker_container` when container entity is in cascade |
| **ServiceNow Discovery** | `discovery/docker/discover.yml` on `DOCKER_HOSTS` with `container_discovery: true` | `cmdb_ci_docker_container` + **`cmdb_key_value`** from Compose labels (`com.docker.compose.*`, `servicenow.io/*`) |
| **CSDM Service Mapping** | Tag-based SM on Application Services | **`cmdb_rel_ci` Contains::Contained by** from `cmdb_ci_service_discovered` → container / host (not from Dynatrace) |

Dynatrace **`CONTAINER_GROUP`** / **`CONTAINER_GROUP_INSTANCE`** appear on Docker hosts and inside K8s pods. On Compose hosts, correlate container CIs to process groups via **shared host** + Compose service name tags — see [docker_model.md](docker_model.md).

#### 4.1 CONTAINER_GROUP — `dt.entity.container_group`
A logical grouping of identical container instances (analogous to **PROCESS_GROUP** for container images). Dynatrace groups containers that share image, name pattern, and orchestration metadata.

When the Docker/container import set is enabled in the SGC cascade, may map to a grouping CI or roll up under the pod/host. On standalone Docker hosts, Smartscape often surfaces **PROCESS_GROUP** first; container group is secondary.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |
| image / orchestration metadata | container image fields when RTE maps them |

**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `contains` | Contains::Contained by → `cmdb_ci_docker_container` |
| `runs_on` | Runs on::Runs → `cmdb_ci_computer` / `cmdb_ci_kubernetes_node` |
| `group_of` | Smartscape only; CMDB bridge via tags (see below) |

**Tag-based relationships** (bridge to container):

| Key | Value field |
| --- | --- |
| `servicenow.io/application-service-identifier` | `cmdb_ci_service_discovered.identifier` |
| `com.docker.compose.service` | Compose service name (string) |
| `com.docker.compose.project` | Compose project name (string) |

1. Tags are on **`cmdb_ci_docker_container`**, not on the Dynatrace container group entity.
2. Bridge when **`cmdb_ci_appl`** (process group) lacks `servicenow.io/*`: process group **`cmdb_rel_ci` Runs on::Runs** → **`cmdb_ci_linux_server`**, then find container on that host with matching **`cmdb_key_value`**.
3. Tag-based Service Mapping creates **`cmdb_rel_ci` Contains::Contained by** from **`cmdb_ci_service_discovered`** to **`cmdb_ci_docker_container`**.


#### 4.2 CONTAINER_GROUP_INSTANCE — `dt.entity.container_group_instance`
A single running container — on a Docker host or inside a Kubernetes pod. Carries OCI image metadata, container runtime info, and resource limits.

Imported by Docker/container feeds when enabled. Mapped to **`cmdb_ci_docker_container`** (standalone Docker) or child container CI under **`cmdb_ci_kubernetes_pod`** (K8s). Brooks-lab **`discovery/docker/discover.yml`** also creates/updates **`cmdb_ci_docker_container`** independently of SGC, with Compose labels in **`cmdb_key_value`**.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` / container name | `name` |
| `entityId` | `sys_object_source.id` |
| image metadata | `image`, `container_id` (Discovery sync) |
| Compose labels | **`cmdb_key_value`** via Discovery (`discover.yml`), not SGC |

**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `instance_of` | Contains::Contained by → `cmdb_ci_docker_container` |
| `runs_on` | Runs on::Runs: `cmdb_ci_docker_container` → `cmdb_ci_computer` |
| `belongs_to` | Contains::Contained by: `cmdb_ci_kubernetes_pod` → `cmdb_ci_docker_container` |
| `contains` | Contains::Contained by: `cmdb_ci_docker_container` → `cmdb_ci_appl` |
| CSDM tag-based SM | Contains::Contained by: `cmdb_ci_service_discovered` → `cmdb_ci_docker_container` |

1. **`CSDM tag-based SM`** row is not a Dynatrace edge — created when Service Mapping matches container tags.
2. On K8s, same container entity may appear under **`cmdb_ci_kubernetes_pod`** via **`belongs_to`**.

**Tag-based relationships:**

| Key | Value field |
| --- | --- |
| `servicenow.io/application-service-identifier` | `cmdb_ci_service_discovered.identifier` |
| `servicenow.io/application-identifier` | `cmdb_ci_business_app.identifier` |
| `servicenow.io/business-service-identifier` | `cmdb_ci_service.identifier` |
| `servicenow.io/environment` | `cmdb_ci_service_discovered.environment` |
| `servicenow.io/location` | `cmn_location.name` |
| `com.docker.compose.service` | Compose service name (string) |
| `com.docker.compose.project` | Compose project name (string) |

1. All rows on **`cmdb_ci_docker_container`**, written by **`discovery/docker/discover.yml`** from Compose/`docker inspect` labels.
2. Primary Service Mapping key: **`servicenow.io/application-service-identifier`** → **`cmdb_ci_service_discovered.identifier`**.


#### 4.3 Docker host application stack — HOST, PROCESS_GROUP, SERVICE
On a Compose host (Lab3 pattern), Smartscape typically materializes:

```
HOST (lab3)
 └─runs─► PROCESS_GROUP (containerized app process)
           └─instance_of─► PROCESS_GROUP_INSTANCE
HOST ◄─Runs on── cmdb_ci_docker_container   (Discovery + optional SGC)
PROCESS_GROUP ◄─Depends on── SERVICE        (SGC Application Relationships)
```

| Dynatrace entity | ServiceNow class | Key relationships imported |
| --- | --- |
| **HOST** | `cmdb_ci_linux_server` (merged) | **Runs** process groups; **Contains** disks/NICs |
| **PROCESS_GROUP** | `cmdb_ci_group` / `cmdb_ci_appl` (IRE) | **Runs on::Runs** → host; **Depends on::Used by** ← SERVICE |
| **PROCESS_GROUP_INSTANCE** | `cmdb_ci_appl` | **Runs on::Runs** → host |
| **SERVICE** | `cmdb_ci_service_auto` | **Depends on::Used by** → process group; **calls** peers |
| **CONTAINER_GROUP_INSTANCE** | `cmdb_ci_docker_container` | Runs on::Runs → `cmdb_ci_computer`; Contains::Contained by from `cmdb_ci_service_discovered` (tag-based SM) |

**Tag bridge (process group alert):** When **`em_alert.cmdb_ci`** is **`cmdb_ci_appl`** without `servicenow.io/*` tags: (1) follow **`cmdb_rel_ci` Runs on::Runs** to **`cmdb_ci_linux_server`**; (2) find **`cmdb_ci_docker_container`** on that host with matching **`cmdb_key_value`**; (3) resolve **`cmdb_ci_service_discovered`** where **`identifier`** equals the tag value. Optional: **`DT_TAGS=servicenow.io/application-service-identifier=<identifier>`** in Compose so SGC copies the tag onto the process group CI.

**Problem / event binding:** Log and APM problems usually attach to **`PROCESS_GROUP`** or **HOST**, not the container CI, unless `sys_object_source` exists for the container **`entityId`**. Plan incident automation accordingly — see [docker_model.md](docker_model.md).

---

### 5. Custom & Extension Entities

Entities used when monitoring devices or systems not natively instrumented by OneAgent.

#### 5.1 CUSTOM_DEVICE — `dt.entity.custom_device`
A device or system monitored via the Dynatrace Custom Device API or an Extension (e.g., a router, switch, PLC, or any technology Dynatrace doesn't instrument natively).


#### 5.2 CUSTOM_DEVICE_GROUP — `dt.entity.custom_device_group`
A logical group of custom devices, automatically or manually organized for shared alerting and monitoring settings.


#### 5.3 QUEUE — `dt.entity.queue`
A messaging queue or topic (e.g., ActiveMQ, RabbitMQ, IBM MQ, Kafka topic) discovered through process monitoring or extensions.


#### 5.4 QUEUE_INSTANCE — `dt.entity.queue_instance`
A specific instance of a queue on a specific message broker host. Tracks message throughput, queue depth, and consumer lag.


#### 5.5 QUEUE_LISTENER — `dt.entity.queue_listener`
A listener/consumer process attached to a queue, tracked as part of distributed tracing through messaging systems.


---

### 6. AWS Entities

Cloud infrastructure entities discovered via the Dynatrace AWS integration or CloudWatch extension.

#### 6.1 AWS_CREDENTIALS — `dt.entity.aws_credentials`
Represents an AWS account/IAM role credential set configured in Dynatrace for cloud monitoring. The top-level AWS account scope entity.


#### 6.2 AWS_AVAILABILITY_ZONE — `dt.entity.aws_availability_zone`
An AWS Availability Zone within a region. Contains EC2 instances, Lambda functions, RDS instances, and DynamoDB tables deployed within it.


#### 6.3 EC2_INSTANCE — `dt.entity.ec2_instance`
An Amazon EC2 virtual machine instance. Tracks instance type, AMI, VPC, security groups, and CloudWatch metrics.

Imported by **SGO-Dynatrace AWS EC2 / VM** cloud feeds in the Hosts cascade. Mapped to **`cmdb_ci_vm_instance`** (cloud VM class). May merge with **`cmdb_ci_ec2_instance`** when class rules match.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |
| AWS account / region / AZ tags | cloud metadata fields on VM CI |
| underlying host relationship | `cmdb_rel_ci` Runs on::Runs when DT provides host link |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `runs_on` | Runs on::Runs: `cmdb_ci_vm_instance` → `cmdb_ci_computer` |
| `balanced_by` | Connects to::Connected by: `LB` → `cmdb_ci_vm_instance` |
| `belongs_to` | Contains::Contained by: `AZ` → EC2 CI (when AZ imported) |
| `same_as` | IRE merge with OneAgent host |

#### 6.4 AUTO_SCALING_GROUP — `dt.entity.auto_scaling_group`
An AWS Auto Scaling Group. Tracks scaling events, min/max/desired capacity, and which EC2 instances belong to it.


#### 6.5 AWS_APPLICATION_LOAD_BALANCER — `dt.entity.aws_application_load_balancer`
An AWS ALB (Application Load Balancer). Distributes HTTP/HTTPS traffic across targets. Tracked for request counts, latency, and unhealthy targets.

Imported by AWS load-balancer cloud feeds. Mapped to **`cmdb_ci_cloud_load_balancer`** (or AWS-specific LB subclass).

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |
| target relationships | `cmdb_rel_ci` balances / Depends on |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `balances` | Connects to::Connected by or Depends on::Used by: `ALB` → target CI |
| `calls` | Depends on::Used by: `ALB` → Smartscape service (APM path) |
| Frontend VIP / DNS | `ip_address`, `fqdn` on `cmdb_ci_cloud_load_balancer`; listener frontend port may appear in custom attributes when RTE maps them ← Entity properties (not a separate DT entity) |

**VIP → backend host:port:** Dynatrace models **targets** (VM, Lambda, or service) via `balances` and APM **`calls`**, not as separate Azure-style frontend/backend pool CIs. SGC does **not** import AWS listener rule rows (frontendPort → targetGroup → backendPort) as distinct CMDB classes — that granularity requires **AWS Cloud Discovery** or manual modeling. When OneAgent monitors a backend service, **`calls`** links the ALB to the **`SERVICE`** / **`PROCESS_GROUP`** representing the host:port workload.

#### 6.6 AWS_NETWORK_LOAD_BALANCER — `dt.entity.aws_network_load_balancer`
An AWS NLB (Network Load Balancer). Distributes TCP/UDP traffic at the connection level.

Imported by AWS NLB cloud feeds. Mapped to **`cmdb_ci_cloud_load_balancer`**.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `balances` | Connects to::Connected by: `NLB` → target VM CI |
| `calls` | Depends on::Used by: `NLB` → backend SERVICE (when APM sees traffic) |

**VIP → host:port:** NLB frontend IP and listener ports are attributes on the LB CI; backend socket pairs appear indirectly via **`balances`** to targets and **`calls`** to monitored services — not as separate listener CIs in SGC.

#### 6.7 ELASTIC_LOAD_BALANCER — `dt.entity.elastic_load_balancer`
An AWS Classic ELB (Elastic Load Balancer, the original generation). Routes traffic to EC2 instances.

Imported by Classic ELB cloud feeds. Mapped to **`cmdb_ci_cloud_load_balancer`**.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `balances` | Connects to::Connected by: `Classic ELB` → EC2 CI |
| `calls` | Depends on::Used by: `ELB` → backend SERVICE |

#### 6.8 AWS_LAMBDA_FUNCTION — `dt.entity.aws_lambda_function`
An AWS Lambda serverless function. Tracked for invocations, duration, errors, concurrency, and cold starts.

Imported by **SGO-Dynatrace AWS Lambda** feeds. Mapped to **`cmdb_ci_cloud_function`**.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |
| region / account | cloud scope attributes |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `balanced_by` | Connects to::Connected by: `LB` → Lambda CI |
| `calls` / `called_by` | Depends on::Used by (Application Relationships) ← SERVICE, other Lambda |

#### 6.9 DYNAMO_DB_TABLE — `dt.entity.dynamo_db_table`
An AWS DynamoDB NoSQL table. Tracked for read/write capacity units, latency, and throttling.


#### 6.10 RELATIONAL_DATABASE_SERVICE — `dt.entity.relational_database_service`
An AWS RDS managed database instance (MySQL, PostgreSQL, SQL Server, Oracle, etc.). Tracked for connections, IOPS, and query performance.

Imported by AWS RDS feeds. When modeled as a Dynatrace **`DATABASE_SERVICE`**, also maps via Services import to **`cmdb_ci_db_instance`**. RDS-specific cloud import sets target database instance classes (for example `cmdb_ci_aws_rds_instance` when configured in CI Class Models).

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |
| engine / endpoint | database technology fields |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `calls` / `called_by` | DB → Depends on::Used by ← client SERVICE |
| `belongs_to` | Contains::Contained by: `AZ` → RDS CI |

#### 6.11 EBS_VOLUME — `dt.entity.ebs_volume`
An Amazon Elastic Block Store volume attached to an EC2 instance. Tracked for IOPS, throughput, and latency.


#### 6.12 S3_BUCKET — `dt.entity.s3bucket`
An Amazon S3 storage bucket. Tracked for storage metrics and access patterns via CloudWatch integration.

Imported by **SGO-Dynatrace AWS S3** feeds. Mapped to cloud object-storage CI classes (for example **`cmdb_ci_cloud_object_storage`** / S3 bucket subclass per `sn_cmdb_ci_class`).

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` / bucket name | `name` |
| `entityId` | `sys_object_source.id` |



**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `accessible_by` | credentials scope (monitoring); rarely a traversable SM edge ← AWS_CREDENTIALS |
| `calls` / client | Depends on::Used by: `client CI` → bucket CI (when modeled) |
---

### 7. Azure Entities

Cloud infrastructure entities discovered via the Dynatrace Azure integration.

#### 7.1 AZURE_TENANT — `dt.entity.azure_tenant`
The root Azure Entra ID (formerly AAD) tenant. Top-level organizational scope for all Azure resources.


#### 7.2 AZURE_MGMT_GROUP — `dt.entity.azure_mgmt_group`
An Azure Management Group for hierarchically organizing subscriptions under a tenant.


#### 7.3 AZURE_SUBSCRIPTION — `dt.entity.azure_subscription`
An Azure Subscription — the billing and access management scope for Azure resources.


#### 7.4 AZURE_CREDENTIALS — `dt.entity.azure_credentials`
The Azure credential/service principal configured in Dynatrace for cloud monitoring.


#### 7.5 AZURE_REGION — `dt.entity.azure_region`
An Azure geographic region (e.g., East US, West Europe). Contains all region-specific resources.


#### 7.6 AZURE_VM — `dt.entity.azure_vm`
An Azure Virtual Machine. Tracked for CPU, memory, disk, and network metrics.

Imported by **SGO-Dynatrace Azure VM** feeds. Mapped to **`cmdb_ci_vm_instance`**. v1.14.1+ creates **`Runs on::Runs`** to the host-tier CI so service maps traverse through the VM layer.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |
| region / resource group / subscription | Azure metadata on VM CI |
| host / compute link | `cmdb_rel_ci` Runs on::Runs (v1.14.1+) |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `runs_on` | Runs on::Runs: `VM` → host / computer CI |
| `balanced_by` | Connects to::Connected by: `LB` → VM CI |
| `hosted_by` | subscription/region Contains (when org entities imported) ← Azure region / subscription scope |

#### 7.7 AZURE_VM_SCALE_SET — `dt.entity.azure_vm_scale_set`
An Azure VM Scale Set — a group of identical VMs that auto-scale together.


#### 7.8 AZURE_WEB_APP — `dt.entity.azure_web_app`
An Azure App Service Web App (PaaS hosted website or API).

Imported by Azure App Service cloud feeds. Mapped to **`cmdb_ci_azure_web_app`** (or PaaS web-app subclass).

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `hosted_by` | Contains::Contained by: `plan` → web app (when plan imported) |
| `calls` / `called_by` | Depends on::Used by ← SERVICE, SQL, storage |

#### 7.9 AZURE_FUNCTION_APP — `dt.entity.azure_function_app`
An Azure Function App — the serverless compute resource hosting Azure Functions.

Imported by Azure Function App feeds. Mapped to **`cmdb_ci_cloud_function`** / Azure function CI subclass.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `hosted_by` | Contains::Contained by: `plan` → function app |
| `calls` / `called_by` | Depends on::Used by ← SERVICE, Event Hub, storage |

#### 7.10 AZURE_APP_SERVICE_PLAN — `dt.entity.azure_app_service_plan`
The underlying compute tier (pricing tier / worker pool) that hosts Azure Web Apps and Function Apps.


#### 7.11 AZURE_APPLICATION_GATEWAY — `dt.entity.azure_application_gateway`
An Azure Application Gateway — a Layer 7 load balancer with WAF capability, routing HTTP/HTTPS traffic to backend VMs.

Imported by Azure Application Gateway feeds. Mapped to **`cmdb_ci_cloud_load_balancer`** / application gateway subclass.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `balances` | Connects to::Connected by: `App Gateway` → backend CI |
| `calls` | Depends on::Used by: `cmdb_ci_cloud_load_balancer` → `cmdb_ci_service_auto` |

**Frontend VIP:** public/private frontend IP and listener config are LB CI attributes; backend pool members link via **`balances`**. Rule-level frontendPort → backendPort → host:port is **not** expanded into `cmdb_ci_azure_lb_*` pool CIs by Dynatrace SGC alone.

#### 7.12 AZURE_LOAD_BALANCER — `dt.entity.azure_load_balancer`
An Azure Load Balancer — a Layer 4 load balancer distributing TCP/UDP traffic across VMs.

Imported by Azure Load Balancer feeds. Mapped to **`cmdb_ci_cloud_load_balancer`**.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `balances` | Connects to::Connected by: `Azure LB` → `cmdb_ci_vm_instance` |
| `calls` | Depends on::Used by: `Azure LB` → Smartscape SERVICE (when traffic is APM-visible) |

**Virtual IP → backend host:port:** In Dynatrace, the **AZURE_LOAD_BALANCER** entity carries frontend VIP and SKU metadata as properties. Smartscape links **`balances`** to each **AZURE_VM** in the backend pool. SGC imports the LB CI plus those **`balances`** edges — it does **not** create separate ServiceNow **`cmdb_ci_azure_lb_frontend_ip_config`** or **`cmdb_ci_azure_lb_backend_pool`** rows (those come from **Azure Cloud Discovery** patterns). Per-rule **frontend port → backend IP:port** appears in CMDB only when (a) OneAgent **`calls`** links the LB to a **`SERVICE`** on a known host:port, or (b) Azure Discovery populates native LB child CIs. For brooks-lab SGC-only imports, plan on **LB → VM** edges plus optional **LB → SERVICE** call-path edges, not a full listener matrix.

#### 7.13 AZURE_API_MANAGEMENT_SERVICE — `dt.entity.azure_api_management_service`
Azure API Management (APIM) — an API gateway for publishing, securing, and monitoring APIs.


#### 7.14 AZURE_COSMOS_DB — `dt.entity.azure_cosmos_db`
Azure Cosmos DB — a globally distributed NoSQL database service. Tracked for RUs, latency, and availability.

Imported by Azure Cosmos DB feeds. Mapped to NoSQL / Cosmos DB CI classes (for example **`cmdb_ci_nosql`** / Azure Cosmos subclass).

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `calls` / `called_by` | Depends on::Used by ← SERVICE, AZURE_FUNCTION_APP |

#### 7.15 AZURE_SQL_SERVER — `dt.entity.azure_sql_server`
An Azure SQL Server logical server — the parent container for Azure SQL Databases and Elastic Pools.


#### 7.16 AZURE_SQL_DATABASE — `dt.entity.azure_sql_database`
An Azure SQL Database (individual managed relational database). Tracked for DTU usage, connection counts, and query performance.

Imported by Azure SQL Database feeds. Mapped to **`cmdb_ci_db_instance`** / **`cmdb_ci_azure_sql_database`**.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |
| server parent | `cmdb_rel_ci` to Azure SQL Server CI |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `belongs_to` | Contains::Contained by: `SQL Server` → database CI |
| `calls` / `called_by` | Depends on::Used by ← SERVICE, AZURE_WEB_APP |

#### 7.17 AZURE_SQL_ELASTIC_POOL — `dt.entity.azure_sql_elastic_pool`
An Azure SQL Elastic Pool — a shared resource pool for multiple SQL databases with variable workloads.


#### 7.18 AZURE_REDIS_CACHE — `dt.entity.azure_redis_cache`
Azure Cache for Redis — a managed in-memory caching service. Tracked for cache hits, memory usage, and latency.

Imported by Azure Redis feeds. Mapped to cache / Redis CI subclass when present in CI Class Models.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `calls` / `called_by` | Depends on::Used by ← SERVICE, AZURE_WEB_APP |

#### 7.19 AZURE_STORAGE_ACCOUNT — `dt.entity.azure_storage_account`
An Azure Storage Account — provides Blob, Queue, Table, and File storage services.

Imported by Azure Storage Account feeds. Mapped to **`cmdb_ci_cloud_storage_account`**.

| Dynatrace attribute | ServiceNow field |
| --- | --- |
| `displayName` | `name` |
| `entityId` | `sys_object_source.id` |


**ServiceNow relationships:**

| DT rel | cmdb_rel_ci |
| --- | --- |
| `calls` / client | Depends on::Used by: `client` → storage account |

#### 7.20 AZURE_EVENT_HUB_NAMESPACE — `dt.entity.azure_event_hub_namespace`
An Azure Event Hub Namespace — the management container for Event Hubs (Kafka-compatible streaming platform).


#### 7.21 AZURE_EVENT_HUB — `dt.entity.azure_event_hub`
An individual Azure Event Hub (a stream/topic) within an Event Hub Namespace.


#### 7.22 AZURE_SERVICE_BUS_NAMESPACE — `dt.entity.azure_service_bus_namespace`
An Azure Service Bus Namespace — the top-level container for queues and topics in Azure's enterprise messaging service.


#### 7.23 AZURE_SERVICE_BUS_QUEUE — `dt.entity.azure_service_bus_queue`
An individual Azure Service Bus Queue for point-to-point messaging.


#### 7.24 AZURE_SERVICE_BUS_TOPIC — `dt.entity.azure_service_bus_topic`
An Azure Service Bus Topic for publish/subscribe messaging patterns.


#### 7.25 AZURE_IOT_HUB — `dt.entity.azure_iot_hub`
Azure IoT Hub — a managed cloud gateway for bidirectional IoT device communication.


---

### 8. Cloud Foundry / BOSH Entities

Entities discovered when monitoring Pivotal/VMware Tanzu (Cloud Foundry) environments.

#### 8.1 CF_FOUNDATION — `dt.entity.cf_foundation`
A Cloud Foundry Foundation (PCF/TAS deployment). The top-level organizational unit for a Cloud Foundry environment.


#### 8.2 BOSH_DEPLOYMENT — `dt.entity.bosh_deployment`
A BOSH deployment — a set of VMs and jobs managed by the BOSH director within a Cloud Foundry foundation.


---

## Dynatrace relationships

Relationships in Dynatrace are **directed** — each has a "from" direction and an "opposite" (inverse) direction. In DQL, relationships are exposed as fields on entity records and queried with `fieldsAdd`.

Bidirectional relationships (marked ↔) have no meaningful "from/to" distinction.

---

### Smartscape topology chains

Compact reference for how entities connect in Dynatrace Smartscape (see entity sections for ServiceNow `cmdb_rel_ci` mappings).

```
APPLICATION
 └─calls─► SERVICE
            └─runs_on─► PROCESS_GROUP
                         └─runs_on─► HOST
            └─(PGI)──► PROCESS_GROUP_INSTANCE
                         └─runs_on─► HOST

KUBERNETES_CLUSTER
 └─contains─► KUBERNETES_NODE
 └─contains─► CLOUD_APPLICATION_NAMESPACE
               └─contains─► CLOUD_APPLICATION
                             └─instantiates─► CLOUD_APPLICATION_INSTANCE (Pod)
                                                ├─runs_on─► KUBERNETES_NODE
                                                ├─contains─► CONTAINER_GROUP_INSTANCE
                                                └─contains─► PROCESS_GROUP_INSTANCE

DOCKER HOST (Compose)
 HOST
 └─runs─► PROCESS_GROUP ──instance_of──► PROCESS_GROUP_INSTANCE
 cmdb_ci_docker_container ──Runs on──► HOST          (Discovery / SGC)
 SERVICE ──Depends on──► PROCESS_GROUP               (SGC Application Relationships)
```

> **SGC relationship import:** The **Application Relationships** scheduled feed maps Smartscape **`calls`**, **`runs_on`**, **`contains`**, **`balances`**, and related edges to **`cmdb_rel_ci`** rows (commonly **Depends on::Used by**, **Runs on::Runs**, **Contains::Contained by**, **Connects to::Connected by**). Exact relationship types depend on the RTE mapping in `sn_dynatrace_integ` and the target CMDB classes.



### 1. Call / Traffic Relationships

#### 1.1 calls — Inverse: `called_by`
Entity A makes outbound calls/requests to Entity B. Used between services, load balancers, Lambda functions, cloud-managed services, and process groups to model distributed request flow.

**SGC → ServiceNow:** **`calls`** / **`called_by`** → **`cmdb_rel_ci` Depends on::Used by** (caller depends on callee in Application Relationships import).

#### 1.2 called_by — Inverse: `calls`
Entity A is called by Entity B.

#### 1.3 receives_from — Inverse: `sends_to`
Entity A receives data/messages from Entity B. Used in messaging/queue contexts.

#### 1.4 sends_to — Inverse: `receives_from`
Entity A sends data/messages to Entity B.

#### 1.5 indirectly_receives_from — Inverse: `indirectly_sends_to`
Entity A indirectly receives data from Entity B (e.g., through a broker or intermediary).

#### 1.6 indirectly_sends_to — Inverse: `indirectly_receives_from`
Entity A indirectly sends data to Entity B.

---

### 2. Topology / Hierarchy Relationships

#### 2.1 belongs_to — Inverse: `contains`
Entity A is a member of or belongs to container Entity B. Examples: an EC2 instance belongs to an Availability Zone; a Pod belongs to a Namespace; a Process Group belongs to a Service.

**SGC → ServiceNow:** **`belongs_to`** / **`contains`** → **Contains::Contained by** (parent contains child).

#### 2.2 contains — Inverse: `belongs_to`
Entity A contains one or more of Entity B.

#### 2.3 consists_of — Inverse: `part_of`
Entity A is composed of Entity B components. Used for composite or aggregate entities.

#### 2.4 part_of — Inverse: `consists_of`
Entity A is a component part of Entity B.

#### 2.5 child_of — Inverse: `parent_of`
Entity A is a child of Entity B. Used in hierarchical entity trees (e.g., browser entity family/version hierarchy).

#### 2.6 parent_of — Inverse: `child_of`
Entity A is the parent of Entity B.

---

### 3. Hosting / Runtime Relationships

#### 3.1 runs_on — Inverse: `runs`
Entity A runs on / is hosted by Entity B. Core relationship in Smartscape: a Service runs on a Process Group, a Process Group runs on a Host, a Pod runs on a Kubernetes Node.

**SGC → ServiceNow:** **`runs_on`** / **`runs`** → **Runs on::Runs** (workload → host/node).

#### 3.2 runs — Inverse: `runs_on`
Entity A runs (hosts) Entity B.

#### 3.3 hosted_by — Inverse: `hosts`
Entity A is hosted by Entity B. Similar to `runs_on` but used for infrastructure-layer containment (e.g., a VM hosted by a hypervisor or cloud platform).

#### 3.4 hosts — Inverse: `hosted_by`
Entity A hosts Entity B.

---

### 4. Instance / Instantiation Relationships

#### 4.1 instance_of — Inverse: `instantiates`
Entity A is a running instance of a template/definition Entity B. Example: a Process Group Instance is an instance of a Process Group; a Cloud Application Instance (Pod) is an instance of a Cloud Application (Deployment).

**SGC → ServiceNow:** **`instance_of`** / **`instantiates`** → **Contains::Contained by** (template → instance) or instance **Runs on::Runs** to host.

#### 4.2 instantiates — Inverse: `instance_of`
Entity A is the definition/template that Entity B instantiates. Example: an Auto Scaling Group instantiates EC2 instances.

---

### 5. Load Balancing Relationships

#### 5.1 balances — Inverse: `balanced_by`
A load balancer entity distributes traffic across target entities. Example: an ALB balances EC2 instances; an Azure Application Gateway balances Azure VMs.

**SGC → ServiceNow:** **`balances`** / **`balanced_by`** → **Connects to::Connected by** or **Depends on::Used by** (load balancer → backend VM/service). Does not expand cloud-native frontend/backend pool CIs unless Azure/AWS Discovery also runs.

#### 5.2 balanced_by — Inverse: `balances`
Entity A (a compute resource) receives balanced traffic from Entity B (a load balancer).

---

### 6. Grouping Relationships

#### 6.1 group_of — Inverse: `groups`
Entity A is a group representation of Entity B. Example: a Process Group is the group-of a specific Application. Used to link grouping entities to their parent scope.

**SGC → ServiceNow:** **`group_of`** / **`groups`** → grouping link; often **Depends on::Used by** between SERVICE and PROCESS_GROUP.

#### 6.2 groups — Inverse: `group_of`
Entity A groups or aggregates Entity B.

#### 6.3 cluster_of — Inverse: `clustered_by`
Entity A (e.g., a Kubernetes Service) is the cluster-level representation/grouping of Entity B.

#### 6.4 clustered_by — Inverse: `cluster_of`
Entity A is clustered by / belongs to cluster Entity B. Example: a Cloud Application is clustered_by a Kubernetes Cluster.

---

### 7. Access / Credential Relationships

#### 7.1 can_access — Inverse: `accessible_by`
Entity A (typically a credentials entity) has access permissions to monitor Entity B. Example: AWS Credentials can_access EC2 instances, S3 buckets, RDS instances.

**SGC → ServiceNow:** credential scope edges; typically not traversed in service maps.

#### 7.2 accessible_by — Inverse: `can_access`
Entity A (a cloud resource) is accessible by Entity B (a credentials/account entity).

---

### 8. Management Relationships

#### 8.1 managed_by — Inverse: `manages`
Entity A is managed/orchestrated by Entity B. Used for infrastructure management hierarchies.

**SGC → ServiceNow:** **`managed_by`** / **`manages`** → **Managed by::Manages** when cloud org hierarchy is imported.

#### 8.2 manages — Inverse: `managed_by`
Entity A manages Entity B.

#### 8.3 monitored_by — Inverse: `monitors`
Entity A (e.g., an Application) is monitored by Entity B (e.g., a Synthetic Test or HTTP Check).

#### 8.4 monitors — Inverse: `monitored_by`
Entity A (e.g., a Synthetic Test) monitors Entity B (e.g., an Application).

---

### 9. Health Propagation Relationships

#### 9.1 affects — Inverse: `affected_by`
Entity A's health or performance problems affect Entity B. Used by Davis AI for root cause propagation — a degraded Host can affect a Service.

**SGC → ServiceNow:** Davis propagation edges; used for problem RCA in Dynatrace — **not** always imported as persistent `cmdb_rel_ci` rows.

#### 9.2 affected_by — Inverse: `affects`
Entity A is affected by problems originating in Entity B.

#### 9.3 propagates_to — Inverse: `propagated_from`
An impact or problem propagates from Entity A to Entity B downstream in the topology.

#### 9.4 propagated_from — Inverse: `propagates_to`
Entity A received a propagated impact from Entity B.

---

### 10. Service / Consumer Relationships

#### 10.1 serves — Inverse: `served_by`
Entity A serves requests to Entity B (e.g., a Service serves an Application).

**SGC → ServiceNow:** **`serves`** / **`served_by`** → **Depends on::Used by** (`cmdb_ci_service_calculated` → `cmdb_ci_service_auto`).

#### 10.2 served_by — Inverse: `serves`
Entity A is served by Entity B.

---

### 11. Bidirectional Relationships

#### 11.1 related_to ↔
A generic bidirectional association between two entities that share a meaningful operational relationship not captured by a more specific relationship type.

**SGC → ServiceNow:** **`same_as`** supports IRE deduplication (HOST ↔ EC2/AZURE_VM); may not create a visible relationship row after merge.

#### 11.2 same_as ↔
Entity A and Entity B represent the same real-world resource as discovered from different data sources (e.g., an EC2 instance discovered by both OneAgent and the AWS API). Used for deduplication and identity stitching.

---

### 12. Tag-based relationships (`cmdb_key_value`)

Smartscape relationship types (sections 1–11) are directed edges on Dynatrace entities. **Tag-based relationships** use **`cmdb_key_value`** on CMDB CIs:

| Mechanism | Storage |
| --- | --- |
| Workload label | `cmdb_key_value` on workload CI |
| Dynatrace tag copy (SGC) | `cmdb_key_value` on SGC-imported CI |
| Application Service filter | `cmdb_ci_service_discovered.tag_list` |

1. Tag-based Service Mapping creates **`cmdb_rel_ci` Contains::Contained by**: parent **`cmdb_ci_service_discovered`**, child workload CI (`cmdb_ci_docker_container`, `cmdb_ci_kubernetes_pod`, or `cmdb_ci_linux_server`).
2. The Application Service **`tag_list`** defines which keys/values the mapping job matches; it is not stored in **`cmdb_key_value`**.
3. Canonical key and value-field mapping: see **Tag-based relationships (`cmdb_key_value`)** under [Dynatrace entities](#dynatrace-entities).

