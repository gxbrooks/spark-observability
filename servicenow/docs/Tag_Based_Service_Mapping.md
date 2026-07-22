# Tag-Based Service Mapping — Brooks Lab

This guide explains **where and how** to configure tag-based Service Mapping on the ServiceNow instance for application services declared in `csdm.yaml` with `service_mapping: tags`.

Tag-based mapping matches discovered workload CIs to application services using **`cmdb_key_value`** rows (label key → value on each CI). The deploy processor creates the CSDM hierarchy; **Service Mapping rules on the instance** populate maps from tags.

## Prerequisites (automation in this repo)

| Step | Playbook | Purpose |
|------|----------|---------|
| 1 | `csdm/deploy.yml` | Create BA / BS / application service CIs |
| 2 | `discovery/docker/discover.yml` | Sync containers; upsert `servicenow.io/*` on container CIs |
| 3 | **Docker Pattern** horizontal discovery on Lab3 (`discovery/discover.yml`) | Enriches container/process relationships (vertical SM) |
| 4 | KVA + `discovery/k8s/sync_pod_labels.yml` | K8s pod CIs; KVA writes `app.kubernetes.io/*`; pod sync writes `servicenow.io/*` |
| 5 | `discovery/host/sync_tags.yml` | Host agents — `servicenow.io/*` on `cmdb_ci_linux_server` |
| 6 | **Instance UI** (below) | Tag Categories + tag filter on each application service |

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
cmdb_key_value.list  →  key=servicenow.io/application-service-identifier
```

Each observability Docker container should have a row whose **value** matches the application service **`identifier`** in `csdm.yaml` (for example `grafana`, `elasticsearch`).

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

Create (or extend OOTB) categories that match labels this lab uses:

| Tag Category (display name) | Label keys to include | Used for |
|----------------------------|------------------------|----------|
| **Application Service** | `servicenow.io/application-service-identifier` | Primary map key — matches `identifier` in `csdm.yaml` |
| **Business Service** | `servicenow.io/business-service-identifier` | Optional filter / grouping |
| **Business Application** | `servicenow.io/application-identifier` | Optional filter / grouping |
| **Environment** | `servicenow.io/environment` | Scope (for example `on-prem`) |
| **Location** | `servicenow.io/location` | Scope (for example `brooks-lab`) |

For Kubernetes-only services, also map **`app.kubernetes.io/name`**, **`app.kubernetes.io/component`**, and **`app.kubernetes.io/part-of`** if you use family-based candidates instead of per-service filters.

## Which application services need tag-based mapping

### Observability Docker Compose (`servicenow/regions/brooks-lab/observability-platform.csdm.yaml`)

All seven use `service_mapping: tags`. Each **`identifier`** must match **`servicenow.io/application-service-identifier`** on the container. See [DT_SN_Specification_Guide.md](DT_SN_Specification_Guide.md) for compose label examples.

| Application Service | identifier (tag value) | Compose service |
|--------------------|------------------------|-----------------|
| Elasticsearch | `elasticsearch` | `es01` |
| Kibana | `kibana` | `kibana` |
| Grafana | `grafana` | `grafana` |
| Prometheus | `prometheus` | `prometheus` |
| Grafana Tempo | `grafana-tempo` | `tempo` |
| OpenTelemetry Collector | `opentelemetry-collector` | `otel-collector` |
| Logstash | `logstash` | `logstash01` |

### Spark Kubernetes (`servicenow/regions/brooks-lab/spark.csdm.yaml`)

| Application Service | identifier | Runtime labels |
|--------------------|------------|----------------|
| Spark Master | `spark-master` | `servicenow.io/*` on pod + `app.kubernetes.io/*` (KVA) |
| Spark History Server | `spark-history-server` | … |
| Spark Worker | `spark-worker` | same identifier on every worker pod (all nodes) |

Sync canonical tags: `discovery/k8s/sync_pod_labels.yml` (included in `discovery/k8s/discover.yml`).

### Host agents (tag-based, per node)

| Spec file | Application Service pattern | Tag target CI |
|-----------|----------------------------|---------------|
| `elastic-agent.csdm.yaml` | `elastic-agent-lab1` … | `cmdb_ci_linux_server` |

Run `discovery/host/sync_tags.yml` after CSDM deploy.

### Kubernetes agent pods (tag-based, per node)

| Spec file | Application Service pattern | Tag target CI |
|-----------|----------------------------|---------------|
| `dynatrace-monitoring.csdm.yaml` | `dynatrace-oneagent-lab1` … | `cmdb_ci_kubernetes_pod` (Dynakube OneAgent pod) |

Run `discovery/k8s/sync_csdm_tags.yml`. Do **not** tag both Elastic Agent and OneAgent on the same `linux_server` CI — they share one canonical `application-service-identifier` key per CI.

### Excluded from tag-based SM

| Application Service | Reason |
|--------------------|--------|
| **Dynatrace Tenant** | `service_mapping: manual` (SaaS) |
| Synthetic / test CIs | `csdm/test/*` |

## How to attach tags to an existing CSDM application service

We pre-create **`cmdb_ci_service_discovered`** records via `csdm/deploy.yml`. Do **not** create duplicate services from Service Candidates unless you retire the CSDM-created CI first.

Recommended path for **existing** application services:

1. Open **Configuration** → **Application Services** (or `cmdb_ci_service_discovered.list`).
2. Open the application service (for example **Grafana**).
3. Use **Service Mapping** related links / **Manage Service Map** (wording varies by version).
4. Add population method **Tags** (or run **Convert to tag-based service** wizard if offered — **irreversible**; prefer adding tag filter without class conversion when possible).
5. Define tag filter: **`servicenow.io/application-service-identifier`** = **`grafana`** (the service `identifier` from `csdm.yaml`).
6. Optionally add **`servicenow.io/environment`** = `on-prem` and **`servicenow.io/location`** = `brooks-lab` to avoid cross-environment matches.
7. Save and run **Update map** / wait for the tag-based scheduled job.
8. Confirm **Contains** children include the Docker container CI (or K8s pod/deployment).

Alternative (family-based, net-new services): define a **Tag-Based Service Family** using Application Service + Environment categories, review **Service Candidates**, and create maps — only when not using CSDM-precreated application services.

## Traversal rules

Default **`svc_traversal_rules`** on the instance control parent/child edges in tag-based maps (for example Docker container → Linux Server). Review in **Service Mapping** → **Traversal Rules** if maps appear flat.

## Automation reference

```bash
cd ansible

# Repopulate containers + cmdb_key_value labels + retire stale container CIs
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/discover.yml \
  -e @../vars/secrets.yaml

# Kubernetes pod servicenow.io labels (after KVA sync)
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/sync_pod_labels.yml \
  -e @../vars/secrets.yaml

# Host agent servicenow.io labels on linux_server CIs
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
