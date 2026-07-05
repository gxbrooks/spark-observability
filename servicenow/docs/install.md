# ServiceNow Discovery — installation guide

This document covers **prerequisites** on the ServiceNow instance and lab hosts,
then the Ansible install sequence for brooks-lab Discovery.

**Instance:** [https://optimizincdemo1.service-now.com/](https://optimizincdemo1.service-now.com/)  
**Playbooks:** `ansible/playbooks/servicenow/discovery/`  
**Variables:** `vars/variables.yaml` → `**service-now`** context → generated
`vars/contexts/servicenow_ansible_vars.yml`  
**Secrets:** `vars/secrets.yaml` → `servicenow:` block (see `vars/secrets.example.yaml`)

---

## Prerequisites overview

Sections **1–4** are **Phase 1** (horizontal Discovery). Sections **5–7** are Phases **2–4**
(Kubernetes KVA, Docker container discovery, Dynatrace SGC).

Phase 1 needs **three separate identities**. They must not be combined into one
ServiceNow user.


| Identity             | Where it lives             | Purpose                                                     |
| -------------------- | -------------------------- | ----------------------------------------------------------- |
| **admin_brooks_lab** | ServiceNow (`SN_USER`)     | Ansible REST automation — locations, credentials, schedules |
| **mid_brooks_lab**   | ServiceNow (`SN_MID_USER`) | MID Server agent authentication only                        |
| **sn-discovery**     | Linux on Lab1–Lab3         | SSH target for Discovery classification probes              |


---

## 1. ServiceNow user: `admin_brooks_lab`

Used by Ansible `deploy.yml`, `discover.yml`, `diagnose.yml`, and `test.yml`.
Mapped to `servicenow.SN_USER` in `vars/secrets.yaml`.

### User record


| Field                  | Value                                              |
| ---------------------- | -------------------------------------------------- |
| **User ID**            | `admin_brooks_lab`                                 |
| **Identity type**      | Machine                                            |
| **Web service access** | Enabled (required for REST Table API / Basic Auth) |
| **Interactive login**  | Not required                                       |


### Required roles (minimum effective set)

Grant enough rights to **read and write** Discovery configuration tables and
CMDB locations. On optimizincdemo1 the following roles are effective:


| Role                                    | Why                                                                                                                                                                                                                                  |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **discovery_admin**                     | Discovery schedules, ranges, credentials, run scans *(or equivalent ACLs via elevated CMDB/admin roles)*                                                                                                                             |
| **cmdb_inst_admin**                     | Create/update `cmn_location` (**brooks-lab**); CMDB CI tables. For tag-based Service Mapping, also requires a **table ACL extension** on `**cmdb_key_value`** — see [§6.3](#63-enable-automation-to-update-key-value-pairs) |
| **rest_service**                        | REST API access                                                                                                                                                                                                                      |
| **snc_platform_rest_api_access**        | Table API authentication                                                                                                                                                                                                             |
| **cmdb_query_builder** or **cmdb_read** | `test.yml` CMDB validation                                                                                                                                                                                                           |


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


| Field                  | Value            |
| ---------------------- | ---------------- |
| **User ID**            | `mid_brooks_lab` |
| **Identity type**      | Machine          |
| **Web service access** | Enabled          |
| **Interactive login**  | Not required     |


### Required roles


| Role           | Required                   |
| -------------- | -------------------------- |
| **mid_server** | **Yes — only role needed** |


Do **not** grant `discovery_admin`, `admin`, or `itil` to this user unless
ServiceNow support documents a specific exception. Least privilege is
`mid_server` alone.

### Password and `config.xml`

The User ID and password must match `mid.instance.username` and
`mid.instance.password` in the MID `config.xml` on Lab3 (rendered by
`discovery/install.yml`).

If the password contains `**&`**, `<`, `>`, or quotes, the install template
XML-escapes it automatically. Prefer passwords without `&` when rotating, to
avoid encoding mistakes in manual edits.

### What the MID user cannot do (verified)

`mid_brooks_lab` with `**mid_server` only** is **not sufficient to complete
Phase 1 by itself**:


| Action                               | MID user | admin_brooks_lab |
| ------------------------------------ | -------- | ---------------- |
| Authenticate MID agent / ECC queue   | Yes      | N/A              |
| Read `ecc_agent` (MID registration)  | Yes      | Yes              |
| Create `cmn_location` (brooks-lab)   | **No**   | Yes              |
| Create `discovery_credentials`       | **No**   | Yes              |
| Create `discovery_schedule` / ranges | **No**   | Yes              |
| Run `deploy.yml` / `discover.yml`    | **No**   | Yes              |


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


| Field        | Value                                                              |
| ------------ | ------------------------------------------------------------------ |
| **Username** | `sn-discovery` (override: `SN_DISCOVERY_USER` in `variables.yaml`) |
| **Auth**     | SSH public key (generated on controller)                           |
| **Sudo**     | Limited NOPASSWD for Discovery classification commands             |
| **Purpose**  | Target credential for SSH-based Linux CI Discovery on lab servers  |


Private key path (gitignored): `vars/sn_discovery_id_ed25519`  
Uploaded to ServiceNow as credential `**brooks-lab-ssh`** by `deploy.yml`.

---

## 4. Instance and lab prerequisites

### ServiceNow instance

- ITOM **Discovery** and **CMDB** licensed/active on the instance
- `admin_brooks_lab` and `mid_brooks_lab` created with roles above
- `SN_URL` set in `vars/variables.yaml` (service-now context; not a secret)
- `vars/secrets.yaml` populated (both users, passwords)
- Copy `vars/secrets.example.yaml` field names if migrating from older `lab_admin` naming

### Lab hosts

- Lab1, Lab2, Lab3 powered on and reachable via Ansible inventory
- Lab3 outbound HTTPS (443) to `optimizincdemo1.service-now.com`
- Lab3 can reach `192.168.1.0/24` for Discovery scans
- ~4–6 GiB RAM headroom on Lab3 for MID JVM (see `docs/architecture-and-resources.md`)

### MID Server package

- `SN_MID_INSTALLER_DEB_URL` in `vars/variables.yaml` (service-now context)
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


| Object           | Name / value                                                                |
| ---------------- | --------------------------------------------------------------------------- |
| Location         | `brooks-lab` (`cmn_location`)                                               |
| IP range         | `192.168.1.0/24`                                                            |
| SSH credential   | `brooks-lab-ssh` → `sn-discovery`                                           |
| Schedule         | `Brooks Lab CI Discovery`                                                   |
| MID Server name  | `mid-brooks-lab3` (Lab3)                                                    |
| Discover Now API | **Discovery Operations API** (global Scripted REST; `discovery/deploy.yml`) |


Only Lab1–Lab3 have SSH credentials; other addresses on the subnet may appear
as network or unclassified devices.

### Discovery Operations REST API (`discovery/deploy.yml`)

`deploy.yml` creates a **global-scoped Scripted REST API** (**Discovery Operations
API**) that wraps the platform `global.Discovery()` scriptable API. `discover.yml`
calls the schedule endpoint; operators and automation may also call Quick Discovery.


| Endpoint                                  | Script API                  | Body (JSON)                              |
| ----------------------------------------- | --------------------------- | ---------------------------------------- |
| `POST …/schedule/run` (or legacy `…/run`) | `discoverNow(scheduleGr)`   | `schedule_name` **or** `schedule_sys_id` |
| `POST …/quick/run`                        | `discoveryFromIP(ip, mid?)` | `ip_address`; optional `mid_server`      |



| Requirement                                     | Role                                                   |
| ----------------------------------------------- | ------------------------------------------------------ |
| Create `sys_ws_definition` / `sys_ws_operation` | `**web_service_admin`**                                |
| Execute Discovery in the script                 | `**discovery_admin**`                                  |
| Invoke the REST endpoint                        | `**rest_service**`, `**snc_platform_rest_api_access**` |


ServiceNow assigns the base path (instance-specific). Operation URIs are written
to `vars/contexts/servicenow_discovery_deploy.json` as `discovery_rest_operation_uri`
and `discovery_rest_quick_uri`.

CMDB license checks use the **CI/CD plugin activate API** (`sn_cicd.sys_ci_automation`)
— not Table API reads on `sys_plugins`.

---

## 5. Phase 2 — Kubernetes prerequisites (KVA Informer)

Phase 2 discovers the brooks-lab Kubernetes cluster into CMDB via the **Kubernetes
Visibility Agent (KVA) Informer** only. Cluster identity is shared with Dynatrace
so CMDB and observability stay aligned on one **K8-native cluster name**.

### Variable model (`vars/variables.yaml`)

All Kubernetes cluster definitions live in the **Kubernetes** section of
`variables.yaml`. Use **K8-prefixed** names (not `SN_` or `DT_`) for constructs
that exist in the cluster itself.


| Variable                | Purpose                                                                                                                                                                                       |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `**K8S_CLUSTERS`**      | Multi-entry registry (list). Each entry describes one cluster known to the shared ServiceNow instance, with per-entry **capability flags** selecting what this repo's automation does for it. |
| `**K8S_KVA_HELM_REPO`** | ServiceNow KVA Informer Helm repository URL.                                                                                                                                                  |


Regenerate context files after editing:

```bash
cd vars && ./generate_contexts.sh service-now
# or: ansible-playbook ... discovery/common/regenerate_context.yml
```

Generated outputs: `vars/contexts/servicenow_ansible_vars.yml` (includes
`K8S_CLUSTERS`).

### `K8S_CLUSTERS` entry fields

Each list item in `K8S_CLUSTERS` supports:


| Field                    | Required            | Description                                                                                                                                                                                                             |
| ------------------------ | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `**name**`               | Yes                 | Kubernetes cluster name in CMDB and Dynatrace (must match KVA `clusterName`).                                                                                                                                           |
| `**location**`           | Yes                 | `cmn_location.name` in ServiceNow (`k8s/deploy.yml` creates location if missing). Every entry with a location is location-mapped, regardless of flags.                                                                  |
| `**location_full_name**` | Recommended         | Display name for `cmn_location` when created by deploy.                                                                                                                                                                 |
| `**kva_informer**`       | Capability flag     | `true` = this repo installs the KVA informer (`k8s/install.yml`) and validates the cluster's CMDB content (`k8s/test.yml`). Absent = false.                                                                             |
| `**dynatrace**`          | Capability flag     | `true` = this repo applies DynaKube, auto-tags, and the management zone for this cluster name (Dynatrace playbooks). Absent = false. Exactly one entry may carry this flag (templates reference a single cluster name). |
| `**kva_namespace**`      | When `kva_informer` | Namespace for KVA Informer (e.g. `servicenow-kva`).                                                                                                                                                                     |
| `**api_url**`            | Optional            | Kubernetes API URL (documentation / future use).                                                                                                                                                                        |
| `**environment**`        | Optional            | `on-prem`, `azure`, etc.                                                                                                                                                                                                |
| `**cloud_provider**`     | Optional            | Cloud provider when applicable.                                                                                                                                                                                         |


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

## 6. Phase 3 — Docker prerequisites

Phase 3 registers running Docker containers from Compose stacks into CMDB. Location is
inherited from the **Linux server CI** via an instance business rule — the same GitOps
pattern as Kubernetes.

### 6.1 Variable model (`vars/variables.yaml`)

Docker host definitions live in `**vars/variables.yaml`** (immediately after
`K8S_CLUSTERS`). Use **Docker-prefixed** names (not `SN_`) for host/stack constructs.


| Variable           | Purpose                                                                                                                                                          |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `**DOCKER_HOSTS`** | Multi-entry registry (list). Each entry describes one Docker host/stack, with a per-entry **capability flag** selecting what this repo's automation does for it. |


Regenerate context files after editing:

```bash
cd vars && ./generate_contexts.sh -f service-now
```

### 6.2 `DOCKER_HOSTS` entry fields


| Field                     | Required                   | Description                                                                                                                                                 |
| ------------------------- | -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `**name**`                | Yes                        | Logical stack name (used in playbooks and logs).                                                                                                            |
| `**location**`            | Yes                        | Expected `cmn_location.name` (inherited from host CI via business rule).                                                                                    |
| `**location_full_name**`  | Recommended                | Display name when location is created by deploy.                                                                                                            |
| `**container_discovery**` | Capability flag            | `true` = this repo syncs running containers into `cmdb_ci_docker_container` (`docker/discover.yml`) and validates them (`docker/test.yml`). Absent = false. |
| `**cmdb_host_name**`      | Yes                        | CMDB Linux server name (e.g. `lab3` from Phase 1).                                                                                                          |
| `**ansible_host**`        | When `container_discovery` | Inventory host to run `docker ps` on (e.g. `Lab3`).                                                                                                         |
| `**compose_dir**`         | Optional                   | Compose project directory name (documentation).                                                                                                             |
| `**description**`         | Optional                   | Human-readable stack description.                                                                                                                           |


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

Phase 1 must have discovered the host CI with the expected location before Phase 3.
`docker/deploy.yml` installs business rule `**docker-inherit-location-from-host**`
so new/updated `cmdb_ci_docker_container` rows copy `host.location`.

### 6.3 Enable automation to update key-value pairs

An out-of-the-box ServiceNow instance does not include permission configurations
sufficient for an automation service account (for example **`admin_brooks_lab`**) to
create tag key-value pairs. To enable automations to manage the **`cmdb_key_value`**
table, an authorized operational administrator must create the requisite ACLs. To
simplify configuration, augment the **`cmdb_inst_admin`** role with **create**,
**write**, and **delete** permissions on rows in **`cmdb_key_value`**. The procedure
below describes how to do so.

The automation service account (**`admin_brooks_lab`**) was assigned several roles —
see [§1 — Required roles](#required-roles-minimum-effective-set). One of those roles is
**`cmdb_inst_admin`**. Out of the box, **`cmdb_inst_admin`** can **read** the
**`cmdb_key_value`** table (via **`cmdb_read`** in the role hierarchy). Create Allow-if
ACLs only for **create**, **write**, and **delete**. Each ACL for **`cmdb_inst_admin`**
should use the fields in **Table 6.3 — `cmdb_key_value` ACL record fields**.

#### Table 6.3 — `cmdb_key_value` ACL record fields

| Field name | Value | Comment |
| ---------- | ----- | ------- |
| **Type** | `record` | Table ACL (not field or other type) |
| **Operation** | `create`, `write`, or `delete` | Create **one ACL per operation**; do **not** create a read ACL |
| **Name** | `cmdb_key_value` | Table picker → **Key Value**; leave the field box empty |
| **Decision type** | `Allow if` | Grants access when the role matches |
| **Active** | `true` | Inactive ACLs are ignored |
| **Admin overrides** | `false` | On an **existing** ACL, do **not** change this field |
| **Advanced** | `false` | Leave **Condition** and **Script** empty |
| **Application** | `Global` | |
| **Requires role** | `cmdb_inst_admin` | Related list → **Edit** → select role → **Save** |
| **Description** | *(optional)* | e.g. automation label sync for `admin_brooks_lab` |

To create or update these ACLs, go to **All → Access Control** and select **Access
Control (ACL)**. Filter **Name = `cmdb_key_value`**; optionally filter **Active =
true**. Look for **create**, **read**, **write**, and **delete** operations. If
**create**, **write**, or **delete** Allow-if ACLs do not exist, create an ACL for
**`cmdb_inst_admin`** per Table 6.3. If an ACL for the operation already exists,
ensure its fields match Table 6.3 — except do **not** change **Admin overrides** on an
existing ACL. Do **not** edit the active **read** ACL. Ignore inactive rows and
**`cmdb_key_value_v2`** (a different table).

Further context: [Tag_Based_Service_Mapping.md](Tag_Based_Service_Mapping.md).

#### 6.3.1 Elevate `security_admin` (prerequisite)

Table ACL edits require a human operator who can **elevate to `security_admin`**. On
shared demo instances (for example **optimizincdemo1**), two configuration steps are
often missing even after **`security_admin`** is assigned to a user:

1. The **`security_admin`** role must have **Elevated privilege = true** on the role
   record (otherwise **Profile → Elevate role** shows an empty **Available roles**
   list).
2. The operator user must be granted **`security_admin`** and must **log out and back
   in** after the grant.

Perform **Part A** once per instance. Perform **Part B** for each human operator who
will edit ACLs (for example **Gary Brooks** / `gbrooks` on optimizincdemo1).

**Part A — `security_admin` role (instance maintainer)**

Use an account that already has full admin access (typically **`admin`**) — not the
operator who will perform ACL edits unless they already hold **`admin`**.

1. Open **User Administration → Roles** (Filter navigator: `sys_user_role.list`).
2. Open the **`security_admin`** role.
3. Confirm **Elevated privilege** is checked (**true**).
   - If the field is read-only, an instance maintainer may need to adjust the field ACL
     on **`sys_user_role`** temporarily (common on hardened instances).
4. **Save** the role.
5. Optional API check (as a user who can read roles):
   ```bash
   # Expect elevated_privilege=true in the result
   curl -s -u "$SN_USER:$SN_PASSWORD" \
     'https://optimizincdemo1.service-now.com/api/now/table/sys_user_role?sysparm_query=name=security_admin&sysparm_fields=name,elevated_privilege' \
     | python3 -m json.tool
   ```
   On some instances the role record is hidden from non-admin REST callers; use the UI
   in that case.

**Part B — Operator user profile (who performs ACL changes)**

The operator needs **`security_admin`** assigned directly (group inheritance also
works). They do **not** need **`admin`** for the **`cmdb_key_value`** ACL task alone.

1. **User Administration → Users** → open the operator (for example **Gary Brooks** /
   **`gbrooks`**).
2. **Roles** related list → confirm **`security_admin`** is present.
   - Do not confuse with **`agent_security_admin`** or **`security_dashboard_user`**
     — those are different roles and do not replace **`security_admin`** for ACL
     edits.
3. If **`security_admin`** is missing, an instance admin adds it (**Edit** → select
   **`security_admin`** → **Save**). A user cannot grant themselves roles they do not
   already hold.
4. Operator **logs out completely** and signs back in (session cache refresh).
5. Operator opens **Profile** (avatar menu) → **Elevate role**.
6. Under **Available roles**, select **`security_admin`** → **Update**.
   - If the list is still empty, return to **Part A** (Elevated privilege not set) or
     repeat step 4 (stale session).
7. Perform §6.3 ACL edits while elevated.
8. When finished, **log out** (elevation ends with the session) or leave elevation
   only for the duration of the security task.

**Part C — Verify elevation before ACL edits**

| Check | Expected |
| ----- | -------- |
| **Profile → Elevate role** lists **`security_admin`** | Checkbox visible; **Update** enabled |
| After elevation, **System Security → Access Control** opens | ACL forms editable (not read-only) |
| Without elevation, same ACL form | Read-only or insufficient privilege |

Alternative when elevation cannot be configured: use the **`admin`** account (or another
user who already has active **`security_admin`** without needing elevation) to perform
§6.3 once.

#### OOB ACL state (typical demo instance)

From a typical OOB/demo instance:

| Operation | Active ACL? | Decision | Requires role | Action needed |
| --------- | ----------- | -------- | ------------- | ------------- |
| **read** | Yes | Allow if | **`cmdb_read`** | **No operator action** — read already works |
| **query_range** | Yes | Allow if | (varies) | **Leave unchanged** — list/range queries, not REST insert |
| **create** | No (inactive Deny unless) | — | — | **Create new** Allow if ACL |
| **write** | No (inactive Deny unless) | — | — | **Create new** Allow if ACL |
| **delete** | No (inactive Deny unless) | — | — | **Create new** Allow if ACL |

ServiceNow uses **write** for record updates (PATCH). There is no separate **modify**
operation on table ACLs.

**Do not:**

- Activate the existing inactive **Deny unless** **create** / **write** / **delete** rows.
- Edit **`cmdb_key_value_v2`** ACLs or the active **query_range** ACL.
- Edit the active **read** ACL.

#### Verify

1. End **`security_admin`** elevation (log out or de-elevate per instance policy).
2. Run discovery:

   ```bash
   cd ansible
   ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/discover.yml \
     -e @../vars/secrets.yaml
   ```

3. In ServiceNow: **`cmdb_key_value.list`** → **Key** =
   `servicenow.io/application-service-identifier` → expect rows on container CIs.

4. Optional Table API spot-check (expect **201**, not **403**):

   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' -u "$SN_USER:$SN_PASSWORD" \
     -H 'Content-Type: application/json' \
     -d '{"configuration_item":"<container_ci_sys_id>","key":"servicenow.io/application-service-identifier","value":"grafana"}' \
     'https://optimizincdemo1.service-now.com/api/now/table/cmdb_key_value'
   ```

#### After ACL change

Re-run CSDM diagnose if application services were waiting for tags:

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/diagnose.yml -e @../vars/secrets.yaml
```

### 6.4 Phase 3 install sequence

**Prerequisite:** complete [§6.3](#63-enable-automation-to-update-key-value-pairs) if using tag-based Service Mapping for Docker.

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

### 6.5 Tag-based Service Mapping — Observability Application Services

**When:** After **§6.3** (`cmdb_key_value` ACLs), **§6.4** (`discovery/docker/discover.yml`), and **`csdm/deploy.yml`** for `observability-platform.csdm.yaml`.

**Who:** The Ansible automation user (`admin_brooks_lab`) configures tag-based population during **`csdm/deploy.yml`**. Tag Categories (Step A below) require **`service_mapping_admin`** on your interactive user ( **`sm_admin`** is often absent on Zurich).

**Why the CMDB map shows “add an entry point”:** CSDM creates **`cmdb_ci_service_discovered`** rows with **`service_mapping: tags`** and **`discover: false`**. The CMDB Service Map widget defaults to the **vertical** path until tag-based population runs. **`csdm/deploy.yml`** applies tag filters from each spec’s **`identifier`**, **`environment`**, and **`location`** via the Service Mapping Operations REST API. **Do not add entry points** for observability Docker services.

#### What Ansible automates vs what stays manual

| Step | Automated | Playbook / action |
| ---- | --------- | ----------------- |
| Delete + recreate Application Services | Yes | `observability-platform-delete.csdm.yaml` then `observability-platform.csdm.yaml` via `csdm/deploy.yml` (see below) |
| BA → BS → AS hierarchy + `depends_on` | Yes | `csdm/deploy.yml` |
| Container CIs + `servicenow.io/*` tags | Yes (after §6.3) | `discovery/docker/discover.yml` |
| Tag filter per Application Service (`tag_list`) | Yes | `csdm/deploy.yml` → `configure_tag_based_sm.yml` (when `service_mapping: tags`) |
| Tag Categories (instance-wide) | Yes | `service-mapping/deploy.yml` (via scoped REST; included in `csdm/deploy.yml`) |
| **Contains** workload → Application Service | **ServiceNow** (after tags + filters exist) | Tag-based mapping scheduled job / **Update map** |

For every Application Service with **`service_mapping: tags`** in a `*.csdm.yaml` file, the deploy processor POSTs a **`tag_list`** to **`/api/opti8/service_mapping_operations_api/populate_tags`**, using the same platform path as **`snc service-graph app-service populate`**. Disable with **`-e sn_csdm_configure_tag_sm=false`**.

Once tag filters exist, ServiceNow re-evaluates maps when new containers match — no per-container rule is needed.

#### Reset observability Application Services (test instance)

```bash
cd ansible
OBS="/home/gxbrooks/repos/spark-observability/servicenow/regions/brooks-lab"

# 1. Delete seven Application Services (BA/BS retained)
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/deploy.yml \
  -e @../vars/secrets.yaml \
  -e "{\"sn_csdm_spec_paths_override\": [\"$OBS/observability-platform-delete.csdm.yaml\"]}"

# 2. Recreate from CSDM spec (skip horizontal discovery trigger for faster run)
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/deploy.yml \
  -e @../vars/secrets.yaml \
  -e "{\"sn_csdm_spec_paths_override\": [\"$OBS/observability-platform.csdm.yaml\"], \"sn_csdm_trigger_horizontal_discovery\": false}"

# 3. Sync container tags (requires §6.3 ACLs)
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/discover.yml \
  -e @../vars/secrets.yaml
```

Override variable **`sn_csdm_spec_paths_override`** limits `csdm/deploy.yml` to one or more spec files (see `ansible/playbooks/servicenow/common/resolve_csdm_spec_paths.yml`).

#### Step A — Tag Categories (once per instance)

**Role:** **`service_mapping_admin`** (from plugin `com.snc.service-mapping`). Do **not** search for **`sm_admin`** — that role record is often missing on Zurich even when Service Mapping is installed.

**Install stack first:**

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/service-mapping/install.yml \
  -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/service-mapping/deploy.yml \
  -e @../vars/secrets.yaml
```

Tag categories are created automatically by **`service-mapping/deploy.yml`** (also run at the start of **`csdm/deploy.yml`**).

**Manual fallback** (when deploy output shows tag category errors):

1. Sign in as a user with **`service_mapping_admin`**.
2. Filter Navigator → **CI tag categories** (table `svc_tag_categories`), or open  
   [classic Tag Categories list](https://optimizincdemo1.service-now.com/now/nav/ui/classic/params/target/svc_tag_categories_list.do).
3. An **empty list is normal** on a greenfield instance — click **New** and create:

| Tag Category (name) | Label key (`tag_key`) |
| ------------------- | --------------------- |
| **Application Service** | `servicenow.io/application-service-identifier` |
| **Environment** | `servicenow.io/environment` |
| **Location** | `servicenow.io/location` |

The Service Mapping Workspace URL (`/now/svc-map/tag-categories`) may be unavailable when the **`sn_itom_map_app`** Store package cannot be downloaded on a shared demo; classic **CI tag categories** is sufficient for brooks-lab. See [ServiceNow tag mapping doc](https://www.servicenow.com/docs/r/it-operations-management/service-mapping/map-service-tag.html) (role: **`service_mapping_admin`**).

#### Step B — Tag population (automated by `csdm/deploy.yml`)

When **`service_mapping: tags`** is set on an Application Service in a `*.csdm.yaml` file, **`csdm/deploy.yml`** configures tag-based population automatically after the CI is created or updated. Tags are derived from the spec:

| CSDM field | Tag key |
| ---------- | ------- |
| **`identifier`** (with `{host}` / `{host_lower}` expansion) | `servicenow.io/application-service-identifier` |
| **`environment`** (when present) | `servicenow.io/environment` |
| **`location`** (when present) | `servicenow.io/location` |

For observability-platform, values match `observability/docker-compose.yml` labels:

| Application Service | `servicenow.io/application-service-identifier` | Optional scope |
| ------------------- | ------------------------------------------------ | -------------- |
| Elasticsearch | `elasticsearch` | environment=`on-prem`, location=`brooks-lab` |
| Kibana | `kibana` | same |
| Grafana | `grafana` | same |
| Prometheus | `prometheus` | same |
| Grafana Tempo | `grafana-tempo` | same |
| OpenTelemetry Collector | `opentelemetry-collector` | same |
| Logstash | `logstash` | same |

Deploy output shows **`Tag SM <name>: HTTP 202`** for each service when population succeeds. **`service_status`** may remain **requirements** until workload tags exist and the tag-based mapping job runs.

**Verify tags before blaming SM:** `cmdb_key_value.list` filtered on key `servicenow.io/application-service-identifier`. If rows are missing, complete [§6.3](#63-enable-automation-to-update-key-value-pairs) and re-run `discovery/docker/discover.yml`.

**Verify relationships:** `cmdb_rel_ci.list` with parent = Application Service sys_id and type **Contains::Contained by**. Trigger **Update map** in Service Mapping Workspace if **Contains** edges are slow to appear.

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/diagnose.yml -e @../vars/secrets.yaml
```

#### Manual fallback (UI or CLI)

Use these when automation is disabled (**`-e sn_csdm_configure_tag_sm=false`**) or for troubleshooting:

- **Service Mapping Workspace** → per-service **Tags** filter (same keys/values as the table above).
- **ServiceNow CLI** (`snc service-graph app-service populate` with `population_method.type: tag_list`) — see [Automating Application Service Registration](https://www.servicenow.com/community/cmdb-articles/automating-application-service-registration-with-best-practices/ta-p/3275122).
- **CSDM UI flow:** [Populate application services using tags](https://www.servicenow.com/docs/r/it-operations-management/service-mapping/map-service-tag.html).

Further context: [Tag_Based_Service_Mapping.md](Tag_Based_Service_Mapping.md), [DT_Problems_to_SN_Event.md](../observability/dynatrace/tenants/pdt20158/docs/DT_Problems_to_SN_Event.md#observability-application-services--tag-based-map-bootstrap-brooks-lab), [csdm/README.md](../../ansible/playbooks/servicenow/csdm/README.md).

---

## 7. Phase 4 — Dynatrace SGC and Event Management

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


| One-time prerequisite                                 | Why it cannot be automated                                                                |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Grant `admin_brooks_lab` the roles in the table below | A user cannot grant itself roles; requires an instance admin (Optimiz on the shared demo) |
| Plugin `**com.snc.ci_cd`** active                     | Provides the `sn_cicd` REST endpoints — the CI/CD API cannot activate itself              |
| Store entitlement / first-time license click-through  | Contractual acceptance is UI-only in ServiceNow Store                                     |


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


| #   | Actor                                                                                    | Step                                                                                                                                                                                                                 |
| --- | ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | instance admin (manual, once)                                                            | Create automation user, grant Phase 1–3 roles (§1–2); extend `**cmdb_key_value`** ACLs for `**cmdb_inst_admin**` ([§6.3](#63-enable-automation-to-update-key-value-pairs)) when using tag-based Docker/CSDM |
| 2   | instance admin (manual, once, **only if** the preflight reports the role record missing) | Activate plugin `com.snc.ci_cd` (System Definition → Plugins) — the CI/CD API cannot activate its own plugin                                                                                                         |
| 3   | instance admin (manual, once)                                                            | Grant `sn_cicd.sys_ci_automation`, `sn_appclient.app_client_user`, `evt_mgmt_admin`, and `connection_admin` (see the roles table) to `admin_brooks_lab`                                                              |
| 4   | automation                                                                               | Run `sgc/install.yml` — installs everything else; re-run after any grant                                                                                                                                             |
| 5   | operator (manual, once)                                                                  | Guided Setup (section E below)                                                                                                                                                                                       |


### Roles required by the automation user (`admin_brooks_lab`)


| Role                           | Needed for (tables / APIs)                                                                                                                                                                                                                                                          |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cmdb_inst_admin`              | CMDB tables — `cmdb_ci_*`, `cmdb_rel_ci`, `sys_object_source`; Identification/Reconciliation API `/api/now/identifyreconcile`. **Also requires** [§6.3 table ACL extension](#63-enable-automation-to-update-key-value-pairs) on `**cmdb_key_value`** for Docker label sync |
| `discovery_admin`              | Discovery configuration and status — `discovery_schedule`, `discovery_status`, `ecc_agent` (MID server), `ecc_queue`                                                                                                                                                                |
| `evt_mgmt_admin`               | Event Management — `em_event`, `em_alert`, event rules                                                                                                                                                                                                                              |
| `rest_service`                 | Inbound REST web-service access (basic-auth API calls as this user)                                                                                                                                                                                                                 |
| `sn_appclient.app_client_user` | `sys_store_app` read (App Manager visibility) — latest-version / update-available reporting in `diagnose.yml`. Not needed to install: the App Repo Install API takes the scope directly                                                                                             |
| `connection_admin`             | Connections & Credentials — `http_connection` (SGC connection Hostname set by `sgc/sources/dynatrace/deploy.yml`); `api_key_credentials` is writable without it                                                                                                                     |
| `sn_cicd.sys_ci_automation`    | CI/CD API — `/api/sn_cicd/app_repo/install` (by scope), `/api/sn_cicd/plugin/{id}/activate`, `/api/sn_cicd/progress/{id}` (plugin entitlement checks for CMDB 360 and SGC install)                                                                                                  |
| `snc_platform_rest_api_access` | Platform REST APIs — Table API `/api/now/table/*` (incl. `sys_scope`, `sys_user_role`, `sys_user_has_role`)                                                                                                                                                                         |


### Required Store applications and plugins (install order)

The authoritative manifest — names, scopes, install order, and **pinned
versions** — is `**sgc/common/store_apps.yml`** (`sn_store_apps`; sgc-local
because only the sgc playbooks consume it). `sgc/install.yml` consumes it;
`sgc/diagnose.yml` reports installed vs pinned vs latest versions. Update pins
there after a deliberate upgrade.

Install in this order. Later apps depend on earlier ones.


| #   | Name                                                  | Scope / ID                             | Type      | Purpose                                                   |
| --- | ----------------------------------------------------- | -------------------------------------- | --------- | --------------------------------------------------------- |
| 1   | Observability Commons for CMDB                        | `sn_observability`                     | Store app | Required before SGC; notification payload template step   |
| 2   | Integrations Commons for CMDB                         | `sn_cmdb_int_util`                     | Store app | IH/RTE/IRE commons for SGC                                |
| 3   | CMDB CI Class Model                                   | `sn_cmdb_ci_class`                     | Store app | CSDM class model for SGC mappers                          |
| 4   | ITOM Discovery License                                | `com.snc.itom.discovery.license`       | Plugin    | Discovery entitlement (usually already on ITOM instances) |
| 5   | Event Management                                      | `sn_em_ai`                             | Store app | `em_event` processing, push connector listener            |
| 6   | IntegrationHub Data Stream action type                | `com.glide.hub.action_type.datastream` | Plugin    | Required for SGC scheduled imports                        |
| 7   | Service Graph Connector for Observability – Dynatrace | `sn_dynatrace_integ`                   | Store app | SGC + Dynatrace push connector (`source=SGO-Dynatrace`)   |


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

Use an account with `**admin`** or `**sn_appclient.app_client_company_installer**`
(and Store access) — first-time UI installation requires the company-installer
role; `sn_appclient.app_client_user` alone does not grant it. For post-install
Ansible, also grant `admin_brooks_lab`:


| Additional role                  | Why                                                                                                                                                                          |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **evt_mgmt_admin**               | Read/create `em_event`; validate event integration                                                                                                                           |
| **sn_cicd.sys_ci_automation**    | App Repo Install + plugin activation API                                                                                                                                     |
| **sn_appclient.app_client_user** | Least-privilege read on `sys_store_app` (latest-version reporting); the installer role is **not** needed for the automated path — install authority comes from the CI/CD API |
| **cmdb_inst_admin**              | Already on automation user for Phases 1–3                                                                                                                                    |


Coordinate with **Optimiz / instance owners** before installing on a shared demo.

#### B. Request the Data Stream plugin (once per instance)

1. Navigate to **System Applications → All Available Applications → Request Plugin** (or **System Definition → Plugins**).
2. Search `**com.glide.hub.action_type.datastream`**.
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

#### Application maintain modes (`install.yml`)

Use when the scoped app is installed but instance metadata is corrupt (for
example Import Log `NullPointerException` on transform with orphaned RTE
field mappings):


| Mode              | Variable                    | API                                                         | When to use                                        |
| ----------------- | --------------------------- | ----------------------------------------------------------- | -------------------------------------------------- |
| Install (default) | `sn_sgc_app_mode=install`   | CI/CD App Repo Install                                      | Missing Store apps/plugins                         |
| Repair            | `sn_sgc_app_mode=repair`    | App Manager `GET .../app/repair?appId=&version=`            | Re-apply app files without uninstall               |
| Reinstall         | `sn_sgc_app_mode=reinstall` | App Manager `GET .../app/install?...&isReinstall=true`      | Full reinstall of same version                     |
| Reset (lab)       | `sn_sgc_app_mode=reset`     | REST DELETE orphaned RTE mappings + optional SGO CMDB purge | Fix Import NPE without admin UI; data rediscovered |


```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/install.yml \
  -e @../vars/secrets.yaml -e sn_sgc_app_mode=repair

# Lab instance — purge corrupt RTE metadata (no admin password required)
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/install.yml \
  -e @../vars/secrets.yaml -e sn_sgc_app_mode=reset
```

Target scope(s): `sn_sgc_maintain_scopes` (default `[sn_dynatrace_integ]`).

**Full uninstall + reinstall:** ServiceNow exposes **no CI/CD uninstall API**.
Uninstall (with **Retain tables and data** unchecked) requires **admin** or
`**sn_appclient.app_client_company_installer`** in the UI. The automation user
can install missing apps but cannot uninstall an installed version — CI/CD
`reinstall=true` fails with *Application version is currently installed*, and
App Manager repair/reinstall fails preprocessing with `id: null`.

**Reset mode (automated alternative):** When lab data may be discarded,
`reset` deletes orphaned `sys_rte_eb_field_mapping` rows across all
SGO-Dynatrace RTE feeds (the NPE root cause) and optionally purges CMDB /
`sys_object_source` rows with `discovery_source=SGO-Dynatrace`. The scoped app
stays installed; run `sources/dynatrace/deploy.yml` and
`sources/dynatrace/start.yml` afterward.

Set `sn_sgc_reset_purge_data=false` to skip CMDB / object-source deletion.

**Limits:** Repair/reinstall use the App Manager API, not
`/api/sn_cicd/app_repo/install` (which rejects an already-installed version).
The automation user may queue the job but fail preprocessing with
`Unable to process schema and dependencies for id: null` — in that case use
**System Applications → Applications → Service Graph Connector for
Observability - Dynatrace → Repair** with a full **admin** account (steps 1–3
below), then continue with steps 4–5.

**Version compatibility:** `diagnose.yml` and `install.yml` call
`common/validate_compatibility.yml`, which checks:

- ServiceNow platform family (from `glide.war`) against Store compatibilities
- Installed dependency versions against `sn_dynatrace_integ` Store-declared
dependencies (currently `sn_cmdb_int_util:2.25.0`, `sn_cmdb_ci_class:1.83.0`
for v1.15.0)
- Orphaned RTE field mappings on **SGO-Dynatrace Hosts** (transform NPE root cause)

Pins in `sgc/common/store_apps.yml` match the Store dependency matrix for
v1.15.0.

**After repair — run import (steps 4–5):**

1. `playbooks/servicenow/sgc/sources/dynatrace/start.yml` — queues Execute Now
  and monitors the cascade (or run Execute Now manually; see deploy.md).
2. Confirm Import Log has no `NullPointerException`; lab feeds reach `processed`.

#### E. Source deploy (mostly automated)

The connection, credential, management-zone scoping, and import-schedule
activation are automated by
`playbooks/servicenow/sgc/sources/dynatrace/deploy.yml`. **No Guided Setup
card requires manual configuration** — all six (app v1.14.x) are covered:


| Guided Setup card                    | Manual action needed                                                                        |
| ------------------------------------ | ------------------------------------------------------------------------------------------- |
| Enable Access To SNC.ImpactManager   | None — automated by `deploy.yml`                                                            |
| Basic (credential, connection, test) | None — automated by `deploy.yml`; optional *Test Connection* sanity check                   |
| Configure Dynatrace Grail OAuth      | None — optional feature, not used; Skip                                                     |
| Advanced                             | None — **do not run** *Configure Problem Notification* (owned by `events/deploy.yml`); Skip |
| Add Multiple Instances               | None — single-instance setup; Skip                                                          |
| Set up scheduled import jobs         | None — schedule activated by `deploy.yml`                                                   |


See `../sgc/sources/dynatrace/docs/deploy.md` for the detailed card map,
Dynatrace token model, and manual fallbacks. Remaining manual steps **outside**
the wizard:

1. Grant `connection_admin` to `admin_brooks_lab` (one-time; lets the playbook
  set the connection Hostname).
2. Optional: run Basic card **Test Connection** as a sanity check.

Import execution is automated by `sources/dynatrace/start.yml` after
`deploy.yml`. Then verify `**sys_object_source*`* rows with `name=SGO-Dynatrace` and CMDB
CIs with `discovery_source=SGO-Dynatrace` (`sgc/diagnose.yml`).

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


| Action                                                                                                          | Where                                            | Why not automated                                                                                                             |
| --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| Grant roles (`sn_cicd.sys_ci_automation`, `sn_appclient.app_client_user`, `evt_mgmt_admin`, `connection_admin`) | User Administration                              | Role grants require instance admin on the shared demo                                                                         |
| Configure **`security_admin`** elevation + operator profile | User Administration → Roles / Users | See [§6.3.1](#631-elevate-security_admin-prerequisite); required before ACL edits |
| Create **`cmdb_key_value`** Allow-if ACLs for **`cmdb_inst_admin`** (create, write, delete) | System Security → Access Control | Table ACL change requires elevated **`security_admin`**; read usually needs no change — see [§6.3](#63-enable-automation-to-update-key-value-pairs) |
| Store entitlement / license click-through                                                                       | ServiceNow Store / Subscriptions                 | Contractual acceptance is UI-only                                                                                             |
| Plugin request when CI/CD activation is denied                                                                  | System Definition → Plugins / HI case            | Strict instances gate plugin activation                                                                                       |
| Scheduled Data Imports first execution                                                                          | Dynatrace Observability → Scheduled Data Imports | Operator-triggered; monitor Concurrent Import Sets                                                                            |


**Required IDs / prerequisite configuration:**


| Variable                                           | Where                                               | Purpose                                                                          |
| -------------------------------------------------- | --------------------------------------------------- | -------------------------------------------------------------------------------- |
| `SN_DT_LEGACY_CONNECTOR_SYS_ID`                    | `vars/variables.yaml` (service-now)                 | Pre-existing legacy EM push connector (`712a39811…`) used until SGC is installed |
| `SN_URL`, `SN_INSTANCE_SHORT_NAME`                 | `vars/variables.yaml` (service-now)                 | Instance identity                                                                |
| `DT_API_URL`, `DT_API_TOKEN`, `DT_MANAGEMENT_ZONE` | `vars/variables.yaml` (dynatrace-ansible) / secrets | Dynatrace side                                                                   |
| `sn_store_apps`                                    | `sgc/common/store_apps.yml` (sgc-local)             | App/plugin manifest: scopes, install order, pinned versions                      |


Package `sys_id`s are **not** configuration and are not needed — `install.yml`
installs by application **scope** via the CI/CD App Repo Install API.

### Do not override others’ work (shared demo)

**Naming convention for brooks-lab automation:**


| System     | Prefix / name pattern                            | Examples                                             |
| ---------- | ------------------------------------------------ | ---------------------------------------------------- |
| Dynatrace  | `Spark Observability`, `Spark Lab`, `brooks-lab` | Alerting profile, metric event, problem notification |
| ServiceNow | `brooks-lab` location scope                      | CMDB rows, Discovery schedules                       |


**Ansible idempotency rules:**

- Dynatrace objects are upserted by **displayName/summary** (`Spark Observability - ServiceNow brooks-lab`, etc.) — does **not** modify `Default`, `DemoProfile - Optimiz`, or `**ServiceNow Demo 1 - Optimiz`**.
- Problem notification deploy **copies payload template** from pre-existing `ServiceNow Demo 1 - Optimiz` only when creating the brooks-lab notification; it does **not** update Demo 1.
- ServiceNow Discovery/K8/Docker playbooks scope to `**brooks-lab`** location and named schedules — they do not delete or reconfigure unrelated CMDB CIs.

**Pre-existing tenant configuration (not created by this repo):**


| Object                                                              | Status                                                                                             |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Dynatrace problem notification `**ServiceNow Demo 1 - Optimiz`**    | **Pre-existing** — webhook to `optimizincdemo1…/inbound_event?source=dynatrace&sys_id=712a39811…`  |
| ServiceNow EM push connector `**712a39811ba483105488a937b04bcba5`** | **Pre-existing** — referenced by Demo 1 notification; **not** created or modified by our playbooks |
| Dynatrace notification `**ServiceNow optimiz demo3`**               | **Pre-existing** — points at optimizincdemo3                                                       |


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


| Symptom                              | Check                                                                                                             |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| `deploy.yml` 403 on Discovery tables | `admin_brooks_lab` roles; run `diagnose.yml`                                                                      |
| `cmdb_key_value` REST insert 403     | Complete [§6.3](#63-enable-automation-to-update-key-value-pairs); re-run `discovery/docker/discover.yml` |
| MID stays Down                       | `mid_brooks_lab` has `mid_server`; password matches `config.xml`; `&` in password XML-escaped                     |
| MID user cannot run deploy           | Expected — use `admin_brooks_lab` (`SN_USER`)                                                                     |
| No CIs after scan                    | MID Up; schedule linked to range + credential; wait for scan completion                                           |
| Duplicate CIs                        | Hostnames must be `Lab1.lan`, `Lab2.lan`, `Lab3.lan` consistently                                                 |


---

## Related documentation

- [DT_SN_Specification_Guide.md](DT_SN_Specification_Guide.md) — **primary modeling guide** for CSDM, runtime labels, and Dynatrace alignment
- [Tag_Based_Service_Mapping.md](Tag_Based_Service_Mapping.md) — tag-based Service Mapping UI and `cmdb_key_value`
- [CSDM_Specifications.md](CSDM_Specifications.md) — CSDM YAML schema and deploy processor rules
- [DT_SN_Comparison_Process.md](DT_SN_Comparison_Process.md) — compare workflow (`servicenow/comparator/`)
- [../../ansible/playbooks/servicenow/README.md](../../ansible/playbooks/servicenow/README.md) — Ansible playbook layout
- [../../ansible/playbooks/servicenow/discovery/README.md](../../ansible/playbooks/servicenow/discovery/README.md) — discovery playbook verbs
- [../../ansible/playbooks/servicenow/discovery/docker/README.md](../../ansible/playbooks/servicenow/discovery/docker/README.md) — Docker container sync and label upsert
- [../../ansible/playbooks/servicenow/discovery/k8s/sync_pod_labels.yml](../../ansible/playbooks/servicenow/discovery/k8s/sync_pod_labels.yml) — Kubernetes pod label sync
- [../../ansible/playbooks/servicenow/discovery/host/sync_tags.yml](../../ansible/playbooks/servicenow/discovery/host/sync_tags.yml) — host agent tags on linux_server CIs
- [../../docs/architecture-and-resources.md](../../docs/architecture-and-resources.md) — Lab3 MID memory budget
- `tmp/ServiceNow_Dynatrace_Integration.md` — CMDB / Dynatrace design
- `tmp/Dynatrace-ServiceNow SGC.md` — SGC / IRE mapping
- `tmp/Dynatrace-ServiceNow-events.md` — event paths, field mapping, webhook comparison

