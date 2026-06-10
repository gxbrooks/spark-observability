# ServiceNow Discovery — installation guide (Phase 1)

This document covers **prerequisites** on the ServiceNow instance and lab hosts,
then the Ansible install sequence for brooks-lab Discovery.

**Instance:** https://optimizincdemo1.service-now.com/  
**Playbooks:** `ansible/playbooks/servicenow/discovery/`  
**Variables:** `vars/variables.yaml` → **`service-now`** context → generated
`vars/contexts/servicenow_ansible_vars.yml`  
**Secrets:** `vars/secrets.yaml` → `servicenow:` block (see `vars/secrets.example.yaml`)

---

## Prerequisites overview

Phase 1 needs **three separate identities**. They must not be combined into one
ServiceNow user.

| Identity | Where it lives | Purpose |
| -------- | -------------- | ------- |
| **admin_brooks_lab** | ServiceNow (`SN_USER`) | Ansible REST automation — locations, credentials, schedules |
| **mid_brooks_lab** | ServiceNow (`SN_MID_USER`) | MID Server agent authentication only |
| **sn-discovery** | Linux on Lab1–Lab3 | SSH target for Discovery classification probes |

---

## 1. ServiceNow user: `admin_brooks_lab`

Used by Ansible `deploy.yml`, `discover.yml`, `diagnose.yml`, and `test.yml`.
Mapped to `servicenow.SN_USER` in `vars/secrets.yaml`.

### User record

| Field | Value |
| ----- | ----- |
| **User ID** | `admin_brooks_lab` |
| **Identity type** | Machine |
| **Web service access** | Enabled (required for REST Table API / Basic Auth) |
| **Interactive login** | Not required |

### Required roles (minimum effective set)

Grant enough rights to **read and write** Discovery configuration tables and
CMDB locations. On optimizincdemo1 the following roles are effective:

| Role | Why |
| ---- | --- |
| **discovery_admin** | Discovery schedules, ranges, credentials, run scans *(or equivalent ACLs via elevated CMDB/admin roles)* |
| **cmdb_inst_admin** | Create/update `cmn_location` (**brooks-lab**) |
| **rest_service** | REST API access |
| **snc_platform_rest_api_access** | Table API authentication |
| **cmdb_query_builder** or **cmdb_read** | `test.yml` CMDB validation |

Additional roles on the demo instance (ITSM workspace, import, etc.) are fine
but not required for Phase 1.

### Must not use this user for

- MID Server `config.xml` authentication (`mid.instance.username`) — use
  `mid_brooks_lab` instead.

### Secrets mapping

```yaml
servicenow:
  SN_USER: "admin_brooks_lab"
  SN_PASSWORD: "<machine-user password>"
```

---

## 2. ServiceNow user: `mid_brooks_lab`

Used **only** by the MID Server agent on Lab3 to poll the instance and execute
Discovery jobs from the ECC queue. Mapped to `servicenow.SN_MID_USER` /
`SN_MID_PASSWORD` in `vars/secrets.yaml`.

### User record

| Field | Value |
| ----- | ----- |
| **User ID** | `mid_brooks_lab` |
| **Identity type** | Machine |
| **Web service access** | Enabled |
| **Interactive login** | Not required |

### Required roles

| Role | Required |
| ---- | -------- |
| **mid_server** | **Yes — only role needed** |

Do **not** grant `discovery_admin`, `admin`, or `itil` to this user unless
ServiceNow support documents a specific exception. Least privilege is
`mid_server` alone.

### Password and `config.xml`

The User ID and password must match `mid.instance.username` and
`mid.instance.password` in the MID `config.xml` on Lab3 (rendered by
`discovery/install.yml`).

If the password contains **`&`**, `<`, `>`, or quotes, the install template
XML-escapes it automatically. Prefer passwords without `&` when rotating, to
avoid encoding mistakes in manual edits.

### What the MID user cannot do (verified)

`mid_brooks_lab` with **`mid_server` only** is **not sufficient to complete
Phase 1 by itself**:

| Action | MID user | admin_brooks_lab |
| ------ | -------- | ---------------- |
| Authenticate MID agent / ECC queue | Yes | N/A |
| Read `ecc_agent` (MID registration) | Yes | Yes |
| Create `cmn_location` (brooks-lab) | **No** | Yes |
| Create `discovery_credentials` | **No** | Yes |
| Create `discovery_schedule` / ranges | **No** | Yes |
| Run `deploy.yml` / `discover.yml` | **No** | Yes |

**Conclusion:** Phase 1 requires **both** users — `admin_brooks_lab` for
Ansible instance configuration and `mid_brooks_lab` for the MID Server process.

### Secrets mapping

```yaml
servicenow:
  SN_MID_USER: "mid_brooks_lab"
  SN_MID_PASSWORD: "<machine-user password>"
```

---

## 3. Linux user: `sn-discovery` (lab hosts)

Not a ServiceNow account. Created on **Lab1, Lab2, and Lab3** by
`discovery/install.yml`.

| Field | Value |
| ----- | ----- |
| **Username** | `sn-discovery` (override: `SN_DISCOVERY_USER` in `variables.yaml`) |
| **Auth** | SSH public key (generated on controller) |
| **Sudo** | Limited NOPASSWD for Discovery classification commands |
| **Purpose** | Target credential for SSH-based Linux CI Discovery on lab servers |

Private key path (gitignored): `vars/sn_discovery_id_ed25519`  
Uploaded to ServiceNow as credential **`brooks-lab-ssh`** by `deploy.yml`.

---

## 4. Instance and lab prerequisites

### ServiceNow instance

- [ ] ITOM **Discovery** and **CMDB** licensed/active on the instance
- [ ] `admin_brooks_lab` and `mid_brooks_lab` created with roles above
- [ ] `SN_URL` set in `vars/variables.yaml` (service-now context; not a secret)
- [ ] `vars/secrets.yaml` populated (both users, passwords)
- [ ] Copy `vars/secrets.example.yaml` field names if migrating from older `lab_admin` naming

### Lab hosts

- [ ] Lab1, Lab2, Lab3 powered on and reachable via Ansible inventory
- [ ] Lab3 outbound HTTPS (443) to `optimizincdemo1.service-now.com`
- [ ] Lab3 can reach `192.168.1.0/24` for Discovery scans
- [ ] ~4–6 GiB RAM headroom on Lab3 for MID JVM (see `docs/architecture-and-resources.md`)

### MID Server package

- [ ] `SN_MID_INSTALLER_DEB_URL` in `vars/variables.yaml` (service-now context)
  points at the Linux `.deb` that matches the **instance build**.

**Current value (optimizincdemo1, Zurich build
`glide-zurich-07-01-2025__patch7b-hotfix1-05-18-2026_05-19-2026_0833`):**

```
https://install.service-now.com/glide/distribution/builds/package/app-signed/mid-linux-installer/2026/05/19/mid-linux-installer.zurich-07-01-2025__patch7b-hotfix1-05-18-2026_05-19-2026_0833.linux.x86-64.deb
```

**How to find the URL when the instance is upgraded:**

1. In ServiceNow: **MID Server > Downloads** (or **All > MID Server > Downloads**).
2. Select the Linux installer for your instance version.
3. Copy the signed `.deb` URL, or read `glide.war` from the instance and match
   the build string in the filename.
4. Update `SN_MID_INSTALLER_DEB_URL` in `variables.yaml` and re-run
   `discovery/install.yml --tags mid_server`.

The MID installer build **must** match the instance; a mismatch prevents the MID
from registering or causes ECC queue failures.

### brooks-lab Discovery scope (configured by `deploy.yml`)

| Object | Name / value |
| ------ | ------------- |
| Location | `brooks-lab` (`cmn_location`) |
| IP range | `192.168.1.0/24` |
| SSH credential | `brooks-lab-ssh` → `sn-discovery` |
| Schedule | `Brooks Lab CI Discovery` |
| MID Server name | `mid-brooks-lab3` (Lab3) |

Only Lab1–Lab3 have SSH credentials; other addresses on the subnet may appear
as network or unclassified devices.

---

## 5. Kubernetes prerequisites (Phase 2 — KVA Informer)

Phase 2 discovers the brooks-lab Kubernetes cluster into CMDB via the **Kubernetes
Visibility Agent (KVA) Informer** only. Cluster identity is shared with Dynatrace
so CMDB and observability stay aligned on one **K8-native cluster name**.

### Variable model (`vars/variables.yaml`)

All Kubernetes cluster definitions live in the **Kubernetes** section of
`variables.yaml`. Use **K8-prefixed** names (not `SN_` or `DT_`) for constructs
that exist in the cluster itself.

| Variable | Purpose |
| -------- | ------- |
| **`K8S_CLUSTERS`** | Multi-entry registry (list). Each entry describes one cluster known to the shared ServiceNow instance, with per-entry **capability flags** selecting what this repo's automation does for it. |
| **`K8S_KVA_HELM_REPO`** | ServiceNow KVA Informer Helm repository URL. |

Regenerate context files after editing:

```bash
cd vars && ./generate_contexts.sh service-now
# or: ansible-playbook ... discovery/common/regenerate_context.yml
```

Generated outputs: `vars/contexts/servicenow_ansible_vars.yml` (includes
`K8S_CLUSTERS`).

### `K8S_CLUSTERS` entry fields

Each list item in `K8S_CLUSTERS` supports:

| Field | Required | Description |
| ----- | -------- | ----------- |
| **`name`** | Yes | Kubernetes cluster name in CMDB and Dynatrace (must match KVA `clusterName`). |
| **`location`** | Yes | `cmn_location.name` in ServiceNow (`k8s/deploy.yml` creates location if missing). Every entry with a location is location-mapped, regardless of flags. |
| **`location_full_name`** | Recommended | Display name for `cmn_location` when created by deploy. |
| **`kva_informer`** | Capability flag | `true` = this repo installs the KVA informer (`k8s/install.yml`) and validates the cluster's CMDB content (`k8s/test.yml`). Absent = false. |
| **`dynatrace`** | Capability flag | `true` = this repo applies DynaKube, auto-tags, and the management zone for this cluster name (Dynatrace playbooks). Absent = false. Exactly one entry may carry this flag (templates reference a single cluster name). |
| **`kva_namespace`** | When `kva_informer` | Namespace for KVA Informer (e.g. `servicenow-kva`). |
| **`api_url`** | Optional | Kubernetes API URL (documentation / future use). |
| **`environment`** | Optional | `on-prem`, `azure`, etc. |
| **`cloud_provider`** | Optional | Cloud provider when applicable. |

**Example (current optimizincdemo1):**

```yaml
K8S_CLUSTERS:
  value:
    - name: brooks-lab
      location: brooks-lab
      location_full_name: Brooks Lab
      kva_informer: true
      dynatrace: true
      api_url: https://192.168.1.207:6443
      kva_namespace: servicenow-kva
      environment: on-prem
    - name: aks-otel-demo
      location: bradens-cloud
      location_full_name: Braden Cloud Demo
      environment: azure
      cloud_provider: azure
  contexts: [service-now, dynatrace-ansible]
```

No ServiceNow custom mapping table is required. `K8S_CLUSTERS` is the GitOps
source; `k8s/deploy.yml` applies locations to cluster CIs and installs the
instance business rule that inherits `cluster.location` to child K8s CIs.
Entries without capability flags (e.g. `aks-otel-demo`) exist solely for
location mapping of CIs that arrive via someone else's instrumentation.

### Dynatrace alignment

The `dynatrace: true` entry's `name` replaces the former `DT_K8S_CLUSTER_NAME`
/ `K8S_PRIMARY_CLUSTER`. After changing the cluster name, redeploy Dynatrace
so DynaKube, auto-tags, and management zones match:

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/observability/dynatrace/deploy.yml \
  -e @../vars/secrets.yaml --tags k8s,partitioning
```

### Phase 2 install sequence

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/install.yml \
  -e @../vars/secrets.yaml
# wait for KVA full discovery (~5 min)
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/deploy.yml \
  -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/test.yml \
  -e @../vars/secrets.yaml
```

See `discovery/k8s/README.md` for playbook details.

---

## 6. Docker prerequisites (Phase 3 — Lab3 observability stack)

Phase 3 registers running Docker containers from the Lab3 observability Compose
stack into CMDB. Location is inherited from the **Linux server CI** (`lab3`) via
an instance business rule — the same GitOps pattern as Kubernetes.

### Variable model (`vars/variables.yaml`)

Docker host definitions live in **`vars/variables.yaml`** (immediately after
`K8S_CLUSTERS`). Use **Docker-prefixed** names (not `SN_`) for host/stack constructs.

| Variable | Purpose |
| -------- | ------- |
| **`DOCKER_HOSTS`** | Multi-entry registry (list). Each entry describes one Docker host/stack, with a per-entry **capability flag** selecting what this repo's automation does for it. |

Regenerate context files after editing:

```bash
cd vars && ./generate_contexts.sh -f service-now
```

### `DOCKER_HOSTS` entry fields

| Field | Required | Description |
| ----- | -------- | ----------- |
| **`name`** | Yes | Logical stack name (used in playbooks and logs). |
| **`location`** | Yes | Expected `cmn_location.name` (inherited from host CI via business rule). |
| **`location_full_name`** | Recommended | Display name when location is created by deploy. |
| **`container_discovery`** | Capability flag | `true` = this repo syncs running containers into `cmdb_ci_docker_container` (`docker/discover.yml`) and validates them (`docker/test.yml`). Absent = false. |
| **`cmdb_host_name`** | Yes | CMDB Linux server name (e.g. `lab3` from Phase 1). |
| **`ansible_host`** | When `container_discovery` | Inventory host to run `docker ps` on (e.g. `Lab3`). |
| **`compose_dir`** | Optional | Compose project directory name (documentation). |
| **`description`** | Optional | Human-readable stack description. |

**Example (current optimizincdemo1):**

```yaml
DOCKER_HOSTS:
  value:
    - name: lab3-observability
      location: brooks-lab
      location_full_name: Brooks Lab
      container_discovery: true
      cmdb_host_name: lab3
      ansible_host: Lab3
      compose_dir: observability
      description: Lab3 observability Docker Compose stack
  contexts: [service-now, dynatrace-ansible]
```

Phase 1 must have discovered **`lab3`** with `location=brooks-lab` before Phase 3.
`docker/deploy.yml` installs business rule **`docker-inherit-location-from-host`**
so new/updated `cmdb_ci_docker_container` rows copy `host.location`.

### Phase 3 install sequence

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/deploy.yml \
  -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/discover.yml \
  -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/test.yml \
  -e @../vars/secrets.yaml
```

See `discovery/docker/README.md` for playbook details.

---

## 7. Dynatrace SGC and Event Management (Phase 4)

Phase 4 adds **Service Graph Connector for Observability – Dynatrace** (topology import) and
**Event Management** push (problems → `em_event`). Detailed mapping and event-field reference:
`tmp/Dynatrace-ServiceNow SGC.md`, `tmp/Dynatrace-ServiceNow-events.md`.

Playbooks: `ansible/playbooks/servicenow/sgc/` (Dynatrace-specific configuration
under `sgc/sources/dynatrace/`, events under `sgc/sources/dynatrace/events/`).

### Automation posture

Store app and plugin installation **is automated** by `sgc/install.yml`
(manifest, CI/CD App Repo Install by scope in manifest order, plugin
activation, progress polling, re-verification). Implementation details live in
the playbook, not in this document.

What remains manual is a one-time **bootstrap** that the automation user
cannot perform for itself:

| One-time prerequisite | Why it cannot be automated |
| --------------------- | -------------------------- |
| Grant `admin_brooks_lab` the roles in the table below | A user cannot grant itself roles; requires an instance admin (Optimiz on the shared demo) |
| Plugin **`com.snc.ci_cd`** active | Provides the `sn_cicd` REST endpoints — the CI/CD API cannot activate itself |
| Store entitlement / first-time license click-through | Contractual acceptance is UI-only in ServiceNow Store |

On an instance we own, the first two could also be scripted under an admin
credential; on optimizincdemo1 they are requests to the instance owners.
Without the bootstrap, `sgc/install.yml` degrades to a state report plus the
manual steps below.

### Bootstrap sequence (interleaved manual / automated steps)

**Ordering constraint:** a role record only exists once the app that delivers
it is installed. `sn_cicd.sys_ci_automation` ships with the CI/CD tooling, so
on a bare instance the **plugin activation must precede the role grant**. On
**optimizincdemo1 the CI/CD tooling is already present** (CICD Spoke v2.0.2;
`/api/sn_cicd` endpoints answer 400/403, not 404), so the role **can be
granted up front** and the sequence collapses to steps 3–4.

`sgc/install.yml` runs a bootstrap preflight
(`sgc/common/check_cicd_bootstrap.yml`) whenever components need installing:
it checks that the role record exists and that the automation user holds it,
and **fails fast naming the exact missing manual step**. The interleaving is
therefore just *run → perform the reported step → re-run* — the playbook is
idempotent and skips completed work.

| # | Actor | Step |
| - | ----- | ---- |
| 1 | instance admin (manual, once) | Create automation user, grant Phase 1–3 roles (§1–2) |
| 2 | instance admin (manual, once, **only if** the preflight reports the role record missing) | Activate plugin `com.snc.ci_cd` (System Definition → Plugins) — the CI/CD API cannot activate its own plugin |
| 3 | instance admin (manual, once) | Grant `sn_cicd.sys_ci_automation`, `sn_appclient.app_client_user`, and `evt_mgmt_admin` (see the roles table) to `admin_brooks_lab` |
| 4 | automation | Run `sgc/install.yml` — installs everything else; re-run after any grant |
| 5 | operator (manual, once) | Guided Setup (section E below) |

### Roles required by the automation user (`admin_brooks_lab`)

| Role | Needed for (tables / APIs) |
| ---- | -------------------------- |
| `cmdb_inst_admin` | CMDB tables — `cmdb_ci_*`, `cmdb_rel_ci`, `sys_object_source`; Identification/Reconciliation API `/api/now/identifyreconcile` |
| `discovery_admin` | Discovery configuration and status — `discovery_schedule`, `discovery_status`, `ecc_agent` (MID server), `ecc_queue` |
| `evt_mgmt_admin` | Event Management — `em_event`, `em_alert`, event rules |
| `rest_service` | Inbound REST web-service access (basic-auth API calls as this user) |
| `sn_appclient.app_client_user` | `sys_store_app` read (App Manager visibility) — latest-version / update-available reporting in `diagnose.yml`. Not needed to install: the App Repo Install API takes the scope directly |
| `sn_cicd.sys_ci_automation` | CI/CD API — `/api/sn_cicd/app_repo/install` (by scope), `/api/sn_cicd/plugin/{id}/activate`, `/api/sn_cicd/progress/{id}` |
| `snc_platform_rest_api_access` | Platform REST APIs — Table API `/api/now/table/*` (incl. `sys_scope`, `sys_user_role`, `sys_user_has_role`) |

Not grantable as a role: **`sys_plugins`** read is admin-only by default. The
playbooks treat plugin state as unverifiable, report it as such, and request
activation idempotently via the CI/CD API.

### Required Store applications and plugins (install order)

The authoritative manifest — names, scopes, install order, and **pinned
versions** — is **`sgc/common/store_apps.yml`** (`sn_store_apps`; sgc-local
because only the sgc playbooks consume it). `sgc/install.yml` consumes it;
`sgc/diagnose.yml` reports installed vs pinned vs latest versions. Update pins
there after a deliberate upgrade.

Install in this order. Later apps depend on earlier ones.

| # | Name | Scope / ID | Type | Purpose |
| - | ---- | ---------- | ---- | ------- |
| 1 | Observability Commons for CMDB | `sn_observability` | Store app | Required before SGC; notification payload template step |
| 2 | Integrations Commons for CMDB | `sn_cmdb_int_util` | Store app | IH/RTE/IRE commons for SGC |
| 3 | CMDB CI Class Model | `sn_cmdb_ci_class` | Store app | CSDM class model for SGC mappers |
| 4 | ITOM Discovery License | `com.snc.itom.discovery.license` | Plugin | Discovery entitlement (usually already on ITOM instances) |
| 5 | Event Management | `sn_em_ai` | Store app | `em_event` processing, push connector listener |
| 6 | IntegrationHub Data Stream action type | `com.glide.hub.action_type.datastream` | Plugin | Required for SGC scheduled imports |
| 7 | Service Graph Connector for Observability – Dynatrace | `sn_dynatrace_integ` | Store app | SGC + Dynatrace push connector (`source=SGO-Dynatrace`) |

`sgc/install.yml` attempts plugin activation via the CI/CD API; on strict or
shared instances plugins may still need a manual **Request Plugin** (step B
below) or a ServiceNow HI case.

### Manual Store install — step-by-step (fallback)

Run `sgc/install.yml` first — it skips installed components and tells you what
remains. Use these manual steps when the automated path is blocked (missing
`sn_cicd.sys_ci_automation`, no Store entitlement, first-time license
click-through, or plugin requests requiring an HI case).

Assumes Zurich UI; navigation names may vary slightly by role.

#### A. Resolve entitlement and roles

Use an account with **`admin`** or **`sn_appclient.app_client_company_installer`**
(and Store access) — first-time UI installation requires the company-installer
role; `sn_appclient.app_client_user` alone does not grant it. For post-install
Ansible, also grant `admin_brooks_lab`:

| Additional role | Why |
| ----------------- | --- |
| **evt_mgmt_admin** | Read/create `em_event`; validate event integration |
| **sn_cicd.sys_ci_automation** | App Repo Install + plugin activation API |
| **sn_appclient.app_client_user** | Least-privilege read on `sys_store_app` (latest-version reporting); the installer role is **not** needed for the automated path — install authority comes from the CI/CD API |
| **cmdb_inst_admin** | Already on automation user for Phases 1–3 |

Coordinate with **Optimiz / instance owners** before installing on a shared demo.

#### B. Request the Data Stream plugin (once per instance)

1. Navigate to **System Applications → All Available Applications → Request Plugin** (or **System Definition → Plugins**).
2. Search **`com.glide.hub.action_type.datastream`**.
3. Click **Request Plugin** / **Activate** and wait until state is **Active** (may require ServiceNow HI case on strict instances).

#### C. Install each Store application (repeat for the Store apps in the table above)

1. Open **System Applications → All Available Applications** (or **ServiceNow Store** from the app navigator filter).
2. Search for the exact application name (e.g. `Service Graph Connector for Observability - Dynatrace`).
3. Open the application record → **Install** (or **Get** then **Install** from Store).
4. Choose **Install** (not **Install with Demo Data** unless you explicitly want demo content).
5. Wait for install to complete (progress in **System Applications → Installation History** or the overlay).
6. Confirm **Application State = Installed** and scope appears under **System Applications → Application Menus** (e.g. filter `Dynatrace Observability`).

**Tips:**

- Install **one app at a time** on busy shared instances to avoid “another update operation is active”.
- If Install is disabled, check **Company → Subscriptions**, dependency apps (previous row in table), or ask instance admin for Store entitlement.
- The automated path does not need package `sys_id`s — the CI/CD App Repo Install API takes the application scope directly.

#### D. Verify installs (Table API or UI)

```text
sys_scope.scope = sn_dynatrace_integ          → row exists
sys_store_app.scope IN (sn_observability, sn_dynatrace_integ, sn_em_ai, …) → active
```

Or run:

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/diagnose.yml -e @../vars/secrets.yaml
```

Expected after success: `scoped app (sn_dynatrace_integ): INSTALLED` and a
per-component version report (installed vs pinned vs latest).

#### E. Guided Setup (ServiceNow UI — not Ansible)

1. Navigate to **Dynatrace Observability → Setup** (module installed with `sn_dynatrace_integ`).
2. Complete Guided Setup sections in order:
   - **Connection** — Dynatrace tenant URL (`DT_API_URL` base), API token with `entities.read`, `settings.read`, etc.
   - **Filters** — Management zone **`Spark Observability`** and/or tags (`Project:spark-observability`, `Environment:lab`).
   - **Service types** — enable types your stack needs (see `tmp/Dynatrace-ServiceNow SGC.md`).
   - **Create Default Notification Payload Template** — creates Dynatrace problem notification + ServiceNow webhook with `source=SGO-Dynatrace` (requires `sn_observability` installed first).
3. **Advanced → Configure Instance Settings** — confirm `serviceTypes`, `tags`, connection properties.
4. **Scheduled Data Imports** — run **Execute** on parent jobs (Hosts first, then Processes/Services). Monitor **Concurrent Import Sets** until complete.
5. Verify **`sys_object_source`** rows with `name=SGO-Dynatrace` and CMDB CIs with `discovery_source=SGO-Dynatrace`.

#### F. Ansible after SGC is installed

```bash
cd ansible
# Re-run event deploy — switches webhook to source=SGO-Dynatrace when scope detected
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/diagnose.yml -e @../vars/secrets.yaml
```

### Phase 4 install sequence (summary)

```bash
# 0. One-time manual bootstrap (see "Bootstrap sequence" above): activate
#    com.snc.ci_cd only if the preflight reports it missing; grant
#    sn_cicd.sys_ci_automation; Store entitlement / license click-through if
#    prompted. install.yml fail-fasts naming the missing step — re-run after.

# 1. Store apps + plugins (idempotent; skips installed components)
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/install.yml -e @../vars/secrets.yaml

# 2. Manual: Guided Setup (section E above) — connection, filters,
#    scheduled imports, notification payload template

# 3. Verify component versions / SGC / CMDB merge state
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/diagnose.yml -e @../vars/secrets.yaml

# 4. Fail-fast if SGC still missing (or proceed after install)
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/deploy.yml -e @../vars/secrets.yaml

# 5. Dynatrace alerting + webhook (brooks-lab objects only)
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/deploy.yml -e @../vars/secrets.yaml

# 6. Generate load + validate events
cd ../spark/apps/data-analysis-book && ./run-chapters.sh -a
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/test.yml -e @../vars/secrets.yaml
```

### Not automatable (manual, one-time or per-upgrade)

| Action | Where | Why not automated |
| ------ | ----- | ----------------- |
| Grant roles (`sn_cicd.sys_ci_automation`, `sn_appclient.app_client_user`, `evt_mgmt_admin`) | User Administration | Role grants require instance admin on the shared demo |
| Store entitlement / license click-through | ServiceNow Store / Subscriptions | Contractual acceptance is UI-only |
| Plugin request when CI/CD activation is denied | System Definition → Plugins / HI case | Strict instances gate plugin activation |
| **Guided Setup** (connection, filters, service types, payload template) | Dynatrace Observability → Setup | No public API for the SGC guided-setup steps |
| Scheduled Data Imports first execution | Dynatrace Observability → Scheduled Data Imports | Operator-triggered; monitor Concurrent Import Sets |

**Required IDs / prerequisite configuration:**

| Variable | Where | Purpose |
| -------- | ----- | ------- |
| `SN_DT_LEGACY_CONNECTOR_SYS_ID` | `vars/variables.yaml` (service-now) | Pre-existing legacy EM push connector (`712a39811…`) used until SGC is installed |
| `SN_URL`, `SN_INSTANCE_SHORT_NAME` | `vars/variables.yaml` (service-now) | Instance identity |
| `DT_API_URL`, `DT_API_TOKEN`, `DT_MANAGEMENT_ZONE` | `vars/variables.yaml` (dynatrace-ansible) / secrets | Dynatrace side |
| `sn_store_apps` | `sgc/common/store_apps.yml` (sgc-local) | App/plugin manifest: scopes, install order, pinned versions |

Package `sys_id`s are **not** configuration and are not needed — `install.yml`
installs by application **scope** via the CI/CD App Repo Install API.

### Do not override others’ work (shared demo)

**Naming convention for brooks-lab automation:**

| System | Prefix / name pattern | Examples |
| ------ | --------------------- | -------- |
| Dynatrace | `Spark Observability`, `Spark Lab`, `brooks-lab` | Alerting profile, metric event, problem notification |
| ServiceNow | `brooks-lab` location scope | CMDB rows, Discovery schedules |

**Ansible idempotency rules:**

- Dynatrace objects are upserted by **displayName/summary** (`Spark Observability - ServiceNow brooks-lab`, etc.) — does **not** modify `Default`, `DemoProfile - Optimiz`, or **`ServiceNow Demo 1 - Optimiz`**.
- Problem notification deploy **copies payload template** from pre-existing `ServiceNow Demo 1 - Optimiz` only when creating the brooks-lab notification; it does **not** update Demo 1.
- ServiceNow Discovery/K8/Docker playbooks scope to **`brooks-lab`** location and named schedules — they do not delete or reconfigure unrelated CMDB CIs.

**Pre-existing tenant configuration (not created by this repo):**

| Object | Status |
| ------ | ------ |
| Dynatrace problem notification **`ServiceNow Demo 1 - Optimiz`** | **Pre-existing** — webhook to `optimizincdemo1…/inbound_event?source=dynatrace&sys_id=712a39811…` |
| ServiceNow EM push connector **`712a39811ba483105488a937b04bcba5`** | **Pre-existing** — referenced by Demo 1 notification; **not** created or modified by our playbooks |
| Dynatrace notification **`ServiceNow optimiz demo3`** | **Pre-existing** — points at optimizincdemo3 |

Contact **Optimiz / prior integrators** before changing Demo 1, connector `712a39811…`, or shared Dynatrace notifications.

**Created by brooks-lab automation (2026-06-08):**

- Dynatrace: `Spark Observability - ServiceNow brooks-lab` (alerting profile)
- Dynatrace: `Spark Lab - Host CPU above 80%` (metric event)
- Dynatrace: `ServiceNow brooks-lab - Spark Observability` (problem notification — uses legacy URL until SGC installed)

---

## Installation sequence

Run from the `ansible/` directory:

```bash
# 0. Permission and connectivity check
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/diagnose.yml \
  -e @../vars/secrets.yaml

# 1. sn-discovery on Lab1–Lab3; MID Server package on Lab3
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/install.yml \
  -e @../vars/secrets.yaml

# 2. ServiceNow objects (location, credential, range, schedule)
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/deploy.yml \
  -e @../vars/secrets.yaml

# 3. Validate MID Server "Up" in ServiceNow UI:
#    MID Server > Servers > mid-brooks-lab3

# 4. On-demand Discovery scan
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/discover.yml \
  -e @../vars/secrets.yaml

# 5. Assert Linux server CIs (after scan completes)
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/test.yml \
  -e @../vars/secrets.yaml
```

Install only the discovery SSH account (skip MID):

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/install.yml \
  -e @../vars/secrets.yaml --tags discovery_user
```

---

## Troubleshooting

| Symptom | Check |
| ------- | ----- |
| `deploy.yml` 403 on Discovery tables | `admin_brooks_lab` roles; run `diagnose.yml` |
| MID stays Down | `mid_brooks_lab` has `mid_server`; password matches `config.xml`; `&` in password XML-escaped |
| MID user cannot run deploy | Expected — use `admin_brooks_lab` (`SN_USER`) |
| No CIs after scan | MID Up; schedule linked to range + credential; wait for scan completion |
| Duplicate CIs | Hostnames must be `Lab1.lan`, `Lab2.lan`, `Lab3.lan` consistently |

---

## Related documentation

- `../README.md` — playbook layout
- `../discovery/README.md` — playbook verbs
- `docs/architecture-and-resources.md` — Lab3 MID memory budget
- `tmp/ServiceNow_Dynatrace_Integration.md` — CMDB / Dynatrace design
- `tmp/Dynatrace-ServiceNow SGC.md` — SGC / IRE mapping
- `tmp/Dynatrace-ServiceNow-events.md` — event paths, field mapping, webhook comparison
