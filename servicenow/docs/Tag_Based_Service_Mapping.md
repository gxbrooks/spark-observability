# Tag-Based Service Mapping — Brooks Lab

This guide explains **where and how** tag-based Service Mapping is configured on the ServiceNow instance for service instances declared in `csdm.yaml` with `service_mapping: tags`.

Tag-based mapping matches discovered workload CIs to service instances using **`cmdb_key_value`** rows (label key → value on each CI). The deploy processor creates the CSDM hierarchy and configures the tag population rule on each service; the Service Populator adds matching CIs as members in **`svc_ci_assoc`**.

## Prerequisites (automation in this repo)

| Step | Playbook | Purpose |
|------|----------|---------|
| 1 | `csdm/deploy.yml` | Create BA / BS / service instance CIs; configure tag population rules |
| 2 | `discovery/docker/discover.yml` | Sync containers; upsert `servicenow.com/*` on container CIs |
| 3 | **Docker Pattern** horizontal discovery on Lab3 (`discovery/discover.yml`) | Enriches container/process relationships (vertical SM) |
| 4 | KVA + `discovery/k8s/sync_pod_labels.yml` | K8s pod CIs; KVA copies pod labels (including `servicenow.com/service-instance`); pod sync mirrors `servicenow.com/*` |
| 5 | `discovery/host/sync_tags.yml` | Host agents — `servicenow.com/*` on `cmdb_ci_linux_server` |
| 6 | **Instance UI** (below) | Verify the Tag Category + tag population rule on each service instance |

### cmdb_key_value and table ACLs

**`cmdb_key_value`** (list label: **Key Values**) is a **CMDB table**, not a role. Tag-based Service Mapping reads label key/value pairs from this table. KVA and Discovery write rows as the internal user **`system`**, which bypasses REST table ACLs that block the automation account.

On **optimizincdemo1**, **`admin_brooks_lab`** already has **`cmdb_inst_admin`**, **`sn_cmdb_admin`**, **`ecmdb_admin`**, **`discovery_admin`**, and related CMDB roles — but REST **POST** to **`cmdb_key_value`** still returns:

```text
ACL Exception Insert Failed due to security constraints
```

So **`cmdb_inst_admin` does not grant insert on `cmdb_key_value`** on this instance. **`discovery/docker/discover.yml`** can read and upsert labels only after a **table ACL** change (or an elevated import path).

#### How to fix (instance admin with security_admin)

Follow **`docs/install.md` [§6.3 — Enable automation to update key-value pairs](../docs/install.md#63-enable-automation-to-update-key-value-pairs)** (rationale, ACL steps, verification, and re-run commands).

Requires **`security_admin`** elevation to create or edit ACL rules.

#### Other options

- **Import Set / Transform** into **`cmdb_key_value`** (if your process allows batch load).
- **Scripted REST** endpoint that inserts rows under an elevated application scope (more work; use only if ACL change is not acceptable).
- **Manual** entry via **`cmdb_key_value.list`** (not scalable).

Until label rows exist, configure tag-based Service Mapping rules in the UI but Docker application services will not bind to container CIs.

Verify labels in CMDB:

```text
cmdb_key_value.list  →  key=servicenow.com/service-instance
```

Each observability Docker container should have a row whose **value** matches the service instance **display name** (the `name:` attribute) in `csdm.yaml` (for example `Grafana`, `Elasticsearch`).

## Where to configure tag-based rules (ServiceNow UI)

Navigation (Zurich / Service Mapping Workspace):

1. **All** → **Service Mapping** → **Service Mapping Workspace**
2. Left nav: **Tag-Based Mapping**
   - **Tag Categories** — normalize label keys
   - **Tag-Based Service Families** — group categories into service definitions
   - **Service Candidates** — auto-generated combinations (optional path for net-new services)

Direct list URLs (replace instance host):

- Tag Categories: `https://<instance>/now/svc-map/tag-categories`
- Tag-Based Service Families: `https://<instance>/now/svc-map/tag-based-service-families`
- Service Candidates: `https://<instance>/now/svc-map/service-candidates`

Required role: **`service_mapping_admin`** on Zurich ( **`sm_admin`** is often absent). Classic UI: Filter Navigator → **CI tag categories** (`svc_tag_categories_list.do`). Workspace `/now/svc-map/tag-categories` requires full **`sn_itom_map_app`** Store entitlement.

## Tag Categories to create

One category covers all workloads in this lab (created automatically by `ansible/playbooks/servicenow/service-mapping/common/ensure_tag_categories.yml`; key variable `sn_csdm_tag_key_service_instance` in `service-mapping/common/vars.yml`):

| Tag Category (display name) | Label key to include | Used for |
|----------------------------|------------------------|----------|
| **Service Instance** | `servicenow.com/service-instance` | Primary map key — value is the service instance **display name** (`name:` in `csdm.yaml`; K8s-sanitized for `platform: kubernetes`) |

For Kubernetes-only services, also map **`app.kubernetes.io/name`**, **`app.kubernetes.io/component`**, and **`app.kubernetes.io/part-of`** if you use family-based candidates instead of per-service filters.

## Which service instances need tag-based mapping

### Observability Docker Compose (`servicenow/regions/brooks-lab/observability-platform.csdm.yaml`)

All seven use `service_mapping: tags`. The **`servicenow.com/service-instance`** label value must match the service instance **display name**. See [DT_SN_Specification_Guide.md](DT_SN_Specification_Guide.md) for compose label examples.

| Service Instance | Display name (tag value) | Compose service |
|--------------------|------------------------|-----------------|
| Elasticsearch | `Elasticsearch` | `es01` |
| Kibana | `Kibana` | `kibana` |
| Grafana | `Grafana` | `grafana` |
| Prometheus | `Prometheus` | `prometheus` |
| Grafana Tempo | `Grafana Tempo` | `tempo` |
| OpenTelemetry Collector | `OpenTelemetry Collector` | `otel-collector` |
| Logstash | `Logstash` | `logstash01` |

### Spark Kubernetes (`servicenow/regions/brooks-lab/spark.csdm.yaml`)

Values are the display names sanitized to the Kubernetes label charset (illegal characters collapse to `-`).

| Service Instance | Tag value (K8s-sanitized) | Runtime labels |
|--------------------|------------|----------------|
| Spark Master | `Spark-Master` | `servicenow.com/service-instance` on pod + `app.kubernetes.io/*` (KVA) |
| Spark History Server | `Spark-History-Server` | … |
| Spark Worker | `Spark-Worker` | same value on every worker pod (all nodes) |

Sync canonical tags: `discovery/k8s/sync_pod_labels.yml` (included in `discovery/k8s/discover.yml`).

### Host agents (tag-based, per node)

| Spec file | Service Instance pattern | Tag target CI |
|-----------|----------------------------|---------------|
| `elastic-agent.csdm.yaml` | `Elastic Agent (Lab1)` … | `cmdb_ci_linux_server` |

Run `discovery/host/sync_tags.yml` after CSDM deploy.

### Kubernetes agent pods (tag-based, per node)

| Spec file | Service Instance pattern | Tag target CI |
|-----------|----------------------------|---------------|
| `dynatrace-monitoring.csdm.yaml` | `Dynatrace OneAgent (Lab1)` … (K8s-sanitized on the pod, e.g. `Dynatrace-OneAgent-Lab1`) | `cmdb_ci_kubernetes_pod` (Dynakube OneAgent pod) |

Run `discovery/k8s/label_oneagent_pods.yml`. Do **not** tag both Elastic Agent and OneAgent on the same `linux_server` CI — they share one canonical `servicenow.com/service-instance` key per CI.

### Excluded from tag-based SM

| Service Instance | Reason |
|--------------------|--------|
| **Dynatrace Tenant** | `service_mapping: manual` (SaaS) |
| Synthetic / test CIs | `csdm/test/*` |

## How to attach tags to an existing CSDM service instance

We pre-create service instance records via `csdm/deploy.yml`; services with `service_mapping: tags` are reclassed to **`cmdb_ci_service_by_tags`**, and the deploy configures the tag population rule automatically (`configure_tag_based_sm.yml` → `/populate_tags` Scripted REST API, which calls `SMServiceByTagsUtils.updateServiceFromTagsList()` and triggers `SNC.ServicePopulatorRunner('INTERACTIVE')`). Do **not** create duplicate services from Service Candidates unless you retire the CSDM-created CI first.

Manual UI path (verification / troubleshooting only — the deploy automates this):

1. Open **Configuration** → **Application Services** (or `cmdb_ci_service_by_tags.list`).
2. Open the service instance (for example **Grafana**).
3. Use **Service Mapping** related links / **Manage Service Map** (wording varies by version).
4. Add population method **Tags** (or run **Convert to tag-based service** wizard if offered — **irreversible**; prefer adding tag filter without class conversion when possible).
5. Define tag filter: **`servicenow.com/service-instance`** = **`Grafana`** (the service instance display name from `csdm.yaml`; K8s-sanitized for `platform: kubernetes`, e.g. `Spark-Worker`).
6. Save and run **Update map** / wait for the tag-based scheduled job.
7. Confirm the Docker container CI (or K8s pod/deployment) appears as a member in **`svc_ci_assoc`**.

Alternative (family-based, net-new services): define a **Tag-Based Service Family** using the Service Instance category, review **Service Candidates**, and create maps — only when not using CSDM-precreated service instances.

## Traversal rules

Default **`svc_traversal_rules`** on the instance control parent/child edges in tag-based maps (for example Docker container → Linux Server). Review in **Service Mapping** → **Traversal Rules** if maps appear flat.

## Automation reference

```bash
cd ansible

# Repopulate containers + cmdb_key_value labels + retire stale container CIs
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/discover.yml \
  -e @../vars/secrets.yaml

# Kubernetes pod servicenow.com labels (after KVA sync)
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/sync_pod_labels.yml \
  -e @../vars/secrets.yaml

# Host agent servicenow.com labels on linux_server CIs
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/host/sync_tags.yml \
  -e @../vars/secrets.yaml

# Diagnose
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/diagnose.yml \
  -e @../vars/secrets.yaml
```

## Related documents

- [DT_SN_Specification_Guide.md](DT_SN_Specification_Guide.md) — **primary modeling guide** (CSDM + runtime labels + Dynatrace alignment)
- [CSDM_Specifications.md](CSDM_Specifications.md) — normative `service_mapping: tags` rules
- [ServiceNow Quick Start Guide for Service Mapping](https://www.servicenow.com/community/itom-articles/quick-start-guide-for-service-mapping/ta-p/3521583)
