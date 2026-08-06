---
title: ServiceNow Tag Ingestion — Native Paths, Gaps, and Workarounds
---

# ServiceNow Tag Ingestion — Native Paths, Gaps, and Workarounds

## Purpose

This document explains **why** this repository includes Ansible playbooks that read runtime environments (Docker, Kubernetes) and write **`cmdb_key_value`** rows, even though ServiceNow’s stated model is for **Discovery and KVA to ingest tags from runtime**. It complements [DT_SN_Specification_Guide.md](DT_SN_Specification_Guide.md) (how to model) and [Tag_Based_Service_Mapping.md](Tag_Based_Service_Mapping.md) (instance UI configuration).

---

## ServiceNow’s stated strategy

Tag-based Service Mapping follows a three-step model:

1. **Label at deploy time** — Compose, Kubernetes manifests, cloud tags, etc.
2. **Discovery ingests labels** — Horizontal Discovery, KVA Informer, cloud patterns, or Kubernetes discovery patterns read labels from the environment and store them on CMDB CIs in **`cmdb_key_value`** (Key Values).
3. **Service Mapping reads CMDB only** — Tag Categories and application service filters match CIs by key/value pairs; maps are built from CMDB relationships and tags, not by re-querying runtime at map time.

Official ServiceNow guidance emphasizes:

- Tags are discovered from **cloud providers and container ecosystems** into CMDB.
- Tag-based mapping **does not require elevated credentials on workloads** (unlike vertical/top-down Service Mapping).
- For Kubernetes, the **Kubernetes Visibility Agent (KVA) Informer** is the recommended near-real-time path: it watches the API server and populates pod/service CIs and label rows.
- Organizations **should standardize labels before deployment** (for example `app.kubernetes.io/*`, environment, application name) and use **Tag Categories** in the Service Mapping Workspace to normalize inconsistent keys.
- **`servicenow.com/service-instance`** is the correlation key between discovered CIs and CSDM service instances; its value is the service instance **display name**.

**Intended division of labor:**

| Role | Responsibility |
|------|----------------|
| **Platform / DevOps** | Author runtime labels on workloads (Compose, K8s, cloud). |
| **Discovery operator** | Run KVA, Docker Pattern, cloud discovery so CIs and `cmdb_key_value` exist. |
| **CSDM modeler** | Declare BA/BS/service-instance hierarchy and **display names** in `*.csdm.yaml`. |
| **Service Mapping operator** | Configure Tag Categories and tag filters on the instance. |

External orchestration that scrapes runtime and REST-writes CMDB is **not** ServiceNow’s documented happy path. See [Single source of truth](#single-source-of-truth-principle) in the specification guide for where runtime labels must be authored.

---

## What ServiceNow actually does in this lab

### Kubernetes — KVA reads pod labels

Phase 2 installs the **KVA Informer** ([install.md](install.md) §5). KVA watches the cluster and writes Kubernetes CIs plus label key/value rows to **`cmdb_key_value`** as internal user **`system`**.

KVA reliably provides:

- Native Kubernetes labels on pods (for example `app.kubernetes.io/name`, `app.kubernetes.io/component`).
- Pod, deployment, and service CI inventory and cluster relationships.

KVA does **not** automatically provide everything this project needs:

| Gap | Consequence |
|-----|-------------|
| **`servicenow.com/service-instance` canonical key** | KVA copies labels that exist on pods; it does not invent CSDM correlation keys. Workloads without `servicenow.com/service-instance` on the pod will not bind to service instances by canonical key. |
| **Spec vs runtime drift** | Manifests in Git may declare labels that are not yet on running pods until redeploy. |
| **Integration user ACLs** | KVA writes as `system`. The automation user (`admin_brooks_lab`) required separate **`cmdb_key_value`** table ACL changes to upsert rows via REST ([install.md](install.md) §6.3). |

### Docker — two different mechanisms

| Mechanism | What ServiceNow / MID does | What it puts in `cmdb_key_value` |
|-----------|---------------------------|----------------------------------|
| **Docker Pattern** (horizontal Discovery) | Discovers containers, processes, relationships for vertical Service Mapping | **Not** custom `servicenow.com/*` Compose labels ([CSDM_Specifications.md](CSDM_Specifications.md) Statement 4.4) |
| **`discovery/docker/discover.yml`** (this repo) | `docker ps` + `docker inspect` on the host | **All** container labels, including `servicenow.com/*` and `com.docker.compose.*` |

Docker Pattern enriches the container/process graph; it does **not** populate Compose **`servicenow.com/*`** rows that tag-based Service Mapping rules expect in this lab.

---

## Repository playbooks and direction of flow

| Playbook | Runtime contact | Direction | Role |
|----------|-----------------|-----------|------|
| **`k8s/sync_pod_labels.yml`** | `kubectl get pods -o json` (read labels) | Runtime → SN `cmdb_key_value` | Mirror `servicenow.com/*` when KVA lag or labels present on pods |
| **`docker/discover.yml`** | `docker ps`, `docker inspect` | Runtime → SN `cmdb_key_value` (+ container CI upsert) | Fills Docker Pattern gap for Compose labels |
| **`host/sync_tags.yml`** | None | CSDM spec → SN `cmdb_key_value` on `linux_server` | Host agents without container/pod label surface |
| **`k8s/discover.yml`** | `kubectl rollout restart` KVA | SN-side informer only | Not app pod labels |
| **`csdm/deploy.yml`** | None | CSDM spec → SN CMDB hierarchy | Business model, not runtime tags |
| **`compare.yml`** | SN + Dynatrace APIs (read) | Export / drift report | No runtime writes |

**None of these playbooks inject tags into running containers or pods.** They either read runtime and write CMDB, or push model intent into CMDB.

The Kubernetes tag pipeline is a **runtime mirror** (`sync_pod_labels.yml`) — it duplicates what KVA would do if pods carry the `servicenow.com/service-instance` label, covering KVA lag.

---

## Is external runtime reach an anti-pattern?

**As the primary architecture: yes** — ServiceNow’s documentation aligns with keeping runtime ingestion inside Discovery/KVA.

External Ansible that inspects Docker or Kubernetes and REST-writes **`cmdb_key_value`** is a **workaround** when:

- Native discovery does not copy the keys you standardized on (`servicenow.com/*`).
- GitOps CSDM deploy and tag binding must proceed before native ingestion catches up.
- Instance ACLs block the integration user from the same writes KVA makes as `system`.
- Custom **container inventory sync** (`container_discovery: true`) runs separately from MID Docker Pattern.

### Target end state (recommended)

1. **Runtime labels correct** on all workloads (Compose, K8s manifests deployed).
2. **KVA + Docker Pattern** as the only runtime readers into CMDB.
3. **Ansible limited to CSDM deploy** (BA/BS/service instances) and **compare** — not tag scraping or CMDB tag injection.

---

## ServiceNow best practices for tags

1. **Define a tagging standard early** — consistent keys across environments (Application, Environment, Location, Owner). For Kubernetes, prefer **`app.kubernetes.io/*`** recommended labels.
2. **Use `servicenow.com/service-instance` for Service Mapping correlation** — its value matching the CSDM service instance display name (`name:`; K8s-sanitized for `platform: kubernetes`).
3. **Apply tags at deploy time** — Compose `labels:`, pod templates, cloud tag policies; avoid manual CMDB tag entry.
4. **Run native discovery** — KVA for Kubernetes; cloud discovery for AWS/Azure/GCP; Docker Pattern where container/process graph is required.
5. **Configure Tag Categories** in Service Mapping Workspace — normalize `app`, `app.kubernetes.io/name`, etc.
6. **Verify `cmdb_key_value`** before expecting maps — `cmdb_key_value.list`, filter by key.
7. **Separate concerns** — CSDM hierarchy (business model) vs tags (workload → application service binding) vs traversal rules (map topology).
8. **One canonical key per CI** — do not assign multiple `servicenow.com/service-instance` values on the same CI (for example Elastic Agent and OneAgent both on one `linux_server`); use the correct CI class (pod vs host).

---

## Why ServiceNow does not “just read designated pod labels” here

ServiceNow **does** read labels that exist on objects and that the ingestion path supports:

- **KVA** → Kubernetes labels → `cmdb_key_value` on pod CIs.
- **Kubernetes discovery patterns** (MID-based) → similar label population.
- **Cloud discovery** → provider tags.

It does **not** automatically:

- Guarantee **`servicenow.com/service-instance`** without that label on the workload.
- Copy Compose **`servicenow.com/*`** via **Docker Pattern alone** in this lab.
- Replace **CSDM deploy** (Business Applications are model declarations, not discovered).
- Ingest tags into **Dynatrace** (OneAgent/Operator and cloud integrations are separate).

---

## Related documents

| Document | Role |
|----------|------|
| [DT_SN_Specification_Guide.md](DT_SN_Specification_Guide.md) | Primary modeling guide; single source of truth for runtime tags |
| [CSDM_Specifications.md](CSDM_Specifications.md) | Normative schema; Statements 4.4–4.5 on discovery vs Ansible |
| [Tag_Based_Service_Mapping.md](Tag_Based_Service_Mapping.md) | Instance UI and playbook prerequisites |
| [install.md](install.md) | KVA, Docker Pattern, `cmdb_key_value` ACLs |
